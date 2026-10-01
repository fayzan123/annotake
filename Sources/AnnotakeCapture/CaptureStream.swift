import CoreMedia
import AnnotakeCore
@preconcurrency import ScreenCaptureKit

public enum CaptureError: Error, Equatable {
    case permissionDenied
    case contentUnavailable
    /// The recorded window closed or the display went away.
    case targetGone
    case streamFailed(String)
}

/// One complete frame from the stream.
public struct CapturedFrame: @unchecked Sendable {
    /// Counts complete frames from 0.
    public let index: Int
    public let pixelBuffer: CVPixelBuffer
    /// Changed regions in output pixels, top-left origin, rounded outward.
    public let dirtyRects: [PixelRect]
    /// Where the captured content is on screen, in global points (used in window mode).
    public let screenRect: CGRect?
}

/// An SCStream delivering complete BGRA frames at up to 10 fps (spec §5.1).
/// Frames are delivered on the queue passed to `start`; its counters are only touched there.
public final class CaptureStream: NSObject, @unchecked Sendable {
    public static let framesPerSecond: Int32 = 10
    public static let queueDepth = 8

    private var stream: SCStream?
    private var onFrame: (@Sendable (CapturedFrame) -> Void)?
    private var onEnd: (@Sendable (CaptureError?) -> Void)?
    /// Complete frames delivered so far.
    public private(set) var completeFrames = 0
    /// Frames that arrived with nothing new to show.
    public private(set) var idleFrames = 0

    override public init() {
        super.init()
    }

    public func start(filter: SCContentFilter, output: OutputSize, showsCursor: Bool, queue: DispatchQueue,
                      onFrame: @escaping @Sendable (CapturedFrame) -> Void,
                      onEnd: @escaping @Sendable (CaptureError?) -> Void) async throws {
        self.onFrame = onFrame
        self.onEnd = onEnd
        let configuration = SCStreamConfiguration()
        configuration.width = output.width
        configuration.height = output.height
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: Self.framesPerSecond)
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = showsCursor
        configuration.queueDepth = Self.queueDepth
        configuration.colorSpaceName = CGColorSpace.sRGB
        configuration.capturesAudio = false
        if filter.style == .window {
            configuration.ignoreShadowsSingleWindow = true
            configuration.scalesToFit = false
        }
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        do {
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
            try await stream.startCapture()
        } catch {
            throw Self.captureError(error)
        }
        self.stream = stream
    }

    public func stop() async {
        guard let stream else { return }
        self.stream = nil
        try? await stream.stopCapture()
    }

    static func captureError(_ error: Error) -> CaptureError {
        let error = error as NSError
        guard error.domain == SCStreamErrorDomain, let code = SCStreamError.Code(rawValue: error.code) else {
            return .streamFailed(error.localizedDescription)
        }
        switch code {
        case .userDeclined: return .permissionDenied
        case .noCaptureSource, .noWindowList, .noDisplayList: return .targetGone
        default: return .streamFailed("\(code.rawValue) \(error.localizedDescription)")
        }
    }
}

extension CaptureStream: SCStreamOutput, SCStreamDelegate {
    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                       of type: SCStreamOutputType) {
        guard type == .screen,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let info = attachments.first,
              let rawStatus = info[.status] as? Int
        else { return }
        guard rawStatus == SCFrameStatus.complete.rawValue, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            if rawStatus == SCFrameStatus.idle.rawValue { idleFrames += 1 }
            return
        }
        let dirtyRects = (info[.dirtyRects] as? [Any] ?? []).compactMap(Self.rect).map(Self.pixelRect)
        let screenRect = info[.screenRect].flatMap(Self.rect)
        let frame = CapturedFrame(index: completeFrames, pixelBuffer: pixelBuffer, dirtyRects: dirtyRects,
                                  screenRect: screenRect)
        completeFrames += 1
        onFrame?(frame)
    }

    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        onEnd?(Self.captureError(error))
    }

    /// Frame-info rects arrive as CGRect dictionaries (M0) or NSValues (the header's description).
    private static func rect(_ value: Any) -> CGRect? {
        if let value = value as? NSValue, String(cString: value.objCType).hasPrefix("{CGRect") {
            return value.rectValue
        }
        guard CFGetTypeID(value as CFTypeRef) == CFDictionaryGetTypeID() else { return nil }
        return CGRect(dictionaryRepresentation: value as! CFDictionary)
    }

    private static func pixelRect(_ rect: CGRect) -> PixelRect {
        let minX = Int(rect.minX.rounded(.down)), minY = Int(rect.minY.rounded(.down))
        return PixelRect(x: minX, y: minY,
                         width: Int(rect.maxX.rounded(.up)) - minX, height: Int(rect.maxY.rounded(.up)) - minY)
    }
}
