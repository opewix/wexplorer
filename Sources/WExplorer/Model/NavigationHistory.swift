import Foundation

/// История «Назад/Вперёд».
struct NavigationHistory {
    private(set) var backStack: [Location] = []
    private(set) var forwardStack: [Location] = []
    private let limit = 100

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }

    mutating func push(_ current: Location) {
        backStack.append(current)
        if backStack.count > limit { backStack.removeFirst() }
        forwardStack.removeAll()
    }

    mutating func back(from current: Location) -> Location? {
        guard let target = backStack.popLast() else { return nil }
        forwardStack.append(current)
        return target
    }

    mutating func forward(from current: Location) -> Location? {
        guard let target = forwardStack.popLast() else { return nil }
        backStack.append(current)
        return target
    }

    /// Недавние места без повторов, самые свежие первыми.
    func recent(_ count: Int) -> [Location] {
        var result: [Location] = []
        for location in backStack.reversed() where !result.contains(location) {
            result.append(location)
            if result.count == count { break }
        }
        return result
    }
}
