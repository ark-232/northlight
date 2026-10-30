import SwiftUI
import NorthlightKit
import NorthlightUI

/// The dashboard. At rest one invisible catcher holds focus, so nothing shows focus;
/// the remote turns pages there by ring, swipe or ring click, and the first click,
/// up or down starts browsing,
/// where the tiles, the page chips and Settings take focus and Select opens a widget.
/// Holding Select on a widget offers editing, where Select carries a widget across the
/// page's slots. Back steps out one level at a time, and out of the app at rest.
struct DashboardView: View {
    let store: DashboardStore
    @Binding var dashboard: Dashboard
    @Binding var pageIndex: Int
    @Binding var busy: Bool
    let settingsOpen: Bool
    let onSettings: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var remote = RemoteInput()
    @Namespace private var zoomNS
    @State private var browsing = false
    @State private var lastInput = Date()
    @State private var detail: Placement?
    @State private var forward = true
    /// The layout being edited, which replaces the dashboard's on Done.
    @State private var editing: Editing?
    @State private var adding = false
    @State private var removing: Placement?
    @FocusState private var focus: Focus?

    private enum Focus: Hashable {
        case tile(UUID), slot(Int), chip(Int), settings, add, done, previousPage, nextPage
    }

    private var pages: [Page] { editing?.pages ?? dashboard.pages }
    private var page: Page { pages[min(pageIndex, pages.count - 1)] }
    private var atRest: Bool {
        !browsing && editing == nil && detail == nil && !adding && !settingsOpen && scenePhase == .active
    }

