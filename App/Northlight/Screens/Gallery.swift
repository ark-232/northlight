import SwiftUI
import NorthlightKit
import NorthlightUI

/// The widgets that can be added, each drawn from sample readings.
struct Gallery: View {
    /// Adds the pick, or says there is no room for it.
    let add: (WidgetConfig, WidgetSize) -> Bool
    @State private var full = false

    private static let kinds = WidgetConfig.all

    var body: some View {
        let sample = Snapshot.sample()
        ZStack {
            SkyField()
            ScrollView {
                VStack(alignment: .leading, spacing: 40) {
                    Text("Add a widget")
                        .font(Theme.Font.clock)
                        .foregroundStyle(Theme.Palette.bone)
                    if full {
                        Text("Every page is full. Remove a widget to make room.")
                            .font(Theme.Font.body)
                            .foregroundStyle(Theme.Palette.amber)
                    }
                    // A plain grid rather than a lazy one: twelve cards, all of them reachable
                    // by focus before they scroll into view.
                    Grid(horizontalSpacing: 60, verticalSpacing: 60) {
                        ForEach(Array(stride(from: 0, to: Self.kinds.count, by: 3)), id: \.self) { start in
                            GridRow {
                                ForEach(Self.kinds[start..<min(start + 3, Self.kinds.count)], id: \.self) { config in
                                    card(config, sample: sample)
                                }
                            }
                        }
                    }
                }
                .padding(80)
            }
        }
    }

    private func card(_ config: WidgetConfig, sample: Snapshot) -> some View {
        // The smallest size it takes; a hold on the widget resizes it.
        let size = WidgetSize.allCases.first { config.sizes.contains($0) }!
        return Button { full = !add(config, size) } label: {
            VStack(spacing: 16) {
                WidgetCard(placement: Placement(config: config, size: size)!, snapshot: sample)
                    .scaleEffect(0.5)
                    .frame(width: 430, height: 408)
                    .allowsHitTesting(false)
                Text(config.name)
                    .font(Theme.Font.title)
            }
            .frame(width: 500)
        }
        .buttonStyle(.card)
        // Its readings are samples, so VoiceOver reads the name alone.
        .accessibilityLabel(config.name)
        .accessibilityIdentifier("gallery.\(config.name)")
    }
}
