import SwiftUI

/// Collegamenti pubblici del progetto (repository, wiki, segnalazioni, privacy).
enum AppLinks {
    static let repository = URL(string: "https://github.com/sidimam/AmuleRemote")!
    static let wiki = URL(string: "https://github.com/sidimam/AmuleRemote/wiki")!
    static let issues = URL(string: "https://github.com/sidimam/AmuleRemote/issues")!
    static let privacy = URL(string: "https://sidimam.github.io/AmuleRemote/")!
    static let license = URL(string: "https://github.com/sidimam/AmuleRemote/blob/main/LICENSE")!
    static let amuleProject = URL(string: "https://amule-org.github.io")!

    static let author = "Simone Di Mambro"
    static let copyright = "© 2026 Simone Di Mambro"

    /// Nome della piattaforma per il testo delle segnalazioni.
    static var platformName: String {
        #if os(macOS)
        return "macOS"
        #elseif os(tvOS)
        return "tvOS"
        #elseif os(visionOS)
        return "visionOS"
        #elseif os(watchOS)
        return "watchOS"
        #else
        return UIDevice.current.userInterfaceIdiom == .pad ? "iPadOS" : "iOS"
        #endif
    }

    /// Nuova issue su GitHub con titolo e corpo precompilati (versione, build,
    /// piattaforma e versione del sistema), così la segnalazione è già completa.
    static var bugReport: URL {
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let body = """
        **Describe the problem**


        **Steps to reproduce**
        1.
        2.

        **Environment**
        - aMule Remote: \(appVersionString())
        - Platform: \(platformName) — \(os)
        - amuled version:
        """
        var comps = URLComponents(url: issues.appendingPathComponent("new"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "title", value: "[\(platformName)] "),
            URLQueryItem(name: "labels", value: "bug"),
            URLQueryItem(name: "body", value: body),
        ]
        return comps.url ?? issues
    }

    /// Testo integrale della licenza MIT del progetto (uguale al file LICENSE).
    static let mitLicense = """
    MIT License

    Copyright (c) 2026 Simone Di Mambro

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.
    """
}

/// Sezione "Informazioni app" comune a iOS/iPadOS, visionOS, Mac (Impostazioni)
/// e Apple TV: versione, autore, licenza, guida, segnalazione problemi, privacy.
struct AppInfoSection: View {
    @State private var showLicense = false
    #if os(tvOS)
    // tvOS: le righe sono focalizzabili (per scorrere col telecomando) e il
    // testo diventa nero sulla riga evidenziata (platter bianco).
    @FocusState private var focus: String?
    private func ink(_ key: String) -> Color { focus == key ? .black : .primary }
    private func ink2(_ key: String) -> Color { focus == key ? Color.black.opacity(0.62) : Color.secondary }
    #endif

    var body: some View {
        Section {
            infoRow("version", "aMule Remote", "app.badge", appVersionString())
            infoRow("author", "Autore", "person", AppLinks.author)
            #if os(macOS)
            Button {
                showLicense = true
            } label: {
                LabeledContent {
                    HStack(spacing: 6) {
                        Text("MIT")
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }
                } label: {
                    Label("Licenza", systemImage: "doc.text")
                }
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showLicense) {
                VStack(spacing: 0) {
                    LicenseView()
                    Divider()
                    HStack {
                        Spacer()
                        Button("Chiudi") { showLicense = false }
                            .keyboardShortcut(.cancelAction)
                    }
                    .padding(12)
                }
                .frame(width: 560, height: 520)
            }
            #elseif os(tvOS)
            NavigationLink {
                LicenseView()
            } label: {
                LabeledContent {
                    Text("MIT").foregroundStyle(ink2("license"))
                } label: {
                    Label("Licenza", systemImage: "doc.text").foregroundStyle(ink("license"))
                }
            }
            .focused($focus, equals: "license")
            #else
            NavigationLink {
                LicenseView()
            } label: {
                LabeledContent {
                    Text("MIT")
                } label: {
                    Label("Licenza", systemImage: "doc.text")
                }
            }
            #endif
            linkRow("Guida (wiki)", "book", AppLinks.wiki)
            linkRow("Segnala un problema", "ladybug", AppLinks.bugReport, shown: AppLinks.issues)
            linkRow("Codice sorgente", "chevron.left.forwardslash.chevron.right", AppLinks.repository)
            linkRow("Informativa sulla privacy", "hand.raised", AppLinks.privacy)
        } header: {
            Text("Informazioni app")
        } footer: {
            Text("\(AppLinks.copyright). Software libero con licenza MIT. Il protocollo EC (External Connections) appartiene al progetto aMule.")
        }
    }

    /// Riga informativa (versione, autore).
    @ViewBuilder
    private func infoRow(_ key: String, _ title: LocalizedStringKey, _ icon: String, _ value: String) -> some View {
        #if os(tvOS)
        LabeledContent {
            Text(value).foregroundStyle(ink2(key))
        } label: {
            Label(title, systemImage: icon).foregroundStyle(ink(key))
        }
        .focusable()
        .focused($focus, equals: key)
        #else
        LabeledContent {
            Text(value)
        } label: {
            Label(title, systemImage: icon)
        }
        #endif
    }

    /// Su Apple TV non esiste un browser: il link viene mostrato come testo.
    @ViewBuilder
    private func linkRow(_ title: LocalizedStringKey, _ icon: String, _ url: URL, shown: URL? = nil) -> some View {
        #if os(tvOS)
        let key = url.absoluteString
        LabeledContent {
            Text((shown ?? url).absoluteString)
                .font(.caption)
                .foregroundStyle(ink2(key))
        } label: {
            Label(title, systemImage: icon)
                .foregroundStyle(ink(key))
        }
        .focusable()
        .focused($focus, equals: key)
        #else
        Link(destination: url) {
            HStack {
                Label(title, systemImage: icon)
                Spacer()
                Image(systemName: "arrow.up.right.square")
                    .foregroundStyle(.secondary)
            }
        }
        #if os(macOS)
        .buttonStyle(.plain)
        #endif
        #endif
    }
}

/// Testo della licenza MIT.
struct LicenseView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("aMule Remote è software libero distribuito con licenza MIT: puoi usarlo, copiarlo, modificarlo e ridistribuirlo liberamente, conservando la nota di copyright.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(AppLinks.mitLicense)
                    .font(.footnote.monospaced())
                    #if !os(tvOS)
                    .textSelection(.enabled)
                    #endif
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .navigationTitle("Licenza")
        #if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
