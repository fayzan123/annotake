import AppKit

/// Soft start and stop sounds (spec §3.2). Neither plays on a discard or cancel.
@MainActor
enum Sounds {
    static let volume: Float = 0.35
    private static let start = sound("Tink")
    private static let stop = sound("Pop")

    static func playStart() { play(start) }
    static func playStop() { play(stop) }

    private static func sound(_ name: String) -> NSSound? {
        let sound = NSSound(named: NSSound.Name(name))
        sound?.volume = volume
        return sound
    }

    private static func play(_ sound: NSSound?) {
        sound?.stop()
        sound?.play()
    }
}
