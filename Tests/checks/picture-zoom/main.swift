// iOSClient/PictureZoom.swift on its own, the device's own zoom of the picture: whole by default, a pinch
// that keeps what is under the fingers under them, the scale held between whole and maxScale, the offset
// held so the magnified picture covers the pane (centred along an axis where it is smaller), a move only
// while magnified, the spring back below snapScale, the two-finger double tap both ways, the change hook's
// animation flag, a pane resized under a magnified picture. Then the map itself: what HEVCDisplayView draws
// (its video layer scaled about the pane's centre and moved) is exactly the rect InputOverlayView maps a
// touch through, for 5,000 random panes, frames and pinches.
//   swiftc -O iOSClient/PictureZoom.swift Tests/checks/picture-zoom/main.swift -o check && ./check
import CoreGraphics
import Foundation

var fails = 0, passes = 0
func check(_ name: String, _ ok: Bool) { if ok { passes += 1; print("ok   \(name)") } else { fails += 1; print("FAIL \(name)") } }
func near(_ a: CGFloat, _ b: CGFloat, _ e: CGFloat = 1e-6) -> Bool { abs(a - b) <= e * max(1, abs(a), abs(b)) }
func near(_ a: CGPoint, _ b: CGPoint) -> Bool { near(a.x, b.x) && near(a.y, b.y) }
func near(_ a: CGRect, _ b: CGRect) -> Bool { near(a.origin, b.origin) && near(a.width, b.width) && near(a.height, b.height) }

/// The letterboxed rect, as HEVCDisplayView.videoRect gives it (copied: that file needs UIKit).
func letterbox(_ bounds: CGRect, _ frame: CGSize) -> CGRect {
    let s = min(bounds.width / frame.width, bounds.height / frame.height)
    let size = CGSize(width: frame.width * s, height: frame.height * s)
    return CGRect(x: bounds.minX + (bounds.width - size.width) / 2, y: bounds.minY + (bounds.height - size.height) / 2,
                  width: size.width, height: size.height)
}

/// Where a pane point shows the picture point `p` (fractions of the frame), through the zoomed rect.
func shown(_ p: CGPoint, _ r: CGRect) -> CGPoint { CGPoint(x: r.minX + p.x * r.width, y: r.minY + p.y * r.height) }
/// The fraction of the frame a pane point lands on, as InputOverlayView.normalized does (unclamped).
func fraction(_ q: CGPoint, _ r: CGRect) -> CGPoint { CGPoint(x: (q.x - r.minX) / r.width, y: (q.y - r.minY) / r.height) }

// A phone's picture pane in portrait, a Mac desktop's frame: the frame is wider, so letterboxed top and bottom.
let pane = CGRect(x: 0, y: 0, width: 390, height: 300)
let video = letterbox(pane, CGSize(width: 2940, height: 1912))

// MARK: - Whole by default

do {
    let z = PictureZoom()
    check("whole: scale 1, not zoomed", z.scale == 1 && !z.isZoomed)
    check("whole: the video rect is drawn as it is", z.zoomed(video, in: pane) == video)
    let d = z.drawn(in: pane, video: video)
    check("whole: drawn scale 1, offset zero", d.scale == 1 && d.offset == .zero)
}

// MARK: - A pinch keeps what is under the fingers under them

do {
    let z = PictureZoom()
    let focus = CGPoint(x: 300, y: 120)
    let before = fraction(focus, z.zoomed(video, in: pane))
    z.pinch(by: 2, at: focus, in: pane, video: video)
    let after = fraction(focus, z.zoomed(video, in: pane))
    check("pinch: scale 2", near(z.scale, 2))
    check("pinch: the picture point under the fingers stays under them", near(before, after))
    // A second step about another point, from a magnified, moved picture.
    let focus2 = CGPoint(x: 80, y: 200)
    let before2 = fraction(focus2, z.zoomed(video, in: pane))
    z.pinch(by: 1.5, at: focus2, in: pane, video: video)
    check("pinch: a second step, scale 3", near(z.scale, 3))
    check("pinch: a second step keeps its own point", near(before2, fraction(focus2, z.zoomed(video, in: pane))))
}

do {
    let z = PictureZoom()
    z.pinch(by: 0.5, at: CGPoint(x: 195, y: 150), in: pane, video: video)
    check("pinch in from whole: stays whole", z.scale == 1 && z.offset == .zero)
    z.pinch(by: 100, at: CGPoint(x: 195, y: 150), in: pane, video: video)
    check("pinch: held at maxScale", z.scale == PictureZoom.maxScale)
    z.pinch(by: 0.01, at: CGPoint(x: 10, y: 10), in: pane, video: video)
    check("pinch: held at whole", z.scale == 1)
    check("pinch: whole again is centred", z.drawn(in: pane, video: video).offset == .zero)
}

