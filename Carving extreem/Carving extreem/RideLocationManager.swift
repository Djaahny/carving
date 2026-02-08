import Combine
import CoreLocation
import Foundation

@MainActor
final class RideLocationManager: NSObject, ObservableObject {
    @Published private(set) var speedMetersPerSecond: Double = 0
    @Published private(set) var status: String = ""
    @Published private(set) var latestLocation: CLLocation?

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .fitness
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
    }

    func startUpdates() {
        switch manager.authorizationStatus {
        case .notDetermined:
            status = "Requesting location access…"
            manager.requestAlwaysAuthorization()
        case .restricted, .denied:
            status = "Location access denied"
        case .authorizedAlways, .authorizedWhenInUse:
            status = "GPS active"
            manager.startUpdatingLocation()
        @unknown default:
            status = "Location status unknown"
        }
    }

    func stopUpdates() {
        manager.stopUpdatingLocation()
        status = ""
    }
}

extension RideLocationManager: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        startUpdates()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        speedMetersPerSecond = location.speed
        latestLocation = location
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        status = "GPS error: \(error.localizedDescription)"
    }
}
