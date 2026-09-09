import Foundation

extension CGRect {
    func nearlyEqual(_ other: CGRect) -> Bool {
        abs(origin.x - other.origin.x) < 0.5
            && abs(origin.y - other.origin.y) < 0.5
            && abs(width - other.width) < 0.5
            && abs(height - other.height) < 0.5
    }
}
