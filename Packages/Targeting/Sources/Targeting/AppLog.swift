import CoreGraphics
import Foundation
import os

/// Unified logging for all packages. Messages go to the system unified log
/// under the host bundle identifier; filter that subsystem in Console.app.
public enum AppLog {
    public enum Category: String, CaseIterable, Sendable {
        case capability
        case target
        case inject
        case editor
    }

    private static let subsystem = Bundle.main.bundleIdentifier ?? "app.log"

    private static let loggers: [Category: Logger] = {
        Dictionary(uniqueKeysWithValues: Category.allCases.map { category in
            (category, Logger(subsystem: subsystem, category: category.rawValue))
        })
    }()

    public static func log(_ category: Category, _ message: String) {
        loggers[category]?.log("\(message, privacy: .public)")
    }

    public static func formatDelta(from: CGPoint, to: CGPoint) -> String {
        String(format: "(%.1f,%.1f)", to.x - from.x, to.y - from.y)
    }
}
