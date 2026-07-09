import AppKit

enum OpenIslandEventSound: String, CaseIterable, Identifiable {
    case startup
    case thinking
    case completed
    case failed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .startup: "Poke Island startup"
        case .thinking: "User message / thinking"
        case .completed: "Model replied"
        case .failed: "Failure / exception"
        }
    }

    var defaultPath: String {
        switch self {
        case .startup:
            "/Users/jarnoyuan/Music/网易云音乐/Funta - Music Start!.mp3"
        case .thinking:
            "/Users/jarnoyuan/Music/网易云音乐/岩田恭明 - ゲットファンファーレ (アイテム).mp3"
        case .completed:
            "/Users/jarnoyuan/Music/网易云音乐/景山将太 - たいせつな道具を手に入れた!.mp3"
        case .failed:
            "/Users/jarnoyuan/Music/网易云音乐/船橋淳,中島正恵,宮脇聡子 - Life Lost.mp3"
        }
    }

    var defaultsKey: String {
        "event.sound.\(rawValue).path"
    }
}

/// Manages notification sound playback using macOS system sounds.
@MainActor
struct NotificationSoundService {
    private static let soundsDirectory = "/System/Library/Sounds"
    private static let defaultsKey = "notification.sound.name"
    private static var activeSounds: [String: NSSound] = [:]
    static let defaultSoundName = "Bottle"

    /// Returns the list of available system sound names (without file extension).
    static func availableSounds() -> [String] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: soundsDirectory) else {
            return []
        }
        return contents
            .filter { $0.hasSuffix(".aiff") }
            .map { ($0 as NSString).deletingPathExtension }
            .sorted()
    }

    /// The currently selected sound name, persisted in UserDefaults.
    static var selectedSoundName: String {
        get {
            UserDefaults.standard.string(forKey: defaultsKey) ?? defaultSoundName
        }
        set {
            UserDefaults.standard.set(newValue, forKey: defaultsKey)
        }
    }

    /// Plays a system sound by name.
    static func play(_ name: String) {
        guard let sound = NSSound(named: NSSound.Name(name)) else {
            return
        }
        sound.stop()
        sound.play()
    }

    static func eventSoundPath(for event: OpenIslandEventSound) -> String {
        UserDefaults.standard.string(forKey: event.defaultsKey) ?? event.defaultPath
    }

    static func setEventSoundPath(_ path: String, for event: OpenIslandEventSound) {
        UserDefaults.standard.set(path, forKey: event.defaultsKey)
    }

    static func resetEventSoundPath(for event: OpenIslandEventSound) {
        UserDefaults.standard.removeObject(forKey: event.defaultsKey)
    }

    static func playEvent(_ event: OpenIslandEventSound, isMuted: Bool) {
        guard !isMuted else { return }
        playFile(path: eventSoundPath(for: event))
    }

    /// Plays the user-selected notification sound, respecting the mute setting.
    static func playNotification(isMuted: Bool) {
        guard !isMuted else { return }
        play(selectedSoundName)
    }

    private static func playFile(path: String) {
        let url = URL(fileURLWithPath: path)
        let key = url.path
        let sound = activeSounds[key] ?? NSSound(contentsOf: url, byReference: true)
        guard let sound else { return }
        activeSounds[key] = sound
        sound.stop()
        sound.currentTime = 0
        sound.play()
    }
}
