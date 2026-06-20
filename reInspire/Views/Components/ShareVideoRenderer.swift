import UIKit
import AVFoundation
import os.log

private let logger = Logger(subsystem: "com.reinspire", category: "ShareVideoRenderer")

/// Renders a short MP4 of a share card with animated falling confetti, by
/// compositing the (static) base card image and the confetti field per frame.
/// Used so the shared Instagram Story / post actually moves.
enum ShareVideoRenderer {
    /// Returns a temp-file URL to the MP4, or nil on failure. `baseData` is the
    /// PNG of the card without confetti (Data so it crosses actor boundaries).
    static func render(baseData: Data,
                       size: CGSize,
                       duration: Double = 3.0,
                       fps: Int = 30) async -> URL? {
        guard let baseCG = UIImage(data: baseData)?.cgImage else { return nil }
        let specs = ShareConfetti.specs()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("reinspire_share_\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: url)

        let w = Int(size.width), h = Int(size.height)

        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { return nil }
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: w,
            AVVideoHeightKey: h
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = false
        let pbAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: w,
            kCVPixelBufferHeightKey as String: h
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
                                                           sourcePixelBufferAttributes: pbAttrs)
        guard writer.canAdd(input) else { return nil }
        writer.add(input)
        guard writer.startWriting() else {
            logger.error("startWriting failed: \(String(describing: writer.error))")
            return nil
        }
        writer.startSession(atSourceTime: .zero)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue
            | CGBitmapInfo.byteOrder32Little.rawValue
        let frameCount = max(1, Int(duration * Double(fps)))

        for frame in 0..<frameCount {
            let t = Double(frame) / Double(fps)

            while !input.isReadyForMoreMediaData {
                try? await Task.sleep(nanoseconds: 5_000_000)
            }
            guard let pool = adaptor.pixelBufferPool else { break }
            var pbOut: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pbOut)
            guard let pb = pbOut else { break }

            CVPixelBufferLockBaseAddress(pb, [])
            if let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb),
                                   width: w, height: h, bitsPerComponent: 8,
                                   bytesPerRow: CVPixelBufferGetBytesPerRow(pb),
                                   space: colorSpace, bitmapInfo: bitmapInfo) {
                // The pixel buffer is bottom-left origin: draw the base upright,
                // and flip each confetti's y (its model uses a top-left origin).
                ctx.draw(baseCG, in: CGRect(x: 0, y: 0, width: w, height: h))
                for s in specs {
                    let f = ShareConfetti.frame(s, t: t, size: size)
                    ctx.saveGState()
                    ctx.translateBy(x: f.pos.x, y: CGFloat(h) - f.pos.y)
                    ctx.rotate(by: f.angle)
                    let rect = CGRect(x: -f.w / 2, y: -f.h / 2, width: f.w, height: f.h)
                    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 4, cornerHeight: 4, transform: nil))
                    ctx.setFillColor(ShareConfetti.uiPalette[s.colorIndex].cgColor)
                    ctx.fillPath()
                    ctx.restoreGState()
                }
            }
            CVPixelBufferUnlockBaseAddress(pb, [])

            let pts = CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps))
            adaptor.append(pb, withPresentationTime: pts)
        }

        input.markAsFinished()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            writer.finishWriting { cont.resume() }
        }

        guard writer.status == .completed else {
            logger.error("video export failed: \(String(describing: writer.error))")
            return nil
        }
        return url
    }
}
