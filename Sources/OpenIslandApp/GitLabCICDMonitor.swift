import Foundation
import OpenIslandCore

struct GitLabPipelineSnapshot: Equatable, Sendable {
    var id: Int
    var iid: Int
    var projectID: Int
    var projectName: String
    var ref: String
    var status: String
    var webURL: String
    var createdAt: Date

    var isTerminal: Bool {
        ["success", "failed", "canceled", "skipped", "manual"].contains(status)
    }
}

struct GitLabWatchProject: Equatable, Sendable {
    var apiBaseURL: URL
    var token: String
    var projectPath: String
}

@MainActor
final class GitLabCICDMonitor {
    var onEvent: ((AgentEvent) -> Void)?

    private let projectsProvider: @Sendable () -> [GitLabWatchProject]
    private let fetchPipelines: @Sendable (GitLabWatchProject) async throws -> [GitLabPipelineSnapshot]
    private let pollInterval: Duration
    private var task: Task<Void, Never>?
    private var lastStatusByPipelineID: [String: String] = [:]
    private var didPrime = false

    init(
        pollInterval: Duration = .seconds(15),
        projectsProvider: @escaping @Sendable () -> [GitLabWatchProject] = GitLabCICDMonitor.defaultProjects,
        fetchPipelines: @escaping @Sendable (GitLabWatchProject) async throws -> [GitLabPipelineSnapshot] = GitLabCICDMonitor.fetchPipelines
    ) {
        self.pollInterval = pollInterval
        self.projectsProvider = projectsProvider
        self.fetchPipelines = fetchPipelines
    }

    deinit {
        task?.cancel()
    }

