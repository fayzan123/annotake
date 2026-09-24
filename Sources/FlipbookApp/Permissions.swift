import ApplicationServices
import CoreGraphics

/// The three permissions (spec §3.7, §7).
enum Permissions {
    /// kAXTrustedCheckOptionPrompt's value; the C global isn't concurrency-safe in Swift 6.
    static let promptOption = "AXTrustedCheckOptionPrompt"

    struct Status: Equatable {
        var screenRecording: Bool
        var inputMonitoring: Bool
        var accessibility: Bool

        var anyMissing: Bool { !(screenRecording && inputMonitoring && accessibility) }
    }

    /// Input Monitoring is checked with CGPreflightListenEventAccess, never by whether a tap was created.
    static func status() -> Status {
        Status(screenRecording: CGPreflightScreenCaptureAccess(), inputMonitoring: CGPreflightListenEventAccess(),
               accessibility: AXIsProcessTrusted())
    }

    /// The system prompt for each missing permission, at launch. The first-launch checklist replaces this.
    static func requestMissing() {
        let status = status()
        log("permissions: screen recording \(status.screenRecording), input monitoring \(status.inputMonitoring), "
            + "accessibility \(status.accessibility)")
        if !status.screenRecording { CGRequestScreenCaptureAccess() }
        if !status.inputMonitoring { CGRequestListenEventAccess() }
        if !status.accessibility {
            AXIsProcessTrustedWithOptions([promptOption: true] as CFDictionary)
        }
    }
}
