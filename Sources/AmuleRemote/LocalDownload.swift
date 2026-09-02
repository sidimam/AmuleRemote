import Foundation
import SwiftUI

// Download in locale dei file completati. Il protocollo EC controlla amuled ma
// NON trasporta i file: il trasferimento avviene via HTTP(S) da un URL che
// pubblica la cartella Incoming del server (es. un file server sul NAS, anche
// dietro Cloudflare Access: gli header configurati vengono inviati a ogni
// richiesta). URL per profilo; header (segreti) nel Portachiavi.

enum LocalDownloadConfig {
    private static func headersAccount(_ address: String) -> String { "incoming-headers-\(address)" }

    /// Header extra come testo "Nome: Valore", una riga per header.
    static func rawHeaders(for address: String) -> String {
        Keychain.loadPassword(account: headersAccount(address)) ?? ""
    }

    static func saveHeaders(_ raw: String, for address: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            Keychain.deletePassword(account: headersAccount(address))
        } else {
            Keychain.savePassword(trimmed, account: headersAccount(address))
        }
    }

    static func headers(for address: String) -> [(name: String, value: String)] {
        rawHeaders(for: address).split(whereSeparator: \.isNewline).compactMap { line in
            guard let colon = line.firstIndex(of: ":") else { return nil }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? nil : (name, value)
        }
    }

    /// Cartella di destinazione: Documenti dell'app su iOS (visibile in File),
    /// ~/Downloads su macOS.
    static var destinationFolder: URL {
        #if os(macOS)
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        #else
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        #endif
    }

    /// Percorso libero: se il nome esiste già aggiunge " (2)", " (3)", …
    static func uniqueDestination(for name: String) -> URL {
        let folder = destinationFolder
        var candidate = folder.appendingPathComponent(name)
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let alt = ext.isEmpty ? "\(base) (\(n))" : "\(base) (\(n)).\(ext)"
            candidate = folder.appendingPathComponent(alt)
            n += 1
        }
        return candidate
    }

    /// URL completo del file sul server (base + nome percent-encoded).
    static func fileURL(base: String, fileName: String) -> URL? {
        var b = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !b.isEmpty else { return nil }
        if !b.hasSuffix("/") { b += "/" }
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/+&?#%;=")
        guard let enc = fileName.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: b + enc)
    }
}

/// Un download alla volta, con progresso osservabile per la sheet.
final class FileDownloadManager: NSObject, ObservableObject, URLSessionDownloadDelegate {
    @Published var fileName = ""
    @Published var received: Int64 = 0
    @Published var total: Int64 = 0
    @Published var finishedURL: URL?
    @Published var errorMessage: String?
    @Published var running = false

    var progress: Double? {
        total > 0 ? Double(received) / Double(total) : nil
    }

    private var task: URLSessionDownloadTask?
    private var demoTask: Task<Void, Never>?
    private lazy var session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)

    func start(base: String, fileName: String, headers: [(name: String, value: String)]) {
        reset(fileName: fileName)
        guard let url = LocalDownloadConfig.fileURL(base: base, fileName: fileName) else {
            errorMessage = "URL Incoming non configurato per questo profilo. Impostalo nella modifica del profilo (es. https://nas.local/incoming/)."
            return
        }
        var request = URLRequest(url: url)
        for h in headers { request.setValue(h.value, forHTTPHeaderField: h.name) }
        running = true
        let t = session.downloadTask(with: request)
        task = t
        t.resume()
    }

    /// Modalità demo: progresso simulato e piccolo file di esempio.
    func startDemo(fileName: String) {
        reset(fileName: fileName)
        running = true
        total = 100
        demoTask = Task { @MainActor in
            for step in 1...50 {
                try? await Task.sleep(nanoseconds: 60_000_000)
                if Task.isCancelled { return }
                received = Int64(step * 2)
            }
            let dest = LocalDownloadConfig.uniqueDestination(for: fileName)
            try? Data("Contenuto di esempio della modalità demo di aMule Remote.\n".utf8).write(to: dest)
            finishedURL = dest
            running = false
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        demoTask?.cancel()
        demoTask = nil
        running = false
    }

    private func reset(fileName name: String) {
        cancel()
        fileName = name
        received = 0
        total = 0
        finishedURL = nil
        errorMessage = nil
    }

    // MARK: - URLSessionDownloadDelegate (coda di background)

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        DispatchQueue.main.async {
            self.received = totalBytesWritten
            self.total = max(totalBytesExpectedToWrite, 0)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // Il file temporaneo sparisce al ritorno: va spostato SUBITO, qui.
        if let http = downloadTask.response as? HTTPURLResponse, http.statusCode >= 400 {
            DispatchQueue.main.async {
                self.errorMessage = "Il server ha risposto HTTP \(http.statusCode). Controlla l'URL Incoming e gli header del profilo."
                self.running = false
            }
            return
        }
        let name = fileName.isEmpty ? (downloadTask.originalRequest?.url?.lastPathComponent ?? "download") : fileName
        let dest = LocalDownloadConfig.uniqueDestination(for: name)
        do {
            try FileManager.default.moveItem(at: location, to: dest)
            DispatchQueue.main.async {
                self.finishedURL = dest
                self.running = false
            }
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = "File scaricato ma non salvabile: \(error.localizedDescription)"
                self.running = false
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, (error as NSError).code != NSURLErrorCancelled else { return }
        DispatchQueue.main.async {
            self.errorMessage = error.localizedDescription
            self.running = false
        }
    }
}

/// Sheet di avanzamento del download locale, condivisa iOS/macOS.
struct LocalDownloadSheet: View {
    @ObservedObject var manager: FileDownloadManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: manager.finishedURL != nil ? "checkmark.circle.fill"
                  : (manager.errorMessage != nil ? "exclamationmark.triangle.fill" : "arrow.down.circle"))
                .font(.system(size: 36))
                .foregroundStyle(manager.finishedURL != nil ? .green
                                 : (manager.errorMessage != nil ? .orange : .blue))
            Text(manager.fileName)
                .font(.callout.weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(.center)

            if let err = manager.errorMessage {
                Text(err)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else if let dest = manager.finishedURL {
                Text(destinationDescription(dest))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                #if os(macOS)
                Button("Mostra nel Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([dest])
                }
                #endif
            } else {
                if let p = manager.progress {
                    ProgressView(value: p)
                    Text("\(formatBytes(UInt64(max(manager.received, 0)))) di \(formatBytes(UInt64(max(manager.total, 0)))) (\(Int(p * 100))%)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                    Text(formatBytes(UInt64(max(manager.received, 0))))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                if manager.running {
                    Button("Annulla", role: .cancel) {
                        manager.cancel()
                        dismiss()
                    }
                } else {
                    Button("Chiudi") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(minWidth: 320, maxWidth: 420)
        .interactiveDismissDisabled(manager.running)
    }

    private func destinationDescription(_ url: URL) -> String {
        #if os(macOS)
        return "Salvato in \(url.deletingLastPathComponent().path)"
        #else
        return "Salvato nei Documenti dell'app: lo trovi nell'app File → Sul mio iPhone → aMule Remote."
        #endif
    }
}