// MARK: - The hold: the magnified picture covers the pane

do {
    let z = PictureZoom()
    // At the pane's corner: the move a pure focus rule would make uncovers the pane; the hold stops it.
    z.pinch(by: 4, at: CGPoint(x: 0, y: 0), in: pane, video: video)
    let r = z.zoomed(video, in: pane)
    check("hold: covers the pane's left edge", r.minX <= pane.minX + 1e-9)
    check("hold: covers the pane's top edge", r.minY <= pane.minY + 1e-9)
    check("hold: covers the pane's right edge", r.maxX >= pane.maxX - 1e-9)
    check("hold: covers the pane's bottom edge", r.maxY >= pane.maxY - 1e-9)
    check("hold: at the corner, the picture's corner is the pane's", near(r.origin, pane.origin))
}

do {
    let z = PictureZoom()
    // 1.15× of the letterboxed frame (390 × 254): wider than the pane (it was as wide), still shorter (292 of 300).
    z.pinch(by: 1.15, at: CGPoint(x: 390, y: 0), in: pane, video: video)
    let r = z.zoomed(video, in: pane)
    check("hold: shorter than the pane, centred vertically", near(r.midY, pane.midY))
    check("hold: wider than the pane, its right edge reached", near(r.maxX, pane.maxX))
    let d = z.drawn(in: pane, video: video)
    check("hold: vertical offset zero", d.offset.y == 0)
}

// MARK: - The move

do {
    let z = PictureZoom()
    z.pan(by: CGPoint(x: 50, y: 50), in: pane, video: video)
    check("move: nothing while whole", z.offset == .zero && z.zoomed(video, in: pane) == video)
    z.pinch(by: 3, at: CGPoint(x: 195, y: 150), in: pane, video: video)
    let r0 = z.zoomed(video, in: pane)
    z.pan(by: CGPoint(x: -20, y: 10), in: pane, video: video)
    let r1 = z.zoomed(video, in: pane)
    check("move: the picture follows the fingers", near(r1.minX - r0.minX, -20) && near(r1.minY - r0.minY, 10))
    z.pan(by: CGPoint(x: 10_000, y: -10_000), in: pane, video: video)
    let r2 = z.zoomed(video, in: pane)
    check("move: held at the left edge", near(r2.minX, pane.minX))
    check("move: held at the bottom edge", near(r2.maxY, pane.maxY))
}

// MARK: - The spring back, the double tap, the hook

do {
    let z = PictureZoom()
    var calls: [Bool] = []
    z.onChange = { calls.append($0) }
    z.pinch(by: 1.05, at: CGPoint(x: 100, y: 100), in: pane, video: video)
    check("hook: a pinch is not animated", calls == [false])
    z.settle(in: pane, video: video)
    check("settle: below snapScale springs back whole", z.scale == 1 && z.offset == .zero)
    check("hook: the spring back is animated", calls == [false, true])
    z.pinch(by: 2, at: CGPoint(x: 100, y: 100), in: pane, video: video)
    z.settle(in: pane, video: video)
    check("settle: at 2× it stays", near(z.scale, 2))
    z.toggle(at: CGPoint(x: 100, y: 100), in: pane, video: video)
    check("double tap: magnified goes whole", z.scale == 1 && z.offset == .zero)
    check("hook: the double tap is animated", calls.last == true)
    let focus = CGPoint(x: 250, y: 160)
    let before = fraction(focus, z.zoomed(video, in: pane))
    z.toggle(at: focus, in: pane, video: video)
    check("double tap: whole goes to tapScale", z.scale == PictureZoom.tapScale)
    check("double tap: about where it landed", near(before, fraction(focus, z.zoomed(video, in: pane))))
    let count = calls.count
    z.reset(animated: false)
    z.reset(animated: false)
    check("reset: once, then nothing to tell", calls.count == count + 1 && calls.last == false)
}

// MARK: - A pane resized under a magnified picture

