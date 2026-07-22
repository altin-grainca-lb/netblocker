import Foundation

enum HostsError: LocalizedError {
    case cancelled
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .cancelled: return "Authorization was cancelled."
        case .failed(let message): return message
        }
    }
}

/// Reads and rewrites /etc/hosts. Each managed app gets its own
/// marker-delimited section so blocks can be added/removed independently
/// and survive manual edits elsewhere in the file.
enum HostsManager {
    static let hostsPath = "/etc/hosts"

    private static func beginMarker(_ appID: String) -> String { "# >>> NetBlocker[\(appID)] >>>" }
    private static func endMarker(_ appID: String) -> String { "# <<< NetBlocker[\(appID)] <<<" }

    static func currentContent() -> String {
        (try? String(contentsOfFile: hostsPath, encoding: .utf8)) ?? ""
    }

    static func isBlocked(appID: String, in content: String) -> Bool {
        content.contains(beginMarker(appID))
    }

    static func contentApplying(block: Bool, appID: String, domains: [String], to content: String) -> String {
        var result = removingSection(appID: appID, from: content)
        if block {
            if !result.hasSuffix("\n") { result += "\n" }
            result += beginMarker(appID) + "\n"
            for domain in domains {
                result += "0.0.0.0 \(domain)\n"
                result += ":: \(domain)\n"
            }
            result += endMarker(appID) + "\n"
        }
        return result
    }

    private static func removingSection(appID: String, from content: String) -> String {
        let lines = content.components(separatedBy: "\n")
        var kept: [String] = []
        var inSection = false
        for line in lines {
            if line == beginMarker(appID) { inSection = true; continue }
            if line == endMarker(appID) { inSection = false; continue }
            if !inSection { kept.append(line) }
        }
        return kept.joined(separator: "\n")
    }

    /// Writes the new content to a temp file, then copies it over /etc/hosts
    /// and flushes the DNS cache — as root, via the standard macOS
    /// administrator-password dialog (no daemons, no special entitlements).
    static func apply(newContent: String) throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("netblocker-hosts-\(UUID().uuidString.prefix(8))")
        try newContent.write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        // chown/chmod: a hosts file that isn't root:wheel 644 is unreadable to
        // mDNSResponder, which then silently ignores every entry system-wide.
        // killall (not -HUP, which only dumps state): mDNSResponder re-reads
        // /etc/hosts on restart; launchd respawns it immediately.
        let shell = "/bin/cp '\(tmp.path)' /etc/hosts"
            + " && /usr/sbin/chown root:wheel /etc/hosts"
            + " && /bin/chmod 644 /etc/hosts"
            + " && /usr/bin/dscacheutil -flushcache"
            + " && (/usr/bin/killall mDNSResponder || true)"
        let script = "do shell script \"\(shell.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
            + " with administrator privileges"
            + " with prompt \"NetBlocker wants to update /etc/hosts.\""

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let err = String(decoding: stderrPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            if err.contains("-128") { throw HostsError.cancelled }
            throw HostsError.failed(err.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
