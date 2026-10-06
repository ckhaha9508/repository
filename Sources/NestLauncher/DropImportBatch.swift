import Foundation

/// Collect one drag's asynchronous results and import only once, in drag order.
@MainActor
final class DropImportBatch {
    private var results: [URL?]
    private var received: Set<Int> = []
    private var completion: (([URL]) -> Void)?

    init(count: Int, completion: @escaping ([URL]) -> Void) {
        results = Array(repeating: nil, count: count)
        self.completion = completion
        if count == 0 { self.completion = nil; completion([]) }
    }

    func accept(_ url: URL?, at index: Int) {
        guard results.indices.contains(index), received.insert(index).inserted else { return }
        results[index] = url
        guard received.count == results.count else { return }
        let callback = completion
        completion = nil
        callback?(results.compactMap { $0 })
    }
}
