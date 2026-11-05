import ImageIO
import SwiftUI
import UIKit

/// Képgyorsítótár a beszélgetéshez.
///
/// A csatolt kép eddig minden újrarajzoláskor újra dekódolódott a fő szálon — folyó válasz
/// közben ez másodpercenként több tucatszor. Itt egyszer dekódolunk, a megjelenítési méretre
/// kicsinyítünk (downsample), és a memóriában tartjuk. A kicsinyítés a lényeg: egy 12 megapixeles
/// fotó teljes felbontásban ~48 MB lenne, 520 px-en ~1 MB.
enum ImageCache {
    /// Az NSCache szálbiztos, de nem `Sendable` — ezért egy `@unchecked Sendable` tokba kerül,
    /// hogy a háttérszálas dekódolás és a fő szál is ugyanazt a tárat lássa (Swift 6 alatt).
    private final class Memory: @unchecked Sendable {
        static let shared = Memory()
        let cache: NSCache<NSString, UIImage> = {
            let cache = NSCache<NSString, UIImage>()
            cache.countLimit = 96
            cache.totalCostLimit = 48 * 1024 * 1024
            return cache
        }()
    }

    private static var memory: NSCache<NSString, UIImage> { Memory.shared.cache }

    /// A már kiszámolt kép, ha van. Ez fut a fő szálon, ezért csak szótárazás.
    static func cached(_ key: String) -> UIImage? {
        memory.object(forKey: key as NSString)
    }

    /// base64 → megjelenítési méretű kép. Ismételt hívásnál a gyorsítótárból jön.
    static func thumbnail(base64: String, key: String, maxPixel: CGFloat) -> UIImage? {
        if let hit = cached(key) { return hit }
        guard let data = Data(base64Encoded: base64),
              let image = downsample(data: data, maxPixel: maxPixel) else { return nil }
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        memory.setObject(image, forKey: key as NSString, cost: cost)
        return image
    }

    /// A kép kicsinyítése dekódolás közben, a teljes kép betöltése nélkül.
    static func downsample(data: Data, maxPixel: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    static func clear() {
        memory.removeAllObjects()
    }
}

/// A csatolt kép nézete: a gyorsítótárból azonnal, ha van; ha nincs, a háttérben készül el,
/// és addig egy halvány helyfoglaló látszik. A `body` sosem dekódol.
struct CachedImage: View {
    let base64: String
    let key: String
    var maxPixel: CGFloat = 520
    var corner: CGFloat = 14

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            }
        }
        .frame(width: 156, height: 156)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            if image == nil {
                ProgressView()
                    .controlSize(.mini)
                    .tint(Theme.textFaint)
                    .padding(6)
            }
        }
        .task(id: key) {
            if let hit = ImageCache.cached(key) {
                image = hit
                return
            }
            let data = base64
            let pixel = maxPixel
            let keyCopy = key
            let made = await Task.detached(priority: .userInitiated) { () -> UIImage? in
                ImageCache.thumbnail(base64: data, key: keyCopy, maxPixel: pixel)
            }.value
            if let made { image = made }
        }
    }
}
