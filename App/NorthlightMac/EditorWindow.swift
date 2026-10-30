import AppKit
import NorthlightKit
import NorthlightUI
import SwiftUI

/// What a drag carries: a widget on the TV, a kind from the gallery, or a page tab.
private enum DragItem {
    case tile(UUID)
    case kind(WidgetConfig)
    case page(UUID)

    init?(_ text: String) {
        let (tag, body) = (text.prefix { $0 != ":" }, text.drop { $0 != ":" }.dropFirst())
        switch tag {
        case "tile": guard let id = UUID(uuidString: String(body)) else { return nil }; self = .tile(id)
        case "page": guard let id = UUID(uuidString: String(body)) else { return nil }; self = .page(id)
        case "kind":
            guard let config = try? JSONDecoder().decode(WidgetConfig.self, from: Data(body.utf8)) else { return nil }
            self = .kind(config)
        default: return nil
        }
    }

    var text: String {
        switch self {
        case .tile(let id): "tile:\(id.uuidString)"
        case .page(let id): "page:\(id.uuidString)"
        case .kind(let config): "kind:" + String(decoding: (try? JSONEncoder().encode(config)) ?? Data(), as: UTF8.self)
        }
    }
}

/// The editor: the TV's screen as it is now, edited in place.
struct EditorView: View {
    let link: TVLink
    let feed: AgentFeed
    let calendar: CalendarConnector
    let github: GitHubConnector
    @Environment(\.openWindow) private var openConnectors
    @Environment(\.undoManager) private var undo
    @State private var selection: UUID?
    @State private var renaming: UUID?
    @State private var name = ""

    private var dashboard: Dashboard? { link.dashboard }

