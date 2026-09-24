import Foundation

/// Edits to a finished capture from the filmstrip (spec §3.4).
public enum FrameEditing {
    /// Removes frames whose frameIndex is in `frameIndices` (spec §3.4).
    /// A removed frame's actions are appended to the previous remaining frame.
    /// Actions from removed frames before the first remaining frame are prepended to it.
    public static func removing(frameIndices: Set<Int>, from frames: [PickedFrame]) -> [PickedFrame] {
        var remaining: [PickedFrame] = []
        var leading: [StepAction] = []
        for frame in frames {
            if frameIndices.contains(frame.frameIndex) {
                if remaining.isEmpty {
                    leading += frame.actions
                } else {
                    remaining[remaining.count - 1].actions += frame.actions
                }
            } else {
                var frame = frame
                frame.actions = leading + frame.actions
                leading = []
                remaining.append(frame)
            }
        }
        return remaining
    }
}
