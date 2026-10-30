import Foundation

extension TimeInterval {
    /// "4m" / "2h" / "3d" — short enough to sit in a tile corner.
    public var shortAge: String {
        let seconds = Int(self)
        if seconds < 60 { return "\(max(seconds, 0))s" }
        if seconds < 3_600 { return "\(seconds / 60)m" }
        if seconds < 86_400 { return "\(seconds / 3_600)h" }
        return "\(seconds / 86_400)d"
    }
}