    /// The TV's page, or the first while it has not said.
    private var pageIndex: Int {
        guard let dashboard else { return 0 }
        return dashboard.pages.firstIndex { $0.id == link.status?.page } ?? 0
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            VStack(spacing: 0) {
                if let notice { banner(notice) }
                if let dashboard {
                    tabs(dashboard)
                    mirror(dashboard)
                        .padding(20)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView("No layout yet", systemImage: "tv",
                                           description: Text("The Apple TV's screen shows here once it answers."))
                }
            }
            .inspector(isPresented: .constant(true)) {
                inspector
                    .inspectorColumnWidth(min: 260, ideal: 300)
            }
        }
        .focusable()
        .focusEffectDisabled()
        .onDeleteCommand { remove() }
        .onChange(of: link.foreignChanges) { undo?.removeAllActions() }
        .onChange(of: dashboard) {
            if let selection, dashboard?.pages.contains(where: { $0.placements.contains { $0.id == selection } }) != true {
                self.selection = nil
            }
        }
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
            link.start()
        }
        .onDisappear {
            link.stop()
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private var notice: String? {
        switch link.state {
        case .looking: "Looking for an Apple TV running Northlight"
        case .connecting(let name): "Connecting to \(name)"
        case .connected: link.status?.editing == true ? "Editing on the Apple TV. Finish there to edit here." : nil
        case .unreachable: "Apple TV not reachable"
        case .outdated(let message): message
        case .unpaired: "This build has no pairing key yet"
        }
    }

    private func banner(_ text: String) -> some View {
        Label(text, systemImage: "lock")
            .font(.callout)
            .frame(maxWidth: .infinity)
            .padding(8)
            .background(.yellow.opacity(0.2))
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List {
            Section("Apple TV") {
                HStack {
                    Circle()
                        .fill(link.canEdit ? .green : .secondary)
                        .frame(width: 8, height: 8)
                    Text(tvName)
                    Spacer()
                    if case .connected = link.state, let trip = link.roundTrip {
                        Text("\(Int(trip / .milliseconds(1))) ms")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section("Place") {
                LabeledContent("Place", value: link.status?.place?.name ?? "Unknown")
                LabeledContent("Units", value: link.status?.units?.rawValue.capitalized ?? "From the TV's region")
            }
            Section("Connectors") {
                LabeledContent("Calendars", value: !calendar.hasAccess ? "Not set up"
                               : calendar.chosen.isEmpty ? "None chosen" : "\(calendar.chosen.count) shown")
                LabeledContent("GitHub", value: github.step == .signedIn ? "Signed in" : "Not set up")
                LabeledContent("Claude Code", value: feed.folder == nil ? "Not set up" : "Reading sessions")
                Button("Calendars and GitHub…") { openConnectors(id: "connectors") }
            }
        }
    }

    private var tvName: String {
        switch link.state {
        case .connected(let name), .connecting(let name), .unreachable(let name): name
        case .looking, .outdated, .unpaired: "Apple TV"
        }
    }

    // MARK: Page tabs

    private func tabs(_ dashboard: Dashboard) -> some View {
        HStack(spacing: 8) {
            ForEach(Array(dashboard.pages.enumerated()), id: \.element.id) { index, page in
                if renaming == page.id {
                    TextField("Page name", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                        .onSubmit {
                            renaming = nil
                            change(dashboard.renaming(page: page.id, to: name))
                        }
                        .onExitCommand { renaming = nil }
                } else {
                    Text(page.name)
                        .fontWeight(index == pageIndex ? .bold : .regular)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(index == pageIndex ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.12),
                                    in: .capsule)
                        .contentShape(.capsule)
                        .onTapGesture(count: 2) {
                            guard link.canEdit else { return }
                            name = page.name
                            renaming = page.id
                        }
                        .onTapGesture { link.show(page: page.id) }
                        .draggable(DragItem.page(page.id).text) { Text(page.name).padding(6) }
                        .dropDestination(for: String.self) { (items: [String], _: CGPoint) in
                            drop(items, onPage: index, at: .max)
                        }
                        .accessibilityAddTraits(index == pageIndex ? [.isButton, .isSelected] : .isButton)
                }
            }
            if dashboard.pages.count < Dashboard.maxPages {
                Image(systemName: "plus")
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Color.secondary.opacity(0.12), in: .capsule)
                    .help("Drop a widget here to start a page")
                    .accessibilityLabel("New page")
                    .dropDestination(for: String.self) { (items: [String], _: CGPoint) in
                        drop(items, onPage: dashboard.pages.count, at: 0)
                    }
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
    }

    // MARK: Mirror

    private func mirror(_ dashboard: Dashboard) -> some View {
        let page = dashboard.pages[min(pageIndex, dashboard.pages.count - 1)]
        let place = link.status?.place ?? Samples.place
        let status = link.status ?? TVStatus(editing: false, page: nil)
        return GeometryReader { geometry in
            let scale = min(geometry.size.width / 1920, geometry.size.height / 1080)
            TVScreen(place: place, mood: { mood(at: $0, place: place) }) { now in
                let snapshot = Snapshot(status: status, place: place, agents: feed.statuses, now: now)
                let elsewhere = snapshot.liveElsewhere(in: dashboard.pages, shown: page)
                let alerts = (status.alerts?.value ?? []).filter { $0.isActive(at: now) }.map(\.event)
                TVHeader(now: now, browsing: false, dayLine: snapshot.dayLine, alert: alerts.first) {
                    PageDots(count: dashboard.pages.count, current: pageIndex)
                } trailing: {
                    TVHeaderStatus(
                        items: HeaderStatus.items(alerts: alerts, liveElsewhere: elsewhere?.kind,
                                                  agentsRunning: feed.statuses.filter { $0.activity != .idle }.count,
                                                  networkFault: status.path.map { $0.link == nil } ?? false, staleAge: nil),
                        elsewhere: elsewhere, pages: dashboard.pages, now: now)
                }
            } canvas: { now in
                canvas(page, pageIndex: pageIndex,
                       snapshot: Snapshot(status: status, place: place, agents: feed.statuses, now: now))
            }
            // The TV's title-safe inset; the sky fills it, the content stays inside it.
            .safeAreaPadding(.horizontal, 80)
            .safeAreaPadding(.vertical, 60)
            .frame(width: 1920, height: 1080)
            .environment(\.timeZone, place.timeZone)
            .environment(\.calendar, place.calendar)
            .environment(\.locale, status.units.map { $0.locale(over: .autoupdatingCurrent) } ?? .autoupdatingCurrent)
            .environment(\.colorScheme, .dark)
            .clipShape(.rect(cornerRadius: 12 / scale))
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: 1920 * scale, height: 1080 * scale, alignment: .topLeading)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .opacity(link.canEdit ? 1 : 0.85)
    }

    private func canvas(_ page: Page, pageIndex: Int, snapshot: Snapshot) -> some View {
        PageCanvas(page: page, snapshot: snapshot) { placement, widget in
            let selected = selection == placement.id
            widget
                .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.corner, style: .continuous))
                .overlay {
                    if selected {
                        RoundedRectangle(cornerRadius: Theme.Metric.corner, style: .continuous)
                            .strokeBorder(Color.accentColor, lineWidth: 8)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: Theme.Metric.corner, style: .continuous))
                .onTapGesture { selection = placement.id }
                .draggable(DragItem.tile(placement.id).text) { dragPreview(placement.config.name) }
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityLabel(placement.config.name)
        }
        .contentShape(.rect)
        .onTapGesture { selection = nil }
        .dropDestination(for: String.self) { items, location in
            drop(items, onPage: pageIndex, near: location)
        }
    }

    private func dragPreview(_ name: String) -> some View {
        Text(name)
            .font(.headline)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(.regularMaterial, in: .capsule)
    }

    private func mood(at date: Date, place: Place) -> SkyMood {
        SkyMood(sunElevation: Solar.elevation(at: date, latitude: place.latitude, longitude: place.longitude),
                cloudCover: link.status?.weather?.value?.cloudCover,
                auroraProbability: link.status?.aurora?.value?.localProbability)
    }

    // MARK: Inspector

    private var inspector: some View {
        let sample = Snapshot.sample()
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let selected {
                    Text(selected.config.name).font(.headline)
                    Picker("Size", selection: Binding(get: { selected.size }, set: { resize(selected.id, to: $0) })) {
                        ForEach(selected.config.sizes.sorted(by: { $0.cells < $1.cells }), id: \.self) { size in
                            Text(size.rawValue.capitalized).tag(size)
                                .selectionDisabled(dashboard?.resizing(selected.id, to: size) == nil)
                        }
                    }
                    .pickerStyle(.segmented)
                    Button("Remove", systemImage: "trash", role: .destructive, action: remove)
                        .disabled(dashboard?.removing(selected.id) == nil)
                    Divider()
                }
                Text("Gallery").font(.headline)
                Text("Drag a widget onto the screen or a page tab.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12)], spacing: 12) {
                    ForEach(WidgetConfig.all, id: \.self) { config in
                        galleryCard(config, sample: sample)
                    }
                }
            }
            .padding(16)
            .disabled(!link.canEdit)
        }
    }

    private func galleryCard(_ config: WidgetConfig, sample: Snapshot) -> some View {
        let placement = Placement(config: config, size: Self.smallest(config))!
        let scale = 0.14
        let card = Lattice.frame(at: GridPoint(col: 0, row: 0), size: placement.size)
        return VStack(spacing: 6) {
            WidgetCard(placement: placement, snapshot: sample)
                .environment(\.colorScheme, .dark)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: card.width * scale, height: card.height * scale, alignment: .topLeading)
                .background(Color(white: 0.08), in: .rect(cornerRadius: 6))
                .clipShape(.rect(cornerRadius: 6))
                .allowsHitTesting(false)
            Text(config.name).font(.caption)
        }
        .frame(maxWidth: .infinity)
        .contentShape(.rect)
        .draggable(DragItem.kind(config).text) { dragPreview(config.name) }
        .accessibilityLabel(config.name)
    }

    private static func smallest(_ config: WidgetConfig) -> WidgetSize {
        WidgetSize.allCases.first { config.sizes.contains($0) }!
    }

    private var selected: Placement? {
        dashboard?.pages.lazy.flatMap(\.placements).first { $0.id == selection }
    }

    // MARK: Edits

    private func change(_ next: Dashboard?) {
        guard let next else {
            NSSound.beep()
            return
        }
        link.edit(next, undo: undo)
    }

    private func remove() {
        guard let selection, link.canEdit, let dashboard else { return }
        change(dashboard.removing(selection))
    }

    private func resize(_ id: UUID, to size: WidgetSize) {
        guard let dashboard else { return }
        change(dashboard.resizing(id, to: size))
    }

    /// A drop on the screen takes the place on the page nearest the pointer.
    private func drop(_ items: [String], onPage page: Int, near location: CGPoint) -> Bool {
        guard let dashboard, let item = items.first.flatMap(DragItem.init) else { return false }
        let placements = dashboard.pages[page].placements
        let size: WidgetSize, others: [Placement]
        switch item {
        case .tile(let id):
            guard let widget = dashboard.pages.lazy.flatMap(\.placements).first(where: { $0.id == id }) else { return false }
            size = widget.size
            others = placements.filter { $0.id != id }
        case .kind(let config):
            size = Self.smallest(config)
            others = placements
        case .page:
            return false
        }
        let nearest = PageGrid.slots(for: size, among: others.map(\.size), near: others.count).min { a, b in
            distance(Lattice.frame(at: a.origin, size: size), location) < distance(Lattice.frame(at: b.origin, size: size), location)
        }
        guard let nearest else {
            NSSound.beep()
            return false
        }
        return drop(items, onPage: page, at: nearest.index)
    }

    private func distance(_ frame: CGRect, _ point: CGPoint) -> CGFloat {
        hypot(frame.midX - point.x, frame.midY - point.y)
    }

    private func drop(_ items: [String], onPage page: Int, at index: Int) -> Bool {
        guard link.canEdit, let dashboard, let item = items.first.flatMap(DragItem.init) else { return false }
        let next: Dashboard?
        switch item {
        case .tile(let id):
            next = dashboard.moving(id, toPage: page, at: index)
        case .kind(let config):
            let widget = Placement(config: config, size: Self.smallest(config))!
            next = dashboard.adding(widget, toPage: page, at: index)
            if next != nil { selection = widget.id }
        case .page(let id):
            guard let from = dashboard.pages.firstIndex(where: { $0.id == id }), page < dashboard.pages.count else { return false }
            next = dashboard.movingPage(from: from, to: page)
        }
        change(next)
        return next != nil
    }
}
