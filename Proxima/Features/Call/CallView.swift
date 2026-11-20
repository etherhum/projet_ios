import SwiftUI

/// Écran d'appel piloté par la session (M3-05) : demande sortante, appel entrant
/// (Accepter / Refuser), poignée de main, code de vérification, résultat. Pas d'audio (M3-07).
struct CallView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "person.circle.fill").font(.system(size: 96)).foregroundStyle(.secondary)
            Text(appState.callPeer?.alias ?? "—").font(.largeTitle.bold())
            content
            Spacer()
            actions.padding(.bottom, 48)
        }
        .padding(.horizontal)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var content: some View {
        switch appState.callPhase {
        case .idle:
            EmptyView()
        case .outgoingRequest:
            ProgressView("Appel en cours…")
        case .incomingRequest:
            Text("Appel entrant").font(.title2).foregroundStyle(.secondary)
            Text("Aucune connexion n'est établie tant que vous n'acceptez pas.")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
        case .handshaking:
            ProgressView("Établissement de la connexion chiffrée…")
        case .verifying(let code):
            codeView(code)
            Text("Comparez ce code avec celui affiché sur l'autre iPhone.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        case .active(let code):
            codeView(code)
            Label("Codes confirmés des deux côtés", systemImage: "checkmark.shield.fill").foregroundStyle(.green)
            Text("Audio à venir (M3-07)").font(.footnote).foregroundStyle(.orange)
        case .failed(let failure):
            Text(Self.message(for: failure)).font(.title3).multilineTextAlignment(.center)
        case .ended(let end):
            Text(Self.message(for: end)).font(.title3).multilineTextAlignment(.center)
        }
    }

    private func codeView(_ code: String) -> some View {
        VStack(spacing: 4) {
            Text("Code de vérification").font(.footnote).foregroundStyle(.secondary)
            Text(code).font(.system(size: 48, weight: .bold, design: .monospaced))
                .accessibilityLabel("Code \(code.map(String.init).joined(separator: " "))")
        }
    }

    @ViewBuilder private var actions: some View {
        switch appState.callPhase {
        case .incomingRequest:
            HStack(spacing: 48) {
                roundButton("phone.down.fill", color: .red, label: "Refuser") { appState.declineIncomingCall() }
                roundButton("phone.fill", color: .green, label: "Accepter") {
                    Task { await appState.acceptIncomingCall() }
                }
            }
        case .verifying:
            VStack(spacing: 12) {
                Button { appState.confirmCode() } label: {
                    Text("Les codes correspondent").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                Button(role: .destructive) { appState.rejectCode() } label: {
                    Text("Ne correspondent pas").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).controlSize(.large)
            }
        case .outgoingRequest, .handshaking, .active:
            roundButton("phone.down.fill", color: .red, label: "Raccrocher") { appState.hangUp() }
        case .failed, .ended, .idle:
            Button("Fermer") { appState.dismissCall() }
                .buttonStyle(.borderedProminent).controlSize(.large)
        }
    }

    private func roundButton(_ symbol: String, color: Color, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title).frame(width: 72, height: 72)
                .background(Circle().fill(color)).foregroundStyle(.white)
        }
        .accessibilityLabel(label)
    }

    static func message(for failure: CallFailure) -> String {
        switch failure {
        case .declinedOrNoAnswer: return "Appel refusé ou sans réponse"
        case .timeout: return "Délai dépassé"
        case .protocolError: return "Connexion sécurisée impossible. Appel fermé."
        case .codeMismatch: return "Codes différents : appel fermé"
        case .disconnected: return "Connexion perdue"
        }
    }

    static func message(for end: CallEnd) -> String {
        switch end {
        case .localHangUp: return "Appel terminé"
        case .remoteHangUp: return "Votre correspondant a raccroché"
        case .declined: return "Appel refusé"
        }
    }

    static func format(_ interval: TimeInterval) -> String {
        let s = max(0, Int(interval))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}
