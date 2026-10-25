import Foundation

/// Device → host (kind 34): an area of the streamed picture the person framed with a finger, as
/// fractions of the video frame (0 to 1 from the top left). The host puts that part of the picture
/// it last sent on the Mac's clipboard, as a PNG (Alexis, 2026-10-25). Sent only to a host whose
/// window list says `captureRegion` 1.
public struct CaptureRegion: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }

    /// The region inside the frame, or nil when nothing of it is left (or a value is not a number).
    public var clamped: CaptureRegion? {
        guard [x, y, width, height].allSatisfy(\.isFinite) else { return nil }
        let left = min(max(x, 0), 1), top = min(max(y, 0), 1)
        let right = min(max(x + width, 0), 1), bottom = min(max(y + height, 0), 1)
        guard right - left > 0.001, bottom - top > 0.001 else { return nil }
        return CaptureRegion(x: left, y: top, width: right - left, height: bottom - top)
    }
}
