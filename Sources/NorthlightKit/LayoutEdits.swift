import Foundation

extension Page {
    /// The longest name a page takes, so the TV's chips fit beside the clock.
    public static let maxNameLength = 20
}

/// The Mac editor's changes, each a whole new layout. Each is nil when its result
/// could not be one: a page over eight cells, a seventh page, the last widget
/// removed, or an id on no page. A page left empty goes.
extension Dashboard {
    /// `page` one past the last starts a new page; `index` counts the target page's
    /// widgets without the moved one.
    public func moving(_ id: UUID, toPage page: Int, at index: Int) -> Dashboard? {
        edited { drafts in
            guard let (from, at) = position(of: id) else { return nil }
            let widget = drafts[from].placements.remove(at: at)
            return Self.insert(widget, into: &drafts, page: page, at: index)
        }
    }

    public func adding(_ widget: Placement, toPage page: Int, at index: Int) -> Dashboard? {
        edited { Self.insert(widget, into: &$0, page: page, at: index) }
    }

    public func removing(_ id: UUID) -> Dashboard? {
        edited { drafts in
            guard let (page, index) = position(of: id) else { return nil }
            drafts[page].placements.remove(at: index)
            return ()
        }
    }

    public func resizing(_ id: UUID, to size: WidgetSize) -> Dashboard? {
        edited { drafts in
            guard let (page, index) = position(of: id),
                  let resized = Placement(id: id, config: drafts[page].placements[index].config, size: size)
            else { return nil }
            drafts[page].placements[index] = resized
            return ()
        }
    }

    /// Trims the name and cuts it to `Page.maxNameLength`; a blank one is refused.
    public func renaming(page id: UUID, to name: String) -> Dashboard? {
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Page.maxNameLength))
        return edited { drafts in
            guard !trimmed.isEmpty, let page = drafts.firstIndex(where: { $0.id == id }) else { return nil }
            drafts[page].name = trimmed
            return ()
        }
    }

    public func movingPage(from: Int, to: Int) -> Dashboard? {
        edited { drafts in
            guard drafts.indices.contains(from), drafts.indices.contains(to) else { return nil }
            drafts.insert(drafts.remove(at: from), at: to)
            return ()
        }
    }

    private struct Draft {
        let id: UUID
        var name: String
        var placements: [Placement]
    }

    private func edited(_ edit: (inout [Draft]) -> Void?) -> Dashboard? {
        var drafts = pages.map { Draft(id: $0.id, name: $0.name, placements: $0.placements) }
        guard edit(&drafts) != nil else { return nil }
        var built: [Page] = []
        for draft in drafts where !draft.placements.isEmpty {
            guard let page = Page(id: draft.id, name: draft.name, placements: draft.placements) else { return nil }
            built.append(page)
        }
        return Dashboard(pages: built)
    }

    private static func insert(_ widget: Placement, into drafts: inout [Draft], page: Int, at index: Int) -> Void? {
        if page == drafts.count {
            let names = Set(drafts.map(\.name))
            let name = ((drafts.count + 1)...).lazy.map { "Page \($0)" }.first { !names.contains($0) }!
            drafts.append(Draft(id: UUID(), name: name, placements: []))
        }
        guard drafts.indices.contains(page) else { return nil }
        drafts[page].placements.insert(widget, at: min(max(index, 0), drafts[page].placements.count))
        return ()
    }

    private func position(of id: UUID) -> (page: Int, index: Int)? {
        for (page, contents) in pages.enumerated() {
            if let index = contents.placements.firstIndex(where: { $0.id == id }) { return (page, index) }
        }
        return nil
    }
}
