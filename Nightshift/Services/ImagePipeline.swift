import SwiftUI
import UIKit

@MainActor
enum ImageEncoder {
    static func jpeg(_ data: Data, maxDimension: CGFloat, quality: CGFloat) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let longest = max(image.size.width, image.size.height)
        guard longest > 0 else { return nil }
        let scale = longest > maxDimension ? maxDimension / longest : 1
        let target = CGSize(width: max(image.size.width * scale, 1), height: max(image.size.height * scale, 1))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            UIColor.black.setFill()
            UIRectFill(CGRect(origin: .zero, size: target))
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return rendered.jpegData(compressionQuality: quality)
    }
}

enum TestImages {
    @MainActor
    static func jpeg(seed: UInt32) -> Data {
        let size = CGSize(width: 1200, height: 800)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor(hex: 0x08090F).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor(hex: seed % 2 == 0 ? 0xA020F0 : 0x00E5FF).setFill()
            context.fill(CGRect(x: 70, y: 470, width: 1060, height: 180))
            UIColor(hex: 0x121420).setFill()
            context.fill(CGRect(x: 160, y: 390, width: 280, height: 90))
            context.fill(CGRect(x: 760, y: 390, width: 280, height: 90))
            UIColor(hex: 0xFF2D92).setFill()
            context.fill(CGRect(x: 140, y: 620, width: 70, height: 36))
            context.fill(CGRect(x: 980, y: 620, width: 70, height: 36))
        }
        return image.jpegData(compressionQuality: 0.9) ?? Data()
    }
}

@MainActor
@Observable
final class ImagePipeline {
    private let repository: any NightshiftRepository
    private let cache = NSCache<NSString, UIImage>()

    init(repository: any NightshiftRepository) {
        self.repository = repository
        cache.countLimit = 150
    }

    func load(path: String?, thumbnail: Bool) async -> UIImage? {
        guard let path else { return nil }
        let key = (thumbnail ? "t:" : "f:") + path as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let data = try? await repository.imageData(storagePath: path, thumbnail: thumbnail),
              let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    func invalidate() {
        cache.removeAllObjects()
    }
}

struct MediaImage: View {
    let path: String?
    var thumbnail = true
    var systemFallback = "car.fill"

    @Environment(ImagePipeline.self) private var pipeline
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            NightshiftColor.elevated
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: systemFallback)
                    .font(.title2)
                    .foregroundStyle(NightshiftColor.secondaryText)
            }
        }
        .clipped()
        .task(id: path) {
            image = await pipeline.load(path: path, thumbnail: thumbnail)
        }
        .accessibilityHidden(image == nil)
    }
}
