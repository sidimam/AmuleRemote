import Foundation

/// Riconoscimento dei link ed2k:// nel testo, condiviso con la Share Extension.
enum Ed2kLink {
    /// Tutti i link ed2k://|file|… presenti nel testo (senza doppioni, con la / finale).
    static func extract(_ text: String) -> [String] {
        let pattern = #"ed2k://\|file\|[^\s|]+\|\d+\|[0-9A-Fa-f]{32}\|(?:[^\s]*?\|)?/?"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let ns = text as NSString
        var seen = Set<String>(), out: [String] = []
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            var link = ns.substring(with: m.range)
            if !link.hasSuffix("/") { link += "/" }
            if seen.insert(link.lowercased()).inserted { out.append(link) }
        }
        return out
    }

    /// Nome del file dentro un link ed2k (campo dopo «file»).
    static func name(_ link: String) -> String {
        let parts = link.split(separator: "|")
        return parts.count > 2 ? String(parts[2]).removingPercentEncoding ?? String(parts[2]) : link
    }
}
