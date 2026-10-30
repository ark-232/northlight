import Foundation

/// iCloud calendars over CalDAV (RFC 4791): finding an account's event calendars and
/// reading their events. Every answer is a WebDAV multistatus.
public enum CalDAV {
    public static let iCloud = URL(string: "https://caldav.icloud.com/")!

    public struct Calendar: Codable, Hashable, Sendable {
        public let url: URL
        public let name: String
    }

    static let dav = "DAV:", caldav = "urn:ietf:params:xml:ns:caldav"

    static let principalQuery = """
        <?xml version="1.0" encoding="UTF-8"?>
        <d:propfind xmlns:d="DAV:"><d:prop><d:current-user-principal/></d:prop></d:propfind>
        """

    static let homeQuery = """
        <?xml version="1.0" encoding="UTF-8"?>
        <d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav"><d:prop><c:calendar-home-set/></d:prop></d:propfind>
        """

    static let calendarsQuery = """
        <?xml version="1.0" encoding="UTF-8"?>
        <d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav"><d:prop>
        <d:displayname/><d:resourcetype/><c:supported-calendar-component-set/></d:prop></d:propfind>
        """

    /// The events that touch `window`, as calendar data.
    static func eventQuery(over window: DateInterval) -> String {
        let utc = ISO8601DateFormatter()
        utc.formatOptions = [.withYear, .withMonth, .withDay, .withTime, .withTimeZone]
        return """
            <?xml version="1.0" encoding="UTF-8"?>
            <c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav"><d:prop><c:calendar-data/></d:prop>
            <c:filter><c:comp-filter name="VCALENDAR"><c:comp-filter name="VEVENT">
            <c:time-range start="\(utc.string(from: window.start))" end="\(utc.string(from: window.end))"/>
            </c:comp-filter></c:comp-filter></c:filter></c:calendar-query>
            """
    }

    static func principal(from data: Data, at url: URL) throws -> URL {
        try href(in: "current-user-principal", dav, of: data, at: url)
    }

    static func home(from data: Data, at url: URL) throws -> URL {
        try href(in: "calendar-home-set", caldav, of: data, at: url)
    }

    /// The collections that are calendars and hold events. A calendar that names no
    /// component set holds every kind (RFC 4791 §5.2.3).
    static func calendars(from data: Data, at url: URL) throws -> [Calendar] {
        let responses = try tree(data).all("response", dav)
        guard responses.contains(where: { !succeeded($0).isEmpty }) else {
            throw FeedError.decode("CalDAV listed no collection it could read")
        }
        return try responses.compactMap { response in
            let props = succeeded(response)
            func property(_ name: String, _ namespace: String) -> XMLNode? {
                props.lazy.compactMap { $0.first(name, namespace) }.first
            }
            guard let href = response.first("href", dav)?.text.trimmingCharacters(in: .whitespacesAndNewlines),
                  let resolved = URL(string: href, relativeTo: url)?.absoluteURL,
                  property("resourcetype", dav)?.first("calendar", caldav) != nil,
                  property("supported-calendar-component-set", caldav)
                      .map({ $0.all("comp", caldav).contains { $0.attributes["name"] == "VEVENT" } }) ?? true
            else { return nil }
            let found = try onICloud(resolved)
            let name = property("displayname", dav)?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return Calendar(url: found, name: name.isEmpty ? found.lastPathComponent : name)
        }
    }

    /// Every event's calendar data. An answer that is not a success throws, so a failed
    /// read never shows as an empty day.
    static func calendarData(from data: Data) throws -> [String] {
        try tree(data).all("response", dav).flatMap { response in
            let statuses = ([response] + response.all("propstat", dav)).compactMap { $0.first("status", dav)?.text }
            guard statuses.allSatisfy({ $0.contains(" 2") }) else {
                throw FeedError.decode("CalDAV could not read an event: \(statuses.joined(separator: ", "))")
            }
            return response.all("calendar-data", caldav).map(\.text)
        }
    }

    /// The props of a response's successful propstats.
    private static func succeeded(_ response: XMLNode) -> [XMLNode] {
        response.all("propstat", dav)
            .filter { $0.first("status", dav)?.text.contains(" 200") == true }
            .compactMap { $0.first("prop", dav) }
    }

    /// The Apple ID's password goes to iCloud over TLS and nowhere else, whatever an
    /// answer or a stored calendar names.
    static func onICloud(_ url: URL) throws -> URL {
        guard url.scheme == "https", let host = url.host()?.lowercased(), host == "icloud.com" || host.hasSuffix(".icloud.com")
        else { throw FeedError.refused("CalDAV named \(url.host() ?? "an address") outside iCloud.") }
        return url
    }