    var body: some View {
        ZStack {
            TVScreen(place: store.config.place, mood: mood(at:)) { now in
                header(now: now)
                    // The whole bar takes focus from any tile below it and lands on the
                    // page on screen, though the chips sit at its far end.
                    .focusSection()
                    .defaultFocus($focus, .chip(pageIndex), priority: .userInitiated)
            } canvas: { now in
                canvas(now: now)
            }

            if !browsing {
                Button { if remote.acceptsSelect() { browse() } } label: { Color.clear }
                    .buttonStyle(InvisibleButtonStyle())
                    .focusEffectDisabled()
                    .onMoveCommand { direction in
                        if let move = Move(direction), remote.acceptsMove() { rest(move) }
                    }
                    .accessibilityLabel("Browse widgets")
                    .accessibilityIdentifier("ambient")
            }
        }
        // Refreshing stays off while editing, where a refresh would only redraw.
        .onPlayPauseCommand(perform: editing == nil ? { store.refreshAll() } : nil)
        .onExitCommand(perform: back)
        .onChange(of: focus) { _, focus in follow(focus) }
        .onChange(of: editing != nil || adding || removing != nil, initial: true) { _, busy in self.busy = busy }
        .onChange(of: dashboard) { _, dashboard in keepFocus(on: dashboard) }
        .task(id: browsing) { await restWhenIdle() }
        .task {
            remote.onMove = { rest($0) }
            remote.start()
        }
        .onChange(of: atRest, initial: true) { _, atRest in remote.atRest = atRest }
        .fullScreenCover(item: $detail) { placement in
            let size = placement.config.sizes.contains(.large) ? WidgetSize.large : .medium
            Group {
                if placement.config == .network {
                    NetworkDetail(store: store)
                } else if placement.config == .github {
                    ZStack {
                        TimelineView(.everyMinute) { context in
                            SkyField(mood: mood(at: context.date))
                        }
                        TimelineView(.everyMinute) { context in
                            GitHubDetail(snapshot: readings(at: context.date))
                        }
                    }
                } else if placement.config == .briefing {
                    BriefingDetail(store: store)
                } else {
                    ZStack {
                        TimelineView(.everyMinute) { context in
                            SkyField(mood: mood(at: context.date))
                        }
                        TimelineView(.everyMinute) { context in
                            WidgetCard(placement: Placement(id: placement.id, config: placement.config, size: size)!,
                                       snapshot: readings(at: context.date))
                        }
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("detail")
            .navigationTransition(.zoom(sourceID: placement.id, in: zoomNS))
        }
        .fullScreenCover(isPresented: $adding) {
            Gallery(add: add)
        }
        .confirmationDialog("Remove \(removing?.config.name ?? "")?", isPresented: Binding(
            get: { removing != nil }, set: { if !$0 { removing = nil } }
        ), titleVisibility: .visible, presenting: removing) { placement in
            Button("Remove", role: .destructive) { change { $0.remove(placement.id) } }
        }
    }

    /// Nil at rest, so Back leaves the app, as tvOS expects at an app's root.
    private var back: (() -> Void)? {
        if let carried = editing?.carried {
            return {
                editing?.putBack()
                focus = .tile(carried.id)
            }
        }
        if editing != nil { return finishEditing }
        if browsing { return { browsing = false } }
        return nil
    }

    private func canvas(now: Date) -> some View {
        HStack(spacing: 30) {
            edge(.previousPage, shown: pageIndex > 0)
            FingerFollow(remote: remote) {
                PageCanvas(page: page, snapshot: readings(at: now)) { placement, widget in
                    if browsing {
                        let carried = editing?.carried?.id == placement.id
                        Button { select(placement) } label: {
                            widget.clipShape(RoundedRectangle(cornerRadius: Theme.Metric.corner, style: .continuous))
                        }
                            .buttonStyle(.card)
                            .contentShape(.hoverEffect, RoundedRectangle(cornerRadius: Theme.Metric.corner, style: .continuous))
                            .disabled(editing?.carried != nil)
                            .focused($focus, equals: .tile(placement.id))
                            // The menu's host and the zoom source both default to a
                            // rectangle, which shows as square corners on a lifted tile.
                            .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: Theme.Metric.corner, style: .continuous))
                            .contextMenu { menu(for: placement) }
                            .overlay {
                                if editing != nil {
                                    RoundedRectangle(cornerRadius: Theme.Metric.corner, style: .continuous)
                                        .strokeBorder(Theme.Palette.muted, style: StrokeStyle(lineWidth: 3, dash: [14, 10]))
                                }
                            }
                            .scaleEffect(carried ? 1.05 : 1)
                            .shadow(color: .black.opacity(carried ? 0.6 : 0), radius: 40, y: 20)
                            .zIndex(carried ? 1 : 0)
                            .animation(Theme.Motion.lift, value: carried)
                            .matchedTransitionSource(id: placement.id, in: zoomNS) {
                                $0.clipShape(RoundedRectangle(cornerRadius: Theme.Metric.corner, style: .continuous))
                            }
                            .accessibilityIdentifier("tile.\(placement.config.name)")
                    } else {
                        widget
                    }
                }
            }
            .overlay(alignment: .topLeading) { slots }
            .animation(Theme.Motion.page, value: page)
            .id(page.id)
            .transition(reduceMotion ? .opacity : .push(from: forward ? .trailing : .leading))
            edge(.nextPage, shown: pageIndex < pages.count - 1)
        }
        // The edges sit just outside the safe area, past the last column.
        .padding(.horizontal, -70)
        .focusSection()
    }

    private func edge(_ which: Focus, shown: Bool) -> some View {
        Color.clear
            .frame(width: 40)
            .frame(maxHeight: .infinity)
            // Not while browsing starts with focus unplaced, where the engine could pick
            // an edge and turn the page.
            .focusable(browsing && shown && editing?.carried == nil && focus != nil)
            .focused($focus, equals: which)
            .accessibilityLabel(which == .nextPage ? "Next page" : "Previous page")
    }

    private func rest(_ move: Move) {
        guard !browsing, editing == nil else { return }
        switch move {
        case .left: turnAtRest(by: -1)
        case .right: turnAtRest(by: 1)
        case .up, .down: browse()
        }
    }

    /// Focus stays hidden, and turns that chain retarget the one running spring.
    private func turnAtRest(by step: Int) {
        let current = min(pageIndex, pages.count - 1)
        let index = min(max(current + step, 0), pages.count - 1)
        guard index != current else { return }
        forward = step > 0
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : Theme.Motion.page) { pageIndex = index }
    }

    private func browse() {
        lastInput = Date()
        browsing = true
        let first = page.placements.first
        Task { focus = first.map { .tile($0.id) } }
    }

    /// While carrying, an invisible button over each place the widget can go; focusing
    /// one moves the widget there, and Select puts it down.
    @ViewBuilder
    private var slots: some View {
        if let editing, let carried = editing.carried,
           let size = editing.pages[carried.page].placements.first(where: { $0.id == carried.id })?.size {
            ForEach(Array(editing.slots.enumerated()), id: \.offset) { index, slot in
                let frame = Lattice.frame(at: slot.origin, size: size)
                Button { drop(carried.id) } label: { Color.clear }
                    .buttonStyle(InvisibleButtonStyle())
                    .focusEffectDisabled()
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
                    .focused($focus, equals: .slot(index))
                    .accessibilityLabel("Place \(index + 1) of \(editing.slots.count)")
            }
        }
    }

