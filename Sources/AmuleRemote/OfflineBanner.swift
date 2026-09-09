import SwiftUI

/// Striscia mostrata sopra i contenuti quando l'app è "Offline": i dati in
/// vista sono l'ultimo snapshot salvato; la connessione riparte da sola al
/// primo tocco/clic o al ritorno in primo piano, oppure con "Riconnetti".
struct OfflineBanner: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        if state.offline {
            HStack(spacing: 10) {
                Image(systemName: state.connecting ? "arrow.triangle.2.circlepath" : "wifi.slash")
                    .font(.title3)
                    .foregroundStyle(state.connecting ? .blue : .orange)
                    .symbolEffect(.pulse, isActive: state.connecting)
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.connecting ? "Riconnessione in corso…" : "Offline")
                        .font(.callout.weight(.semibold))
                    if let d = state.offlineSince {
                        Text("Dati aggiornati alle \(d.formatted(date: .omitted, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let e = state.offlineError, !state.connecting {
                        Text(e)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(2)
                    }
                }
                Spacer()
                if state.connecting {
                    ProgressView()
                        #if !os(tvOS)
                        .controlSize(.small)
                        #endif
                } else {
                    Button {
                        Task { await state.resumeFromOffline() }
                    } label: {
                        Label("Riconnetti", systemImage: "arrow.clockwise")
                    }
                    #if !os(tvOS)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    #endif
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.orange.opacity(0.14))
            .overlay(alignment: .bottom) { Divider() }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
