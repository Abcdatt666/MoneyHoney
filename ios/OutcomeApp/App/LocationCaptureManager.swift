import CoreLocation
import Foundation
import MapKit
import Observation

struct CapturedLocation: Equatable, Sendable {
    let name: String
    let latitude: Double
    let longitude: Double
}

@Observable
@MainActor
final class LocationCaptureManager: NSObject, CLLocationManagerDelegate {
    var isCapturing: Bool = false
    var errorMessage: String?

    private let manager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<(Double, Double)?, Never>?
    private var authContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func captureCurrentLocation() async -> CapturedLocation? {
        guard !isCapturing else { return nil }
        isCapturing = true
        errorMessage = nil
        defer { isCapturing = false }

        var status = manager.authorizationStatus
        if status == .denied || status == .restricted {
            errorMessage = "Hãy bật quyền Vị trí cho Outcome trong Cài đặt iPhone."
            return nil
        }

        if status == .notDetermined {
            status = await withCheckedContinuation { cont in
                self.authContinuation = cont
                self.manager.requestWhenInUseAuthorization()
            }
        }

        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            errorMessage = "Chưa được cấp quyền truy cập vị trí."
            return nil
        }

        let coords: (Double, Double)? = await withCheckedContinuation { cont in
            self.locationContinuation = cont
            self.manager.requestLocation()
        }

        guard let (lat, lon) = coords else {
            errorMessage = "Không thể lấy vị trí lúc này."
            return nil
        }

        let resolvedName = await reverseGeocodeName(latitude: lat, longitude: lon)
        return CapturedLocation(name: resolvedName, latitude: lat, longitude: lon)
    }

    private func reverseGeocodeName(latitude: Double, longitude: Double) async -> String {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        if let request = MKReverseGeocodingRequest(location: location),
           let items = try? await request.mapItems,
           let first = items.first {
            if let short = first.address?.shortAddress, !short.isEmpty {
                return short
            }
            if let name = first.name, !name.isEmpty {
                return name
            }
        }
        return String(format: "%.4f, %.4f", latitude, longitude)
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let newStatus = manager.authorizationStatus
        guard newStatus != .notDetermined else { return }
        Task { @MainActor in
            self.authContinuation?.resume(returning: newStatus)
            self.authContinuation = nil
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        let coords = locations.last.map { ($0.coordinate.latitude, $0.coordinate.longitude) }
        Task { @MainActor in
            self.locationContinuation?.resume(returning: coords)
            self.locationContinuation = nil
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        Task { @MainActor in
            self.locationContinuation?.resume(returning: nil)
            self.locationContinuation = nil
        }
    }
}
