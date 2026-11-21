import MapKit
import SwiftUI

/// Compact, Apple Wallet–style location preview shown ONLY inside Transaction Detail Sheet.
struct TransactionLocationCard: View {
    @Environment(\.openURL) private var openURL

    let locationName: String?
    let latitude: Double?
    let longitude: Double?

    private var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private var displayTitle: String {
        if let locationName, !locationName.isEmpty {
            return locationName
        }
        if let latitude, let longitude {
            return String(format: "%.4f, %.4f", latitude, longitude)
        }
        return "Vị trí giao dịch"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let coordinate {
                let region = MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.0045, longitudeDelta: 0.0045)
                )

                Map(initialPosition: .region(region), interactionModes: []) {
                    Marker(displayTitle, coordinate: coordinate)
                        .tint(OutcomeTheme.Colors.accent)
                }
                .frame(height: 116)
                .clipShape(.rect(cornerRadius: 16))
                .accessibilityLabel("Bản đồ vị trí \(displayTitle)")
            }

            HStack(spacing: 8) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.footnote.bold())
                    .foregroundStyle(OutcomeTheme.Colors.accent)
                    .accessibilityHidden(true)

                Text(displayTitle)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Spacer(minLength: 6)

                if let coordinate {
                    Button {
                        let encodedName = displayTitle.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Giao+dich"
                        if let url = URL(string: "https://maps.apple.com/?ll=\(coordinate.latitude),\(coordinate.longitude)&q=\(encodedName)") {
                            openURL(url)
                        }
                    } label: {
                        Text("Bản đồ")
                            .font(.footnote.bold())
                            .foregroundStyle(OutcomeTheme.Colors.accent)
                            .padding(.horizontal, 10)
                            .frame(minHeight: OutcomeTheme.Layout.minTouchTarget)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(OutcomeTheme.Colors.card, in: .rect(cornerRadius: OutcomeTheme.Layout.tileRadius))
    }
}