    @ViewBuilder
    private func menu(for placement: Placement) -> some View {
        let layout = editing ?? Editing(dashboard)
        if editing == nil {
            Button("Edit Widgets", systemImage: "square.grid.2x2") { editing = layout }
        }
        ForEach((layout.sizes(for: placement.id) ?? []).filter { $0 != placement.size }, id: \.self) { size in
            Button("Make \(size.rawValue.capitalized)") { change { $0.resize(placement.id, to: size) } }
        }
        if layout.canRemove {
            Button("Remove", systemImage: "trash", role: .destructive) { removing = placement }
        }
    }

    private func select(_ placement: Placement) {
        lastInput = Date()
        guard editing != nil else {
            detail = placement
            return
        }
        editing?.pickUp(placement.id)
        let from = editing?.carried?.from
        Task { focus = editing?.slots.firstIndex { $0.index == from }.map { .slot($0) } }
    }

    private func drop(_ id: UUID) {
        editing?.drop()
        focus = .tile(id)
    }

    private func change(_ edit: (inout Editing) -> Void) {
        var changed = editing ?? Editing(dashboard)
        edit(&changed)
        if editing != nil {
            editing = changed
        } else {
            save(changed)
        }
    }

    /// Puts an edited layout on the dashboard. The page on screen stays on screen, or
    /// if it went, the page that took its place shows.
    private func save(_ edited: Editing) {
        let shown = page.id
        dashboard = edited.dashboard
        pageIndex = dashboard.pages.firstIndex { $0.id == shown } ?? min(pageIndex, dashboard.pages.count - 1)
    }

    private func add(_ config: WidgetConfig, size: WidgetSize) -> Bool {
        guard let index = editing!.add(config, size: size, preferring: min(pageIndex, pages.count - 1)) else { return false }
        forward = index > pageIndex
        pageIndex = index
        adding = false
        return true
    }

    private func finishEditing() {
        save(editing!)
        editing = nil
        focus = page.placements.first.map { .tile($0.id) }
    }

    /// A layout from the Mac can take away the widget open or focused: its detail
    /// closes, and focus moves to the first widget on the page shown.
    private func keepFocus(on dashboard: Dashboard) {
        let ids = Set(dashboard.pages.flatMap(\.placements).map(\.id))
        if let detail, !ids.contains(detail.id) { self.detail = nil }
        if case .tile(let id) = focus, !ids.contains(id) {
            focus = page.placements.first.map { .tile($0.id) }
        }
    }

    private func follow(_ focus: Focus?) {
        lastInput = Date()
        switch focus {
        case .nextPage:
            turn(to: pageIndex + 1)
        case .previousPage:
            turn(to: pageIndex - 1)
        case .slot(let index):
            if let slot = editing?.slots[index] { editing?.move(to: slot.index) }
        default:
            break
        }
    }

    /// A chip's page. Chips change the page only when selected, so crossing them on
    /// the way to Settings leaves the page alone.
    private func show(page index: Int) {
        lastInput = Date()
        forward = index > pageIndex
        withAnimation(Theme.Motion.page) { pageIndex = index }
    }

    /// Turns to the live widget's page and focuses it: the button that asked goes away
    /// once that widget is on screen, and focus left to the engine could land on an
    /// edge sentinel, which turns the page again.
    private func show(live elsewhere: LiveElsewhere) {
        show(page: elsewhere.index)
        let target = pages[elsewhere.index].placements.first { $0.config == elsewhere.kind }
        Task { focus = target.map { .tile($0.id) } }
    }

    private func turn(to index: Int) {
        forward = index > pageIndex
        withAnimation(Theme.Motion.page) { pageIndex = index }
        let target = forward ? page.placements.first : page.placements.last
        Task { focus = target.map { .tile($0.id) } }
    }

    private func restWhenIdle() async {
        while browsing, !Task.isCancelled {
            try? await Task.sleep(for: .seconds(5))
            // Time in a widget's detail, in editing or in Settings counts as input.
            if detail != nil || editing != nil || settingsOpen {
                lastInput = Date()
            } else if browsing, Date().timeIntervalSince(lastInput) > 30 {
                browsing = false
            }
        }
    }

