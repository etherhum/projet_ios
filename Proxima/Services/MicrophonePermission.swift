import AVFoundation

enum MicrophoneAuthorization: Equatable {
    case undetermined, granted, denied
}

/// Accès au micro, abstrait pour tester AppState sans popup système.
@MainActor
protocol MicrophonePermission: AnyObject {
    var status: MicrophoneAuthorization { get }
    /// Affiche la popup iOS (uniquement si le statut est `.undetermined`).
    func request() async -> Bool
}

/// Implémentation iOS 17 (`AVAudioApplication`). Aucune demande n'est faite à l'init.
@MainActor
final class SystemMicrophonePermission: MicrophonePermission {
    var status: MicrophoneAuthorization {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return .granted
        case .denied: return .denied
        default: return .undetermined
        }
    }

    func request() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }
}
