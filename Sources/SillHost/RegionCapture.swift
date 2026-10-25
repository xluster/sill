import AppKit
import CoreImage
import StreamProtocol

/// Kind 34 (CaptureRegion.swift): the part of the picture a device framed, cut from the frame the
/// encoder last took (exactly what the device sees, so no permission beyond the capture's) and
/// made a PNG for the Mac's clipboard (Alexis, 2026-10-25).
enum RegionCapture {
    private static let context = CIContext(options: [.cacheIntermediates: false])
    private static let queue = DispatchQueue(label: "sill.regioncapture", qos: .userInitiated)

    /// Cuts `region` out of `frame` off the main actor and hands the PNG, or nil, back on it.
    static func png(of frame: CVPixelBuffer, region: CaptureRegion,
                    done: @escaping @MainActor (Data?, CGSize) -> Void) {
        nonisolated(unsafe) let frame = frame   // read only, on one queue
        queue.async {
            let image = CIImage(cvPixelBuffer: frame)
            let w = image.extent.width, h = image.extent.height
            // The region is measured from the top left; Core Image's origin is the bottom left.
            let rect = CGRect(x: region.x * w, y: (1 - region.y - region.height) * h,
                              width: region.width * w, height: region.height * h)
                .integral.intersection(image.extent)
            var png: Data?
            if !rect.isEmpty, let cg = context.createCGImage(image, from: rect) {
                png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
            }
            let size = rect.size
            Task { @MainActor in done(png, size) }
        }
    }
}