    private func header(now: Date) -> some View {
        let alerts = (store.alerts.value ?? []).filter { $0.isActive(at: now) }
        let snapshot = readings(at: now)
        let elsewhere = snapshot.liveElsewhere(in: pages, shown: page)

        return TVHeader(now: now, browsing: browsing,
                        dayLine: snapshot.dayLine,
                        alert: alerts.first?.event) {
            if browsing {
                HStack(spacing: 16) {
                    ForEach(pages.indices, id: \.self) { index in
                        // One style for every chip, so the focused chip keeps its identity
                        // when it becomes the current page.
                        Button(pages[index].name) { show(page: index) }
                            .fontWeight(index == pageIndex ? .bold : .regular)
                            .lineLimit(1)
                            .fixedSize()
                            // A carried widget stays on its page until it is put down.
                            .disabled(editing?.carried != nil)
                            .buttonStyle(.glass)
                            .focused($focus, equals: .chip(index))
                            .accessibilityAddTraits(index == pageIndex ? .isSelected : [])
                    }
                }
            } else {
                RingDots(remote: remote, count: pages.count, current: min(pageIndex, pages.count - 1))
            }
        } trailing: {
            Group {
                if browsing {
                    if let elsewhere {
                        Button { show(live: elsewhere) } label: {
                            LiveElsewhereLabel(elsewhere, page: pages[elsewhere.index].name, now: now)
                        }
                            .buttonStyle(.glass)
                    }
                    if editing != nil {
                        Button("Add Widget", systemImage: "plus") { adding = true }
                            .buttonStyle(.glass)
                            .focused($focus, equals: .add)
                            .accessibilityIdentifier("add")
                        Button("Done", action: finishEditing)
                            .buttonStyle(.glassProminent)
                            .focused($focus, equals: .done)
                            .accessibilityIdentifier("done")
                    } else {
                        Button("Settings", systemImage: "gearshape", action: onSettings)
                            .labelStyle(.iconOnly)
                            .buttonStyle(.glass)
                            .focused($focus, equals: .settings)
                    }
                } else {
                    let items = HeaderStatus.items(
                        alerts: alerts.map(\.event), liveElsewhere: elsewhere?.kind,
                        agentsRunning: (snapshot.agents ?? []).filter { $0.activity != .idle }.count,
                        networkFault: store.running.contains(.network) && store.path?.link == nil,
                        staleAge: staleAge(now: now), usage: store.usage, now: now)
                    TVHeaderStatus(items: items, elsewhere: elsewhere, pages: pages, now: now)
                }
            }
            // A carried widget stays on its page until it is put down.
            .disabled(editing?.carried != nil)
        }
    }

    /// The oldest stale running feed's age, so a single stalled source is visible.
    private func staleAge(now: Date) -> TimeInterval? {
        store.running.subtracting([.bridge, .network]).compactMap { store.staleAge(of: $0, asOf: now) }.max()
    }

    /// What the widgets draw: the store's readings, or in a debug build launched with
    /// `-samples YES` every widget's sample readings, for screenshots.
    private func readings(at now: Date) -> Snapshot {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "samples") { return .sample(at: now) }
        #endif
        return Snapshot(store: store, now: now)
    }

    private func mood(at date: Date) -> SkyMood {
        let place = store.config.place
        return SkyMood(sunElevation: Solar.elevation(at: date, latitude: place.latitude, longitude: place.longitude),
                       cloudCover: store.weather.value?.cloudCover,
                       auroraProbability: store.aurora.value?.localProbability)
    }
}

private extension Move {
    init?(_ direction: MoveCommandDirection) {
        switch direction {
        case .left: self = .left
        case .right: self = .right
        case .up: self = .up
        case .down: self = .down
        @unknown default: return nil
        }
    }
}

/// The page dots, reaching toward the next page as the ring turns. Its own view, so
/// the touch's reports redraw the dots alone.
private struct RingDots: View {
    let remote: RemoteInput
    let count: Int
    let current: Int

    var body: some View {
        var stretch = 0.0
        if case .ring(let since) = remote.phase { stretch = since / 90 }
        return PageDots(count: count, current: current, stretch: stretch)
    }
}

/// The page follows a finger dragging across the pad at rest, at half the finger's
/// 160 pt per pad unit and 160 pt at most, and springs back when it lifts or circles.
/// A turn leaves from where the finger left the page.
private struct FingerFollow<Content: View>: View {
    let remote: RemoteInput
    @ViewBuilder let content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        var offset = 0.0
        if !reduceMotion, case .pan(let dx) = remote.phase { offset = min(max(dx * 80, -160), 160) }
        return content.animation(offset == 0 ? Theme.Motion.lift : .interactiveSpring(duration: 0.15)) {
            $0.offset(x: offset)
        }
    }
}
