import Foundation

enum InjectLogger {
    enum Category: String {
        case capability
        case target
        case inject
    }

    static func log(_ category: Category, _ message: String) {
        print("[Striker][\(category.rawValue)] \(message)")
    }

    static func formatPoint(_ point: CGPoint) -> String {
        String(format: "(%.1f,%.1f)", point.x, point.y)
    }

    static func formatDelta(from: CGPoint, to: CGPoint) -> String {
        String(format: "(%.1f,%.1f)", to.x - from.x, to.y - from.y)
    }
}
