import Foundation

public enum InjectLogger {
    public enum Category: String, Sendable {
        case capability
        case target
        case inject
    }

    public static func log(_ category: Category, _ message: String) {
        print("[Arkeys][\(category.rawValue)] \(message)")
    }

    public static func formatDelta(from: CGPoint, to: CGPoint) -> String {
        String(format: "(%.1f,%.1f)", to.x - from.x, to.y - from.y)
    }
}
