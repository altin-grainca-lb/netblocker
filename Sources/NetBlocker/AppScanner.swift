import Foundation

/// Scans an app bundle's executables (and Electron .asar archives) for the
/// URLs embedded in them, and returns the domains the app is likely to
/// contact, ranked by how often they appear.
enum AppScanner {

    /// Domains that show up in almost every binary (docs, standards bodies,
    /// package metadata) and are never what the user wants to block.
    private static let noiseSuffixes: [String] = [
        "w3.org", "json-schema.org", "ietf.org", "mozilla.org", "developer.mozilla.org",
        "reactjs.org", "apache.org", "nodejs.org", "nodejs.dev", "stackoverflow.com",
        "example.com", "example.org", "localhost", "apple.com", "adobe.com",
        "schemas.microsoft.com", "schemas.openxmlformats.org", "whatwg.org", "tc39.es",
        "electronjs.org", "semver.org", "iana.org", "openjsf.org", "typescriptlang.org",
        "safaribooksonline.com", "caniuse.com", "web.dev", "aka.ms", "lodash.com",
        "feross.org", "sindresorhus.com", "mathiasbynens.be", "izs.me", "code.google.com",
        "googlesource.com", "chromium.org", "swift.org", "wikipedia.org", "unicode.org",
        "openssl.org", "curl.se", "zlib.net", "sqlite.org", "gnu.org", "webkit.org",
        "khronos.org", "opengl.org", "crashlytics.com.invalid",
    ]

    static func scan(bundleURL: URL) -> [DomainHit] {
        var counts: [String: Int] = [:]
        for file in scanTargets(in: bundleURL) {
            extractDomains(from: file, into: &counts)
        }

        return counts
            .filter { !isNoise($0.key) }
            .map { domain, count in
                // New apps start with every domain selected; the user toggles
                // off any they want to leave reachable.
                DomainHit(domain: domain, count: count, selected: true)
            }
            .sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                return $0.domain < $1.domain
            }
    }

    // MARK: - File discovery

    private static func scanTargets(in bundleURL: URL) -> [URL] {
        var targets: [URL] = []
        let fm = FileManager.default

        // Main executables
        let macOSDir = bundleURL.appendingPathComponent("Contents/MacOS")
        if let files = try? fm.contentsOfDirectory(at: macOSDir, includingPropertiesForKeys: nil) {
            targets += files
        }

        // Electron app code + helper executables anywhere in the bundle
        if let walker = fm.enumerator(at: bundleURL, includingPropertiesForKeys: [.fileSizeKey],
                                      options: [.skipsHiddenFiles]) {
            for case let url as URL in walker {
                if url.pathExtension == "asar" { targets.append(url) }
                if url.deletingLastPathComponent().lastPathComponent == "MacOS",
                   !targets.contains(url) { targets.append(url) }
            }
        }
        return targets
    }

    // MARK: - String extraction

    /// Streams the file in chunks and collects `http(s)://<host>` matches.
    private static func extractDomains(from file: URL, into counts: inout [String: Int]) {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return }
        defer { try? handle.close() }

        let chunkSize = 4 * 1024 * 1024
        let overlap = 512
        var carry = Data()

        let regex = try! NSRegularExpression(
            pattern: #"https?://([a-z0-9](?:[a-z0-9.-]{2,251})[a-z0-9])"#,
            options: [.caseInsensitive])

        while let chunk = try? handle.read(upToCount: chunkSize), !chunk.isEmpty {
            let data = carry + chunk
            let text = String(decoding: data, as: UTF8.self)
            let range = NSRange(text.startIndex..., in: text)
            regex.enumerateMatches(in: text, range: range) { match, _, _ in
                guard let match, let r = Range(match.range(at: 1), in: text) else { return }
                let host = text[r].lowercased()
                guard isPlausibleDomain(host) else { return }
                counts[host, default: 0] += 1
            }
            carry = data.suffix(overlap)
        }
    }

    private static func isPlausibleDomain(_ host: String) -> Bool {
        guard host.contains("."), host.count <= 253 else { return false }
        // Skip bare IPs
        if host.allSatisfy({ $0.isNumber || $0 == "." }) { return false }
        let labels = host.split(separator: ".")
        guard labels.count >= 2, let tld = labels.last else { return false }
        // TLD must be alphabetic and at least 2 chars
        return tld.count >= 2 && tld.allSatisfy(\.isLetter)
    }

    private static func isNoise(_ domain: String) -> Bool {
        noiseSuffixes.contains { domain == $0 || domain.hasSuffix("." + $0) }
    }
}
