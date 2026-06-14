import UIKit

extension UIImage {
    /// Downscales so the longest side is at most `maxDimension`, preserving
    /// aspect ratio and orientation. Returns self when already small enough.
    /// Photos straight from the camera are 4-12 MP; verification only needs
    /// ~1280px, which cuts upload, storage-fetch, and Claude vision latency.
    func downscaled(maxDimension: CGFloat = 1280) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return self }

        let scale = maxDimension / longest
        let newSize = CGSize(width: (size.width * scale).rounded(),
                             height: (size.height * scale).rounded())

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1               // newSize is already in pixels
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    /// Convenience: downscale then JPEG-encode for upload.
    func compressedForUpload(maxDimension: CGFloat = 1280, quality: CGFloat = 0.7) -> Data? {
        downscaled(maxDimension: maxDimension).jpegData(compressionQuality: quality)
    }
}
