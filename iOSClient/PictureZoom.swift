import CoreGraphics
import Foundation

/// The picture's own zoom on the device: a pinch on the stream magnifies the video here, and the Mac
/// is told nothing (its window keeps its size, unlike the Aa control). Two views read it with the
/// same bounds, since they fill the same pane: `HEVCDisplayView` draws the video magnified, and
/// `InputOverlayView` maps a touch through the same magnification, so a tap on the magnified picture
/// clicks what it shows. Main thread.
///
/// The zoom is a scale about the pane's centre, then a move (`offset`, in pane points). A point `p`
/// of the unmagnified pane is drawn at `c + scale·(p − c) + offset`, `c` the pane's centre. The
/// offset drawn is always `clamped`: the magnified picture never uncovers more of the pane than it
/// has to, and stays centred along an axis where it is still smaller than the pane. Held at read
/// time too, so a rotation or a layout change that resizes the pane needs no reset.
final class PictureZoom {
    /// The most the picture is magnified: a desktop on a phone's picture reaches the Mac's own points
    /// at about 4×.
    static let maxScale: CGFloat = 5
    /// A pinch that ends below this springs back to the whole picture.
    static let snapScale: CGFloat = 1.1
    /// A two-finger double tap on the whole picture magnifies it this much.
    static let tapScale: CGFloat = 2

    private(set) var scale: CGFloat = 1
    private(set) var offset: CGPoint = .zero
    /// The display view moves its layer with every change (`StreamView` sets it); `animated` for a
    /// reset or a double tap, never for a pinch, which follows the fingers.
    var onChange: ((_ animated: Bool) -> Void)?

    var isZoomed: Bool { scale > 1 }

    /// The scale and the offset drawn in a pane of `bounds`, whose unmagnified video rect is `video`.
    func drawn(in bounds: CGRect, video: CGRect) -> (scale: CGFloat, offset: CGPoint) {
        (scale, Self.clamped(offset, scale: scale, pane: bounds.size, video: video.size))
    }

    /// Where `video`, the unmagnified video rect in a pane of `bounds`, is drawn magnified.
    func zoomed(_ video: CGRect, in bounds: CGRect) -> CGRect {
        let (s, t) = drawn(in: bounds, video: video)
        guard s != 1 || t != .zero else { return video }
        return CGRect(x: bounds.midX + s * (video.minX - bounds.midX) + t.x,
                      y: bounds.midY + s * (video.minY - bounds.midY) + t.y,
                      width: video.width * s, height: video.height * s)
    }

    /// A pinch's step: the scale times `factor`, held between 1 and `maxScale`, about `focus` (the
    /// point between the fingers), so what is under the fingers stays under them.
    func pinch(by factor: CGFloat, at focus: CGPoint, in bounds: CGRect, video: CGRect) {
        let (s0, t0) = drawn(in: bounds, video: video)
        let s1 = min(max(s0 * factor, 1), Self.maxScale)
        guard s1 != s0 else { return }
        set(scale: s1, offset: Self.offset(keeping: focus, from: s0, t0, to: s1, in: bounds),
            in: bounds, video: video, animated: false)
    }

    /// Two fingers moving the magnified picture by `delta` points.
    func pan(by delta: CGPoint, in bounds: CGRect, video: CGRect) {
        guard isZoomed, delta != .zero else { return }
        let t = drawn(in: bounds, video: video).offset
        set(scale: scale, offset: CGPoint(x: t.x + delta.x, y: t.y + delta.y), in: bounds, video: video, animated: false)
    }

    /// A pinch's end: below `snapScale` the picture springs back whole.
    func settle(in bounds: CGRect, video: CGRect) {
        if scale < Self.snapScale { reset(animated: true) }
    }

    /// A two-finger double tap: the whole picture again, or `tapScale` about `focus`.
    func toggle(at focus: CGPoint, in bounds: CGRect, video: CGRect) {
        if isZoomed { reset(animated: true); return }
        set(scale: Self.tapScale, offset: Self.offset(keeping: focus, from: 1, .zero, to: Self.tapScale, in: bounds),
            in: bounds, video: video, animated: true)
    }

    /// The whole picture: a new source or a new frame size, or the person's double tap.
    func reset(animated: Bool) {
        guard scale != 1 || offset != .zero else { return }
        scale = 1
        offset = .zero
        onChange?(animated)
    }

    private func set(scale s: CGFloat, offset t: CGPoint, in bounds: CGRect, video: CGRect, animated: Bool) {
        scale = s
        offset = Self.clamped(t, scale: s, pane: bounds.size, video: video.size)
        onChange?(animated)
    }

    /// The offset that keeps the pane point `focus` on the same picture point as the scale goes from
    /// `s0` (with offset `t0`) to `s1`.
    static func offset(keeping focus: CGPoint, from s0: CGFloat, _ t0: CGPoint, to s1: CGFloat, in bounds: CGRect) -> CGPoint {
        let k = s1 / s0
        return CGPoint(x: (focus.x - bounds.midX) - k * (focus.x - bounds.midX - t0.x),
                       y: (focus.y - bounds.midY) - k * (focus.y - bounds.midY - t0.y))
    }

    /// `offset` held so a picture of `video` size magnified by `scale` covers as much of `pane` as it
    /// can: zero along an axis where it is no larger than the pane.
    static func clamped(_ offset: CGPoint, scale: CGFloat, pane: CGSize, video: CGSize) -> CGPoint {
        let rx = max(0, (video.width * scale - pane.width) / 2)
        let ry = max(0, (video.height * scale - pane.height) / 2)
        return CGPoint(x: min(max(offset.x, -rx), rx), y: min(max(offset.y, -ry), ry))
    }
}
