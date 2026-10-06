import Foundation

struct CategoryIndex {
    let byID: [UUID: Category]
    let roots: [Category]
    let children: [UUID: [Category]]
    let depths: [UUID: Int]
    let displayOrder: [Category]

    init(_ categories: [Category]) {
        byID = Dictionary(categories.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let sorted = categories.sorted { $0.sortIndex < $1.sortIndex }
        roots = sorted.filter { $0.parentID == nil }
        children = Dictionary(grouping: sorted.filter { $0.parentID != nil }, by: { $0.parentID! })
        var computed: [UUID: Int] = [:]
        // Iterative memoization avoids recursion and repeated ancestor searches.
        for category in sorted where computed[category.id] == nil {
            var trail: [UUID] = []
            var visited = Set<UUID>()
            var current: UUID? = category.id
            while let id = current, computed[id] == nil, visited.insert(id).inserted,
                  let node = byID[id] {
                trail.append(id)
                current = node.parentID
            }
            var depth = current.flatMap { computed[$0] }.map { $0 + 1 } ?? 0
            for id in trail.reversed() { computed[id] = depth; depth += 1 }
        }
        depths = computed
        var ordered: [Category] = []
        var stack = Array(roots.reversed())
        var visited = Set<UUID>()
        while let category = stack.popLast() {
            guard visited.insert(category.id).inserted else { continue }
            ordered.append(category)
            stack.append(contentsOf: (children[category.id] ?? []).reversed())
        }
        // Keep malformed/orphan nodes discoverable until the load repair runs.
        ordered.append(contentsOf: sorted.filter { !visited.contains($0.id) })
        displayOrder = ordered
    }
}
