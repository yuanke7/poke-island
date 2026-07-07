import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

@MainActor
struct GitLabCICDMonitorTests {
    @Test
    func parsesOAuthGitLabRemote() throws {
        let project = try #require(GitLabCICDMonitor.parseGitLabRemote(
            "https://oauth2:token123@gitlab.xpaas.lenovo.com:443/yuankq1/ssc-ariflow.git"
        ))

        #expect(project.apiBaseURL.absoluteString == "https://gitlab.xpaas.lenovo.com:443/api/v4")
        #expect(project.token == "token123")
        #expect(project.projectPath == "yuankq1/ssc-ariflow")
    }

    @Test
    func emitsStartedAndCompletedEventsForNewPipeline() async {
        let project = GitLabWatchProject(
            apiBaseURL: URL(string: "https://gitlab.example/api/v4")!,
            token: "token",
            projectPath: "yuankq1/ssc-ariflow"
        )
        let eventBox = EventBox()
        let createdAt = Date(timeIntervalSince1970: 1_000)
        let pipelineBox = PipelineBox([
            GitLabPipelineSnapshot(
                id: 1,
                iid: 10,
                projectID: 99,
                projectName: "ssc-ariflow",
                ref: "36_env",
                status: "running",
                webURL: "https://gitlab.example/pipelines/1",
                createdAt: createdAt
            )
        ])

        let monitor = GitLabCICDMonitor(
            projectsProvider: { [project] in [project] },
            fetchPipelines: { _ in await pipelineBox.snapshots() }
        )
        monitor.onEvent = { event in
            eventBox.append(event)
        }

        await monitor.pollOnceForTesting()
        eventBox.expectCount(0)

        await pipelineBox.updateStatus("success")
        await monitor.pollOnceForTesting()

        let events = eventBox.events
        #expect(events.count == 1)
        guard case let .sessionCompleted(payload) = events.first else {
            Issue.record("Expected completion event")
            return
        }
        #expect(payload.sessionID == "gitlab-99-1")
        #expect(payload.summary == "CI/CD success on 36_env")
    }

    @Test
    func emitsStartAndCompletionWhenFastPipelineFirstAppearsCompleted() async {
        let project = GitLabWatchProject(
            apiBaseURL: URL(string: "https://gitlab.example/api/v4")!,
            token: "token",
            projectPath: "yuankq1/ssc-ariflow"
        )
        let eventBox = EventBox()
        let pipelineBox = PipelineBox([])

        let monitor = GitLabCICDMonitor(
            projectsProvider: { [project] in [project] },
            fetchPipelines: { _ in await pipelineBox.snapshots() }
        )
        monitor.onEvent = { event in
            eventBox.append(event)
        }

        await monitor.pollOnceForTesting()

        await pipelineBox.set([
            GitLabPipelineSnapshot(
                id: 2,
                iid: 11,
                projectID: 99,
                projectName: "ssc-ariflow",
                ref: "36_env",
                status: "success",
                webURL: "https://gitlab.example/pipelines/2",
                createdAt: Date(timeIntervalSince1970: 1_001)
            )
        ])
        await monitor.pollOnceForTesting()

        let events = eventBox.events
        #expect(events.count == 2)
        guard case let .sessionStarted(started) = events.first,
              case let .sessionCompleted(completed) = events.last else {
            Issue.record("Expected start then completion")
            return
        }
        #expect(started.title == "CI/CD · ssc-ariflow #11")
        #expect(completed.summary == "CI/CD success on 36_env")
    }
}

private actor PipelineBox {
    private var storage: [GitLabPipelineSnapshot]

    init(_ storage: [GitLabPipelineSnapshot]) {
        self.storage = storage
    }

    func snapshots() -> [GitLabPipelineSnapshot] {
        storage
    }

    func set(_ snapshots: [GitLabPipelineSnapshot]) {
        storage = snapshots
    }

    func updateStatus(_ status: String) {
        storage[0].status = status
    }
}

private final class EventBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [AgentEvent] = []

    var events: [AgentEvent] {
        lock.withLock { storage }
    }

    func append(_ event: AgentEvent) {
        lock.withLock {
            storage.append(event)
        }
    }

    func expectCount(_ count: Int) {
        #expect(events.count == count)
    }
}
