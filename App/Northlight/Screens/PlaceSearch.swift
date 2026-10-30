import MapKit
import NorthlightKit

/// Looks places up by name as they are typed, for a TV whose own location is off or
/// wrong, or a dashboard about somewhere else.
@MainActor @Observable
final class PlaceSearch: NSObject, MKLocalSearchCompleterDelegate {
    private(set) var results: [MKLocalSearchCompletion] = []
    /// Why the last pick gave no place.
    private(set) var failure: String?
    @ObservationIgnored private let completer = MKLocalSearchCompleter()

    var query = "" {
        didSet {
            completer.queryFragment = query
            failure = nil
            if query.isEmpty { results = [] }
        }
    }

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
    }

    /// The place a result names, with its time zone and country.
    func place(for result: MKLocalSearchCompletion) async -> Place? {
        failure = nil
        do {
            guard let item = try await MKLocalSearch(request: MKLocalSearch.Request(completion: result)).start().mapItems.first
            else {
                failure = "Maps found no place named \(result.title)."
                return nil
            }
            var zone = item.timeZone
            if zone == nil {
                // A search result can come without a zone; the geocoder supplies one.
                zone = try await MKReverseGeocodingRequest(location: item.location)?.mapItems.first?.timeZone
            }
            guard let zone else {
                failure = "Maps gave no time zone for \(result.title)."
                return nil
            }
            return Place(item, name: result.title, coordinate: item.location.coordinate, zone: zone)
        } catch {
            failure = error.localizedDescription
            return nil
        }
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        Task { @MainActor in results = Array(self.completer.results.prefix(5)) }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: any Error) {
        Task { @MainActor in results = [] }
    }
}
