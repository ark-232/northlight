import NorthlightKit
import SwiftUI

// Open the package in Xcode, pick an Apple TV simulator as the run destination,
// and these render in the canvas from the sample readings.

private func page(_ widgets: [(WidgetConfig, WidgetSize)]) -> Page {
    Page(name: "Preview", placements: widgets.map { Placement(config: $0.0, size: $0.1)! })!
}

private struct Canvas: View {
    let page: Page

    var body: some View {
        PageCanvas(page: page, snapshot: .sample()) { $1 }
            .padding(40)
            .background(SkyField())
            .environment(\.timeZone, Samples.place.timeZone)
            .environment(\.calendar, Samples.place.calendar)
    }
}

#Preview("Today", traits: .fixedLayout(width: 1840, height: 896)) {
    Canvas(page: Dashboard.starter.pages[0])
}

#Preview("Nearby", traits: .fixedLayout(width: 1840, height: 896)) {
    Canvas(page: Dashboard.starter.pages[1])
}

#Preview("Large", traits: .fixedLayout(width: 1840, height: 1792)) {
    VStack(spacing: 0) {
        Canvas(page: page([(.weather, .large), (.forecast, .large)]))
        Canvas(page: page([(.agenda, .large), (.seismic(minMagnitude: 2.5), .large)]))
    }
}

#Preview("Work", traits: .fixedLayout(width: 1840, height: 1792)) {
    VStack(spacing: 0) {
        Canvas(page: page([(.github, .large), (.agents, .large)]))
        Canvas(page: page([(.github, .medium), (.agents, .medium), (.aurora, .small), (.daylight, .small)]))
    }
}

#Preview("Medium and small", traits: .fixedLayout(width: 1840, height: 1792)) {
    VStack(spacing: 0) {
        Canvas(page: page([(.flights, .medium), (.aurora, .medium), (.daylight, .medium), (.agenda, .medium)]))
        Canvas(page: page([(.weather, .medium), (.forecast, .medium), (.airSnow, .medium), (.aurora, .small), (.daylight, .small)]))
    }
}

#Preview("Network", traits: .fixedLayout(width: 1840, height: 1936)) {
    let now = Date()
    VStack(spacing: 0) {
        Canvas(page: page([(.network, .medium), (.network, .small), (.network, .small)]))
        NetworkScreen(path: Samples.network, latency: Samples.latency(at: now), tests: Samples.speedTests(at: now),
                      throughput: Samples.throughput, running: false, error: nil,
                      automatic: (2, now.addingTimeInterval(3_000)), now: now) {
            Button("Run speed test") {}
        }
        .frame(width: 1760, height: 960)
        .padding(40)
        .background(SkyField())
    }
}
