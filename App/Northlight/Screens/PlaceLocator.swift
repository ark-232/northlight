import CoreLocation
import MapKit
import NorthlightKit

/// Finds this Apple TV's place: one location fix, then reverse geocoding for the
/// name, time zone and country.
@MainActor @Observable
final class PlaceLocator: NSObject, CLLocationManagerDelegate {
    enum Status: Equatable {
        case idle
        case locating
        case failed(String)
    }

    private(set) var status = Status.idle
    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var pending: CheckedContinuation<CLLocationCoordinate2D, any Error>?

    override init() {
        super.init()
        manager.delegate = self
    }

    func locate() async -> Place? {
        status = .locating
        do {
            let coordinate = try await fix()
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let item = try await MKReverseGeocodingRequest(location: location)?.mapItems.first
            status = .idle
            // The TV is at this place, so its own zone is right when the geocoder gives none.
            return Place(item, name: "This Apple TV", coordinate: coordinate, zone: item?.timeZone ?? .current)
        } catch {
            status = .failed(error.localizedDescription)
            return nil
        }
    }

    private func fix() async throws -> CLLocationCoordinate2D {
        try await withCheckedThrowingContinuation { continuation in
            pending = continuation
            switch manager.authorizationStatus {
            case .notDetermined: manager.requestWhenInUseAuthorization()
            case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
            default: finish(.failure(LocateError.denied))
            }
        }
    }

    private func finish(_ result: Result<CLLocationCoordinate2D, any Error>) {
        pending?.resume(with: result)
        pending = nil
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            guard self.pending != nil else { return }
            switch status {
            case .notDetermined: break
            case .authorizedWhenInUse, .authorizedAlways: self.manager.requestLocation()
            default: self.finish(.failure(LocateError.denied))
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else { return }
        let (latitude, longitude) = (coordinate.latitude, coordinate.longitude)
        Task { @MainActor in
            self.finish(.success(CLLocationCoordinate2D(latitude: latitude, longitude: longitude)))
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        let message = error.localizedDescription
        Task { @MainActor in self.finish(.failure(LocateError.failed(message))) }
    }

    enum LocateError: LocalizedError {
        case denied
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .denied: "Location access is off for Northlight."
            case .failed(let message): message
            }
        }
    }
}

extension Place {
    /// The place a geocoded map item names: its city, else its own name, else `name`.
    init(_ item: MKMapItem?, name: String, coordinate: CLLocationCoordinate2D, zone: TimeZone) {
        self.init(name: item?.addressRepresentations?.cityName ?? item?.name ?? name,
                  latitude: coordinate.latitude, longitude: coordinate.longitude,
                  timeZoneIdentifier: zone.identifier, countryCode: item?.addressRepresentations?.region?.identifier)
    }
}