    private static func href(in property: String, _ namespace: String, of data: Data, at url: URL) throws -> URL {
        guard let text = try tree(data).first(property, namespace)?.first("href", dav)?.text
                  .trimmingCharacters(in: .whitespacesAndNewlines),
              let found = URL(string: text, relativeTo: url)?.absoluteURL
        else { throw FeedError.decode("CalDAV answered without \(property)") }
        return try onICloud(found)
    }

    private static func tree(_ data: Data) throws -> XMLNode {
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        let builder = TreeBuilder()
        parser.delegate = builder
        guard parser.parse(), let root = builder.stack.first?.children.first, root.name == "multistatus", root.namespace == dav
        else { throw FeedError.decode("CalDAV answered without a multistatus") }
        return root
    }
}

/// An iCloud account and the calendars chosen in it, kept together in the TV's keychain.
public struct ICloudAccount: Codable, Hashable, Sendable {
    public var appleID: String
    /// An app-specific password, which iCloud requires of CalDAV clients.
    public var password: String
    public var calendars: [CalDAV.Calendar]

    public init(appleID: String, password: String, calendars: [CalDAV.Calendar]) {
        self.appleID = appleID
        self.password = password
        self.calendars = calendars
    }
}

extension HTTP {
    /// The account's calendars that hold events: its principal, then its calendar home,
    /// then the home's collections.
    public func icloudCalendars(appleID: String, password: String) async throws -> [CalDAV.Calendar] {
        let principal = try CalDAV.principal(
            from: try await dav("PROPFIND", CalDAV.iCloud, depth: 0, CalDAV.principalQuery, appleID, password), at: CalDAV.iCloud)
        let home = try CalDAV.home(
            from: try await dav("PROPFIND", principal, depth: 0, CalDAV.homeQuery, appleID, password), at: principal)
        return try CalDAV.calendars(
            from: try await dav("PROPFIND", home, depth: 1, CalDAV.calendarsQuery, appleID, password), at: home)
    }

    /// The chosen calendars' events over `window`, recurrences expanded.
    public func icloudEvents(_ account: ICloudAccount, window: DateInterval, calendar: Calendar) async throws -> [CalendarEvent] {
        var events: [CalendarEvent] = []
        for chosen in account.calendars {
            let data = try await dav("REPORT", chosen.url, depth: 1, CalDAV.eventQuery(over: window), account.appleID, account.password)
            for text in try CalDAV.calendarData(from: data) {
                events += ICSParser.parse(text, window: window, calendar: calendar)
            }
        }
        return events
    }

    private func dav(_ method: String, _ url: URL, depth: Int, _ body: String, _ user: String, _ password: String) async throws -> Data {
        var request = URLRequest(url: try CalDAV.onICloud(url))
        request.httpMethod = method
        request.setValue("\(depth)", forHTTPHeaderField: "Depth")
        request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("Basic " + Data("\(user):\(password)".utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
        request.httpBody = Data(body.utf8)
        do {
            return try await send(request)
        } catch FeedError.badStatus(401) {
            throw FeedError.refused("iCloud refused the password. Reconnect iCloud in Settings.")
        }
    }
}

/// An XML element read whole: enough of a tree to query a multistatus.
struct XMLNode {
    var name: String
    var namespace: String
    var attributes: [String: String]
    var text = ""
    var children: [XMLNode] = []

    /// The first element below this one with this name, depth first.
    func first(_ name: String, _ namespace: String) -> XMLNode? {
        for child in children {
            if child.name == name, child.namespace == namespace { return child }
            if let found = child.first(name, namespace) { return found }
        }
        return nil
    }

    func all(_ name: String, _ namespace: String) -> [XMLNode] {
        children.flatMap { ($0.name == name && $0.namespace == namespace ? [$0] : []) + $0.all(name, namespace) }
    }
}

private final class TreeBuilder: NSObject, XMLParserDelegate {
    var stack = [XMLNode(name: "", namespace: "", attributes: [:])]

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        stack.append(XMLNode(name: elementName, namespace: namespaceURI ?? "", attributes: attributes))
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        stack[stack.count - 1].text += string
    }

    func parser(_ parser: XMLParser, foundCDATA block: Data) {
        stack[stack.count - 1].text += String(decoding: block, as: UTF8.self)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        let node = stack.removeLast()
        stack[stack.count - 1].children.append(node)
    }
}
