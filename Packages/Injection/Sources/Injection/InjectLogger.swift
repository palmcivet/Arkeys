import Foundation
import os

public enum InjectLogger {
    public enum Category: String, Sendable {
        case capability
        case target
        case inject
    }

    private static let subsystem = "palmcivet.arkeys"

    private static let loggers: [Category: Logger] = {
        var map = [Category: Logger]()
        for cat in [Category.capability, .target, .inject] {
            map[cat] = Logger(subsystem: subsystem, category: cat.rawValue)
        }
        return map
    }()

    public static func log(_ category: Category, _ message: String) {
        loggers[category]?.log("\(message, privacy: .public)")
    }

    public static func formatDelta(from: CGPoint, to: CGPoint) -> String {
        String(format: "(%.1f,%.1f)", to.x - from.x, to.y - from.y)
    }
}
