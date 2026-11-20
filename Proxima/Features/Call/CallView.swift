import SwiftUI

/// Écran d'appel en cours — MAQUETTE : aucun audio, aucune crypto.
/// TODO M3-05 (demande/acceptation), M3-07 (audio chiffré).
struct CallView: View {
    let peer: NearbyPeer
    let onHangUp: () -> Void

    @State private var startDate = Date()
    @State private var isMuted = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "person.circle.fill").font(.system(size: 96)).foregroundStyle(.secondary)
            Text(peer.alias).font(.largeTitle.bold())
            TimelineView(.periodic(from: startDate, by: 1)) { context in
                Text(Self.format(context.date.timeIntervalSince(startDate)))
                    .font(.title2.monospacedDigit()).foregroundStyle(.secondary)
            }
            Text("Maquette — pas d'audio").font(.footnote).foregroundStyle(.orange)
            Spacer()
            HStack(spacing: 48) {
                Button { isMuted.toggle() } label: {
                    Image(systemName: isMuted ? "mic.slash.fill" : "mic.fill")
                        .font(.title).frame(width: 72, height: 72)
                        .background(Circle().fill(isMuted ? Color.primary.opacity(0.8) : Color.secondary.opacity(0.2)))
                        .foregroundStyle(isMuted ? Color(.systemBackground) : .primary)
                }
                .accessibilityLabel(isMuted ? "Réactiver le micro" : "Couper le micro")
                Button(action: onHangUp) {
                    Image(systemName: "phone.down.fill")
                        .font(.title).frame(width: 72, height: 72)
                        .background(Circle().fill(.red)).foregroundStyle(.white)
                }
                .accessibilityLabel("Raccrocher")
            }
            .padding(.bottom, 48)
        }
        .frame(maxWidth: .infinity)
    }

    static func format(_ interval: TimeInterval) -> String {
        let s = max(0, Int(interval))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}
