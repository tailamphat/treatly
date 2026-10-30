import CoreAudio
import Foundation

/// Notices when a music or video app is playing sound, so the pet can sit and
/// listen along. It asks Core Audio which apps are sending sound to the speakers,
/// which needs no permission and never sees what is playing. Other apps (alerts,
/// apps that keep the speakers open while silent, the pet itself) don't count.
@MainActor
final class MusicListener {
    /// True once music has been playing for a few seconds, false a few seconds after it stops.
    private(set) var isPlaying = false
    private var since: Date?
    private var timer: Timer?

    /// How long music has to keep playing (or stay quiet) before the pet reacts.
    private let settle: TimeInterval = 3

    /// Apps that play music or video, by bundle id prefix (helpers included).
    static let mediaApps = [
        "com.apple.Music", "com.apple.podcasts", "com.apple.TV", "com.apple.QuickTimePlayerX",
        "com.apple.WebKit.GPU", "com.apple.Safari",
        "com.spotify.client", "com.tidal.desktop", "com.amazon.music", "com.deezer", "com.pandora",
        "com.google.Chrome", "company.thebrowser", "org.mozilla.firefox", "com.microsoft.edgemac",
        "com.brave.Browser", "com.operasoftware", "com.vivaldi",
        "org.videolan.vlc", "com.colliderli.iina", "com.soundcloud", "com.bandcamp",
    ]

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    private func poll() {
        let playing = Self.mediaIsPlaying()
        if playing == isPlaying {
            since = nil
        } else if let since {
            if Date().timeIntervalSince(since) >= settle { isPlaying = playing; self.since = nil }
        } else {
            since = Date()
        }
    }

    static func isMediaApp(_ bundleID: String) -> Bool {
        mediaApps.contains { bundleID.hasPrefix($0) }
    }

    /// Whether any music or video app is sending sound to an output right now.
    private static func mediaIsPlaying() -> Bool {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return false }
        var processes = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &processes) == noErr else { return false }
        return processes.contains { process in
            var running: UInt32 = 0
            var runningSize = UInt32(MemoryLayout<UInt32>.size)
            var runningAddress = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyIsRunningOutput,
                                                            mScope: kAudioObjectPropertyScopeGlobal,
                                                            mElement: kAudioObjectPropertyElementMain)
            guard AudioObjectGetPropertyData(process, &runningAddress, 0, nil, &runningSize, &running) == noErr, running != 0 else { return false }
            var bundleID: Unmanaged<CFString>?
            var idSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            var idAddress = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyBundleID,
                                                       mScope: kAudioObjectPropertyScopeGlobal,
                                                       mElement: kAudioObjectPropertyElementMain)
            guard AudioObjectGetPropertyData(process, &idAddress, 0, nil, &idSize, &bundleID) == noErr,
                  let id = bundleID?.takeRetainedValue() as String? else { return false }
            return isMediaApp(id)
        }
    }
}