do {
    let z = PictureZoom()
    z.pinch(by: 4, at: CGPoint(x: 390, y: 300), in: pane, video: video)
    // The same picture rotated to a wide, short pane: the offset is held again at read time.
    let wide = CGRect(x: 0, y: 0, width: 844, height: 300)
    let v2 = letterbox(wide, CGSize(width: 2940, height: 1912))
    let r = z.zoomed(v2, in: wide)
    check("resize: still covers the new pane", r.minX <= 1e-9 && r.minY <= 1e-9 && r.maxX >= wide.maxX - 1e-9 && r.maxY >= wide.maxY - 1e-9)
    check("resize: the scale is kept", z.scale == 4)
}

// MARK: - One map for the picture and the touch, at random

/// Where HEVCDisplayView.applyZoom draws the letterboxed rect: its video layer fills the pane (bounds at the
/// origin, so the layer's centre is the pane's), is scaled by `s` about that centre and sits at the pane's centre
/// moved by `t`.
func drawnByLayer(_ v: CGRect, pane: CGRect, s: CGFloat, t: CGPoint) -> CGRect {
    let position = CGPoint(x: pane.midX + t.x, y: pane.midY + t.y)
    let layerCentre = CGPoint(x: pane.width / 2, y: pane.height / 2)
    let corner = CGPoint(x: position.x + s * (v.minX - pane.minX - layerCentre.x),
                         y: position.y + s * (v.minY - pane.minY - layerCentre.y))
    return CGRect(x: corner.x, y: corner.y, width: v.width * s, height: v.height * s)
}

var rng = SystemRandomNumberGenerator()
func r(_ a: CGFloat, _ b: CGFloat) -> CGFloat { CGFloat.random(in: a...b, using: &rng) }
var mapOK = true, focusOK = true, coverOK = true, boundsOK = true
for _ in 0..<5_000 {
    let p = CGRect(x: 0, y: 0, width: r(200, 1400), height: r(150, 1000))
    let v = letterbox(p, CGSize(width: r(400, 6000), height: r(300, 4000)))
    let z = PictureZoom()
    for _ in 0..<Int(r(1, 6)) {
        let f = CGPoint(x: r(p.minX, p.maxX), y: r(p.minY, p.maxY))
        let before = fraction(f, z.zoomed(v, in: p))
        let s0 = z.scale
        z.pinch(by: r(0.4, 2.5), at: f, in: p, video: v)
        let rect = z.zoomed(v, in: p)
        // Under the fingers stays under them, unless the hold moved the picture back over an uncovered edge or
        // the scale was held at a limit; then the point is the nearest the hold allows, which the cover check covers.
        if z.scale > 1, z.scale < PictureZoom.maxScale, s0 * 2.5 > z.scale {
            let after = fraction(f, rect)
            let heldX = rect.minX >= p.minX - 1e-6 || rect.maxX <= p.maxX + 1e-6 || rect.width <= p.width + 1e-6
            let heldY = rect.minY >= p.minY - 1e-6 || rect.maxY <= p.maxY + 1e-6 || rect.height <= p.height + 1e-6
            if !heldX && !near(before.x, after.x, 1e-6) { focusOK = false }
            if !heldY && !near(before.y, after.y, 1e-6) { focusOK = false }
        }
        z.pan(by: CGPoint(x: r(-300, 300), y: r(-300, 300)), in: p, video: v)
        let d = z.drawn(in: p, video: v)
        let zr = z.zoomed(v, in: p)
        if !near(zr, drawnByLayer(v, pane: p, s: d.scale, t: d.offset)) { mapOK = false }
        if zr.width >= p.width - 1e-6 { if zr.minX > p.minX + 1e-6 || zr.maxX < p.maxX - 1e-6 { coverOK = false } }
        else if !near(zr.midX, p.midX) { coverOK = false }
        if zr.height >= p.height - 1e-6 { if zr.minY > p.minY + 1e-6 || zr.maxY < p.maxY - 1e-6 { coverOK = false } }
        else if !near(zr.midY, p.midY) { coverOK = false }
        if z.scale < 1 || z.scale > PictureZoom.maxScale { boundsOK = false }
        // A tap's round trip: a picture point shown on the pane maps back to itself.
        let q = CGPoint(x: r(0, 1), y: r(0, 1))
        if !near(fraction(shown(q, zr), zr), q) { mapOK = false }
    }
}
check("random: the display view's layer draws exactly the rect the overlay maps touches through", mapOK)
check("random: a pinch keeps the point under the fingers, wherever the hold lets it", focusOK)
check("random: the magnified picture always covers the pane, or is centred where smaller", coverOK)
check("random: the scale stays between whole and maxScale", boundsOK)

print("\(passes) passed, \(fails) failed")
exit(fails == 0 ? 0 : 1)