    func startIfNeeded() {
        guard task == nil else { return }
        task = Task { [weak self] in
            await self?.run()
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    func pollOnceForTesting() async {
        await pollOnce()
    }

    private func run() async {
        while !Task.isCancelled {
            await pollOnce()
            try? await Task.sleep(for: pollInterval)
        }
    }

    private func pollOnce() async {
        let projects = projectsProvider()
        guard !projects.isEmpty else { return }

        var snapshots: [GitLabPipelineSnapshot] = []
        for project in projects {
            if let pipelines = try? await fetchPipelines(project) {
                snapshots.append(contentsOf: pipelines)
            }
        }
        snapshots.sort { $0.createdAt < $1.createdAt }

        if !didPrime {
            for snapshot in snapshots {
                lastStatusByPipelineID[sessionID(for: snapshot)] = snapshot.status
            }
            didPrime = true
            return
        }

        for snapshot in snapshots {
            let key = sessionID(for: snapshot)
            let oldStatus = lastStatusByPipelineID[key]
            guard oldStatus != snapshot.status else { continue }

            if oldStatus == nil {
                onEvent?(startedEvent(for: snapshot))
            }
            if snapshot.isTerminal {
                onEvent?(completedEvent(for: snapshot))
            } else if oldStatus != nil {
                onEvent?(activityEvent(for: snapshot))
            }
            lastStatusByPipelineID[key] = snapshot.status
        }
    }

    private func startedEvent(for snapshot: GitLabPipelineSnapshot) -> AgentEvent {
        .sessionStarted(SessionStarted(
            sessionID: sessionID(for: snapshot),
            title: title(for: snapshot),
            tool: .factory,
            origin: .live,
            initialPhase: .running,
            summary: "CI/CD started on \(snapshot.ref)",
            timestamp: .now,
            isRemote: true
        ))
    }

    private func activityEvent(for snapshot: GitLabPipelineSnapshot) -> AgentEvent {
        .activityUpdated(SessionActivityUpdated(
            sessionID: sessionID(for: snapshot),
            summary: "CI/CD \(snapshot.status) on \(snapshot.ref)",
            phase: .running,
            timestamp: .now
        ))
    }

    private func completedEvent(for snapshot: GitLabPipelineSnapshot) -> AgentEvent {
        .sessionCompleted(SessionCompleted(
            sessionID: sessionID(for: snapshot),
            summary: "CI/CD \(snapshot.status) on \(snapshot.ref)",
            timestamp: .now,
            isSessionEnd: true
        ))
    }

    private func sessionID(for snapshot: GitLabPipelineSnapshot) -> String {
        "gitlab-\(snapshot.projectID)-\(snapshot.id)"
    }

    private func title(for snapshot: GitLabPipelineSnapshot) -> String {
        "CI/CD · \(snapshot.projectName) #\(snapshot.iid)"
    }

    nonisolated static func defaultProjects() -> [GitLabWatchProject] {
        configuredWatchPaths().compactMap(projectFromGitRemote(at:))
    }

    nonisolated private static func configuredWatchPaths() -> [String] {
        if let value = ProcessInfo.processInfo.environment["OPEN_ISLAND_GITLAB_CICD_PATHS"], !value.isEmpty {
            return value.split(separator: ":").map(String.init)
        }
        return ["~/Documents/workspace/Lenovo/ssc_airflow_36_env"]
    }

    nonisolated private static func projectFromGitRemote(at rawPath: String) -> GitLabWatchProject? {
        let path = (rawPath as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        guard let remote = gitRemoteURL(at: path) else { return nil }
        return parseGitLabRemote(remote)
    }

    nonisolated private static func gitRemoteURL(at path: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", path, "config", "--get", "remote.origin.url"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try? process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated static func parseGitLabRemote(_ remote: String) -> GitLabWatchProject? {
        guard remote.hasPrefix("https://") else { return nil }
        guard let markerRange = remote.range(of: "@") else { return nil }

        let credential = String(remote[remote.index(remote.startIndex, offsetBy: "https://".count)..<markerRange.lowerBound])
        guard credential.hasPrefix("oauth2:") else { return nil }
        let token = String(credential.dropFirst("oauth2:".count))
        guard !token.isEmpty else { return nil }

        let rest = String(remote[markerRange.upperBound...])
        let pieces = rest.split(separator: "/", maxSplits: 1)
        guard pieces.count == 2 else { return nil }

        let host = pieces[0]
        let projectPath = pieces[1].replacingOccurrences(of: ".git", with: "")
        guard !projectPath.isEmpty else { return nil }

        return GitLabWatchProject(
            apiBaseURL: URL(string: "https://\(host)/api/v4")!,
            token: token,
            projectPath: projectPath
        )
    }

    nonisolated static func fetchPipelines(for project: GitLabWatchProject) async throws -> [GitLabPipelineSnapshot] {
        let encodedProject = project.projectPath.addingPercentEncoding(withAllowedCharacters: .gitLabProjectPath) ?? project.projectPath
        var components = URLComponents(string: "\(project.apiBaseURL.absoluteString)/projects/\(encodedProject)/pipelines")!
        components.queryItems = [URLQueryItem(name: "per_page", value: "5")]
        var request = URLRequest(url: components.url!)
        request.addValue(project.token, forHTTPHeaderField: "PRIVATE-TOKEN")

        let (data, _) = try await URLSession.shared.data(for: request)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([GitLabPipelineDTO].self, from: data).map {
            GitLabPipelineSnapshot(
                id: $0.id,
                iid: $0.iid,
                projectID: $0.projectID,
                projectName: project.projectPath.split(separator: "/").last.map(String.init) ?? project.projectPath,
                ref: $0.ref,
                status: $0.status,
                webURL: $0.webURL,
                createdAt: $0.createdAt
            )
        }
    }
}

private struct GitLabPipelineDTO: Decodable {
    var id: Int
    var iid: Int
    var projectID: Int
    var ref: String
    var status: String
    var webURL: String
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case iid
        case projectID = "project_id"
        case ref
        case status
        case webURL = "web_url"
        case createdAt = "created_at"
    }
}

private extension CharacterSet {
    static let gitLabProjectPath: CharacterSet = {
        var set = CharacterSet.urlPathAllowed
        set.remove(charactersIn: "/")
        return set
    }()
}
