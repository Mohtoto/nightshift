import CoreLocation
import MapKit
import Observation

@MainActor
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    private(set) var authorization: CLAuthorizationStatus
    private(set) var location: CLLocation?
    private(set) var lastError: String?

    @ObservationIgnored private let manager = CLLocationManager()

    override init() {
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var isAuthorized: Bool {
        authorization == .authorizedAlways || authorization == .authorizedWhenInUse
    }

    func requestAccess() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        default:
            break
        }
    }

    func refresh() {
        guard isAuthorized else { return }
        manager.requestLocation()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            if status == .authorizedAlways || status == .authorizedWhenInUse {
                self.manager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let latest = locations.last
        Task { @MainActor in
            self.location = latest
            self.lastError = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in
            self.lastError = message
        }
    }
}

@MainActor
enum PlaceSearch {
    static func coordinate(for completion: MKLocalSearchCompletion) async throws -> (address: String, coordinate: CLLocationCoordinate2D) {
        let response = try await MKLocalSearch(request: MKLocalSearch.Request(completion: completion)).start()
        guard let item = response.mapItems.first else { throw NightshiftError.notFound }
        let coordinate = item.nightshiftCoordinate
        let address = item.nightshiftAddress
        guard address.count >= 3 else { throw NightshiftError.message("That place doesn't have a street address.") }
        return (address, coordinate)
    }

    static func address(at coordinate: CLLocationCoordinate2D) async throws -> String {
        let marks = try await CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
        guard let address = marks.first?.nightshiftAddress, address.count >= 3 else {
            throw NightshiftError.message("No street address was found there.")
        }
        return address
    }

    static func search(query: String) async throws -> (address: String, coordinate: CLLocationCoordinate2D) {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        let response = try await MKLocalSearch(request: request).start()
        guard let item = response.mapItems.first else { throw NightshiftError.notFound }
        let address = item.nightshiftAddress
        guard address.count >= 3 else { throw NightshiftError.message("Try a more specific address.") }
        return (address, item.nightshiftCoordinate)
    }
}

private extension MKMapItem {
    var nightshiftCoordinate: CLLocationCoordinate2D {
        if #available(iOS 26.0, *) {
            return location.coordinate
        }
        return placemark.coordinate
    }

    var nightshiftAddress: String {
        if #available(iOS 26.0, *) {
            if let full = address?.fullAddress, full.count >= 3 { return full }
            if let title = addressRepresentations?.fullAddress(includingRegion: true, singleLine: true), title.count >= 3 {
                return title
            }
            return name ?? ""
        }
        let street = [placemark.subThoroughfare, placemark.thoroughfare].compactMap { $0 }.joined(separator: " ")
        let city = [placemark.locality, placemark.administrativeArea].compactMap { $0 }.joined(separator: ", ")
        let combined = [street, city].filter { !$0.isEmpty }.joined(separator: ", ")
        if combined.count >= 3 { return combined }
        return placemark.name ?? name ?? ""
    }
}

private extension CLPlacemark {
    var nightshiftAddress: String {
        let street = [subThoroughfare, thoroughfare].compactMap { $0 }.joined(separator: " ")
        let city = [locality, administrativeArea].compactMap { $0 }.joined(separator: ", ")
        return [street, city].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}
