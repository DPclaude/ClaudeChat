import UIKit
import UniformTypeIdentifiers

enum AttachmentFactory {
    /// 压缩到最长边 1568 像素的 JPEG（超过这个尺寸模型也会缩小，只会多花流量）。
    static func image(from data: Data, name: String = "图片.jpg") -> Attachment? {
        guard let image = UIImage(data: data) else { return nil }
        let maxSide: CGFloat = 1568
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: floor(image.size.width * scale), height: floor(image.size.height * scale))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let jpeg = resized.jpegData(compressionQuality: 0.8) else { return nil }
        return Attachment(kind: .image, name: name, mediaType: "image/jpeg", data: jpeg)
    }

    /// 支持图片、PDF 和 UTF-8 文本文件，其他格式返回 nil。
    static func file(at url: URL) -> Attachment? {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return nil }

        let name = url.lastPathComponent
        let type = UTType(filenameExtension: url.pathExtension)
        if let type, type.conforms(to: .image) {
            return image(from: data, name: name)
        }
        if let type, type.conforms(to: .pdf) {
            guard data.count < 30_000_000 else { return nil }
            return Attachment(kind: .pdf, name: name, mediaType: "application/pdf", data: data)
        }
        guard data.count < 2_000_000, String(data: data, encoding: .utf8) != nil else { return nil }
        return Attachment(kind: .text, name: name, mediaType: "text/plain", data: data)
    }
}
