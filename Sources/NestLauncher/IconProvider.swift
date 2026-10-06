import AppKit
import Foundation

@MainActor
final class IconProvider {
    static let shared = IconProvider()

    private let cache = NSCache<NSString, NSImage>()

    private init() { cache.countLimit = 256 }

    func icon(for item: LaunchItem) -> NSImage {
        let key = "\(item.kind.rawValue):\(item.target)" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let expanded = (item.target as NSString).expandingTildeInPath
        let source = NSWorkspace.shared.icon(forFile: expanded)
        let image = source

        cache.setObject(image, forKey: key)
        return image
    }

}
