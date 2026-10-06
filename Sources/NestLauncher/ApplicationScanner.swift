import Foundation

struct DiscoveredApplication {
    let name: String
    let path: String
}

enum ApplicationScanner {
    static var defaultDirectories: [URL] {
        [URL(fileURLWithPath: "/Applications"), URL(fileURLWithPath: "/System/Applications")]
            + FileManager.default.urls(for: .applicationDirectory, in: .userDomainMask)
    }

    static func discover(in directories: [URL]) -> [DiscoveredApplication] {
        var seen = Set<String>()
        var result: [DiscoveredApplication] = []
        for directory in directories {
            guard let enumerator = FileManager.default.enumerator(
                at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            for case let url as URL in enumerator {
                if url.pathExtension.lowercased() == "app" {
                    enumerator.skipDescendants()
                    let path = url.standardizedFileURL.resolvingSymlinksInPath().path
                    guard seen.insert(path).inserted else { continue }
                    result.append(DiscoveredApplication(name: url.deletingPathExtension().lastPathComponent, path: path))
                } else if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                    // Never recurse through symlink directories outside the roots.
                    enumerator.skipDescendants()
                }
            }
        }
        return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
