import Foundation

/// A layout being edited on the TV: a working copy of its pages, and the widget being
/// carried to a new place, if any.
public struct Editing: Equatable, Sendable {
    public private(set) var pages: [Page]
    public private(set) var carried: Carried?

    public struct Carried: Equatable, Sendable {
        public let id: UUID
        public let page: Int
        /// Its place in the page's order when picked up, where Back puts it.
        public let from: Int
    }

    public init(_ dashboard: Dashboard) {
        pages = dashboard.pages
    }

    /// The layout as edited, without the pages left empty.
    public var dashboard: Dashboard {
        Dashboard(pages: pages.filter { !$0.placements.isEmpty })!
    }

    /// The last widget stays: its menu is the way back into editing.
    public var canRemove: Bool {
        pages.reduce(0) { $0 + $1.placements.count } > 1
    }

    /// Nil, and nothing changes, for a widget on no page; the same goes for each edit
    /// below, since a Mac can take a widget away while the TV still shows it.
    @discardableResult
    public mutating func pickUp(_ id: UUID) -> Carried? {
        guard let (page, index) = position(of: id) else { return nil }
        carried = Carried(id: id, page: page, from: index)
        return carried
    }

    /// Where the carried widget can go on its page, each place once.
    public var slots: [Slot] {
        guard let carried, let index = position(of: carried.id)?.index else { return [] }
        var others = pages[carried.page].placements
        let widget = others.remove(at: index)
        return PageGrid.slots(for: widget.size, among: others.map(\.size), near: carried.from)
    }

    public mutating func move(to index: Int) {
        guard let carried, let from = position(of: carried.id)?.index else { return }
        var placements = pages[carried.page].placements
        let widget = placements.remove(at: from)
        placements.insert(widget, at: index)
        pages[carried.page] = pages[carried.page].with(placements)!
    }

    public mutating func drop() {
        carried = nil
    }

    public mutating func putBack() {
        guard let carried else { return }
        move(to: carried.from)
        self.carried = nil
    }

    /// The sizes a widget takes that fit on its page, smallest first.
    public func sizes(for id: UUID) -> [WidgetSize]? {
        guard let (page, index) = position(of: id) else { return nil }
        let placements = pages[page].placements
        return WidgetSize.allCases.filter { size in
            var sizes = placements.map(\.size)
            sizes[index] = size
            return placements[index].config.sizes.contains(size) && PageGrid.fits(sizes)
        }
    }

    /// Nil also when the size no longer fits, which a size offered before a Mac's
    /// change can do.
    @discardableResult
    public mutating func resize(_ id: UUID, to size: WidgetSize) -> Placement? {
        guard let (page, index) = position(of: id) else { return nil }
        var placements = pages[page].placements
        guard let resized = Placement(id: id, config: placements[index].config, size: size) else { return nil }
        placements[index] = resized
        guard let fitted = pages[page].with(placements) else { return nil }
        pages[page] = fitted
        return resized
    }

    @discardableResult
    public mutating func remove(_ id: UUID) -> Placement? {
        guard let (page, index) = position(of: id) else { return nil }
        var placements = pages[page].placements
        let removed = placements.remove(at: index)
        pages[page] = pages[page].with(placements)!
        return removed
    }

    /// Adds a widget to `page`, else to the first page with room, else to a new last
    /// page. Returns the page it went to, or nil when no page has room and there can
    /// be no more pages.
    @discardableResult
    public mutating func add(_ config: WidgetConfig, size: WidgetSize, preferring page: Int) -> Int? {
        let widget = Placement(config: config, size: size)!
        for index in [page] + pages.indices {
            if let fitted = pages[index].with(pages[index].placements + [widget]) {
                pages[index] = fitted
                return index
            }
        }
        guard pages.count < Dashboard.maxPages else { return nil }
        let names = Set(pages.map(\.name))
        let name = ((pages.count + 1)...).lazy.map { "Page \($0)" }.first { !names.contains($0) }!
        pages.append(Page(name: name, placements: [widget])!)
        return pages.count - 1
    }

    private func position(of id: UUID) -> (page: Int, index: Int)? {
        for (page, contents) in pages.enumerated() {
            if let index = contents.placements.firstIndex(where: { $0.id == id }) { return (page, index) }
        }
        return nil
    }
}
