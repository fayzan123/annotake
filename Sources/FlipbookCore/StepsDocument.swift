import Foundation

/// The text of `steps.md` (spec §4.3).
public enum StepsDocument {
    /// captureName e.g. "2026-09-23 at 14.05.12"; target e.g. "Screen: Built-in Retina Display"
    public static func render(_ result: PickResult, captureName: String, target: String) -> String {
        let total = result.frames.count
        var lines = [
            "# Flipbook capture — \(captureName)",
            "\(target) · \(Captions.timestamp(result.duration)) · \(counted(total, "frame")) "
                + "(from \(counted(result.candidateCount, "candidate")))",
            "",
        ]
        for (offset, frame) in result.frames.enumerated() {
            let number = offset + 1
            lines.append("\(number). \(Captions.timestamp(frame.time)) · \(Captions.line2(for: frame.context)) · "
                + Captions.summary(for: frame, number: number, total: total))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func counted(_ count: Int, _ noun: String) -> String {
        count == 1 ? "1 \(noun)" : "\(count) \(noun)s"
    }
}
