import SwiftUI
#if !os(tvOS)
import LocalAuthentication
#endif

/// Autenticazione locale (Face ID / Touch ID / Optic ID, con fallback al
/// codice del dispositivo). Usata per il blocco opzionale dell'app.
/// Su tvOS LocalAuthentication non esiste: il blocco non è disponibile.
#if os(tvOS)
enum BiometricAuth {
    static var biometryLabel: String { "codice di sblocco" }
    static var biometryIcon: String { "lock.open" }
    static var isAvailable: Bool { false }
    static func authenticate(reason: String) async -> Bool { true }
}
#else
enum BiometricAuth {
    /// Nome della biometria disponibile, per le etichette dell'interfaccia.
    static var biometryLabel: String {
        let ctx = LAContext()
        var err: NSError?
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err)
        switch ctx.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "codice di sblocco"
        }
    }

    static var biometryIcon: String {
        let ctx = LAContext()
        var err: NSError?
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err)
        switch ctx.biometryType {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        case .opticID: return "opticid"
        default: return "lock.open"
        }
    }

    /// true se il dispositivo può autenticare (biometria o codice).
    static var isAvailable: Bool {
        var err: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &err)
    }

    /// Autentica con biometria, con fallback al codice del dispositivo.
    static func authenticate(reason: String) async -> Bool {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { return false }
        return (try? await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
}
#endif

/// Schermata mostrata al posto dell'app quando il blocco biometrico è attivo.
struct LockScreenView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.scenePhase) private var scenePhase
    @State private var failed = false

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.fill")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
            Text("aMule Remote")
                .font(.title2.bold())
            Text("L'app è bloccata. Autenticati con \(BiometricAuth.biometryLabel) per continuare.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Button {
                Task { await attempt() }
            } label: {
                Label("Sblocca", systemImage: BiometricAuth.biometryIcon)
                    .frame(minWidth: 140)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            if failed {
                Text("Autenticazione non riuscita. Riprova.")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Prompt automatico quando la schermata compare con l'app attiva; il
        // bottone resta come ripiego dopo un annullamento o un fallimento.
        .task {
            if scenePhase == .active || isMac { await attempt() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && state.locked && !failed {
                Task { await attempt() }
            }
        }
    }

    private var isMac: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }

    private func attempt() async {
        failed = false
        await state.unlock()
        failed = state.locked
    }
}
