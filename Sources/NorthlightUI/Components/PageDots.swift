import SwiftUI

/// The header's page indicator: the current page a capsule, the others dots. During a
/// ring turn the capsule reaches toward the page it is turning to, then snaps over.
public struct PageDots: View {
    let count: Int
    let current: Int
    /// How far the capsule reaches, from -1 (the previous dot) to 1 (the next).
    let stretch: Double
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var dots

    public init(count: Int, current: Int, stretch: Double = 0) {
        self.count = count
        self.current = current
        self.stretch = stretch
    }

    private var reach: Double {
        guard !reduceMotion else { return 0 }
        if stretch > 0, current < count - 1 { return min(stretch, 1) }
        if stretch < 0, current > 0 { return max(stretch, -1) }
        return 0
    }

    public var body: some View {
        HStack(spacing: 12) {
            ForEach(0..<count, id: \.self) { index in
                if index == current {
                    // The gap and the neighbouring dot: 12 + 10.
                    Capsule()
                        .fill(.white)
                        .frame(width: 28 + 22 * abs(reach), height: 12)
                        .frame(width: 28, alignment: reach < 0 ? .trailing : .leading)
                        .matchedGeometryEffect(id: "current", in: dots)
                } else {
                    Circle()
                        .fill(.white.opacity(contrast == .increased ? 0.6 : 0.35))
                        .frame(width: 10, height: 10)
                }
            }
        }
        .animation(reduceMotion ? nil : Theme.Motion.page, value: current)
        .accessibilityElement()
        .accessibilityLabel("Page \(current + 1) of \(count)")
    }
}
