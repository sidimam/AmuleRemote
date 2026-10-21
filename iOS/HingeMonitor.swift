import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Posizione della cerniera dell'iPhone Duo (e di ogni futuro pieghevole).
/// `unknown` = dispositivo senza cerniera o stato non ancora ricevuto.
enum HingeStatus: String {
    case unknown, closed, partiallyOpen, fullyOpen
}

/// Stato della cerniera osservabile da SwiftUI. Lo alimenta `HingeObserverView`
/// (UIHingeInteraction, iOS 27.1+) oppure l'argomento di lancio
/// `-hinge closed|partial|open` per collaudo e screenshot sui simulatori che
/// non permettono di cambiare postura da riga di comando.
@MainActor
final class HingeMonitor: ObservableObject {
    static let shared = HingeMonitor()

    @Published private(set) var status: HingeStatus = .unknown
    /// Angolo in radianti (0 = chiuso, π = aperto del tutto); nil se ignoto.
    @Published private(set) var angle: Double?

    /// Vero quando la postura è forzata da `-hinge` (collaudo).
    let forced: Bool

    private init() {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-hinge"), i + 1 < args.count {
            forced = true
            switch args[i + 1] {
            case "closed": status = .closed; angle = 0
            case "partial", "half": status = .partiallyOpen; angle = .pi / 2
            case "open": status = .fullyOpen; angle = .pi
            default: status = .unknown
            }
        } else {
            forced = false
        }
    }

    func update(status: HingeStatus, angle: Double?) {
        guard !forced else { return }
        if self.status != status { self.status = status }
        self.angle = angle
    }

    /// Postura «mini computer»: telefono aperto a metà e appoggiato, con la
    /// piega che divide lo schermo interno in una metà alta e una bassa.
    var isLaptopPosture: Bool { status == .partiallyOpen }
}

/// Vista invisibile che aggancia `UIHingeInteraction` alla gerarchia e riversa
/// gli aggiornamenti in `HingeMonitor`. Sui sistemi senza l'API (o senza
/// cerniera) non fa nulla.
struct HingeObserverView: UIViewRepresentable {
    @ObservedObject var monitor: HingeMonitor = .shared

    func makeUIView(context: Context) -> UIView {
        let v = UIView(frame: .zero)
        v.isUserInteractionEnabled = false
        v.isHidden = true
        #if os(iOS)
        if #available(iOS 27.1, *) {
            let interaction = UIHingeInteraction { _, update in
                let monitor = HingeMonitor.shared
                guard let hinge = update.hinge else {
                    Task { @MainActor in monitor.update(status: .unknown, angle: nil) }
                    return
                }
                let status: HingeStatus
                switch hinge.status {
                case .closed: status = .closed
                case .partiallyOpen: status = .partiallyOpen
                case .fullyOpen: status = .fullyOpen
                default: status = .unknown
                }
                let angle = Double(hinge.angle)
                Task { @MainActor in monitor.update(status: status, angle: angle) }
            }
            v.addInteraction(interaction)
        }
        #endif
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
