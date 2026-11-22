import AppKit

enum ImageTools {
    /// Downscales so the longest side is at most `maxDimension` pixels and encodes as JPEG.
    /// Snap & Cook sends the model a 1024px copy; saved recipe photos keep 1600px.
    static func jpegData(_ image: NSImage, maxDimension: CGFloat, quality: Double) -> Data? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let scale = min(1, maxDimension / max(w, h))
        let tw = Int((w * scale).rounded()), th = Int((h * scale).rounded())
        guard let ctx = CGContext(data: nil, width: tw, height: th, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: tw, height: th))   // flatten transparency onto white
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: tw, height: th))
        guard let scaled = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: scaled).representation(using: .jpeg, properties: [.compressionFactor: quality])
    }

    static func fromPasteboard() -> NSImage? {
        let pb = NSPasteboard.general
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingContentsConformToTypes: ["public.image"]]) as? [URL],
           let url = urls.first, let img = NSImage(contentsOf: url) { return img }
        return pb.readObjects(forClasses: [NSImage.self])?.first as? NSImage
    }
}
