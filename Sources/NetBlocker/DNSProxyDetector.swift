import Foundation

struct DNSProxyStatus: Equatable {
    var bypassed: Bool = false          // a blocked domain still resolves publicly
    var interceptors: [String] = []     // active network filters likely responsible

    var warningText: String? {
        guard bypassed else { return nil }
        var msg = "Blocking isn’t taking effect — something on this Mac is resolving DNS and ignoring /etc/hosts."
        if !interceptors.isEmpty {
            msg += " Likely: \(interceptors.joined(separator: ", "))."
        }
        return msg
    }
}

/// Decides whether NetBlocker's /etc/hosts blocks are actually working.
///
/// The authoritative signal is a functional probe: if a domain we blocked
/// still resolves to a real (non-blackhole) address, some resolver is
/// bypassing /etc/hosts — DNS proxies (NextDNS, AdGuard), VPN MagicDNS, or
/// corporate network filters (Microsoft Defender, Zscaler, GlobalProtect)
/// all do this. A previous version blamed NextDNS purely because its process
/// was running, which was wrong when NextDNS was disabled; process presence
/// is no longer used. We only *name* a likely culprit from the list of
/// active network-filter system extensions, and only as a hint.
enum DNSProxyDetector {

    /// `blockedDomains`: domains that should currently be null-routed.
    /// Pass several (not just one per app) so a mix of live and dead domains
    /// still surfaces a bypass.
    static func detect(blockedDomains: [String]) -> DNSProxyStatus {
        var status = DNSProxyStatus()
        guard !blockedDomains.isEmpty else { return status }

        status.bypassed = blockedDomains.prefix(8).contains { resolvesPublicly($0) }
        if status.bypassed {
            status.interceptors = activeNetworkFilters()
        }
        return status
    }

    // MARK: - Naming the likely culprit (active network extensions)

    /// Human names of enabled, active network-extension filters — the things
    /// that genuinely sit below /etc/hosts. Read from `systemextensionsctl`
    /// (no privileges needed). Idle-but-loaded extensions may appear; this is
    /// only a hint shown alongside the authoritative probe result.
    private static func activeNetworkFilters() -> [String] {
        let vendors: [(needle: String, name: String)] = [
            ("wdav", "Microsoft Defender"),
            ("zscaler", "Zscaler"),
            ("globalprotect", "GlobalProtect"),
            ("paloaltonetworks", "GlobalProtect"),
            ("cisco.anyconnect", "Cisco AnyConnect"),
            ("umbrella", "Cisco Umbrella"),
            ("nextdns", "NextDNS"),
            ("adguard", "AdGuard"),
            ("tailscale", "Tailscale"),
            ("littlesnitch", "Little Snitch"),
        ]

        let output = run("/usr/bin/systemextensionsctl", ["list"]).lowercased()
        var found: [String] = []
        for line in output.split(separator: "\n") {
            // Only lines describing an activated/enabled extension.
            guard line.contains("activated"), line.contains("enabled") else { continue }
            for vendor in vendors
            where line.contains(vendor.needle) && !found.contains(vendor.name) {
                found.append(vendor.name)
            }
        }
        return found
    }

    private static func run(_ path: String, _ args: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Functional probe

    /// True when the domain resolves to a real (non-blackhole) address even
    /// though we blocked it. Resolution failures return false — offline or
    /// NXDOMAIN both mean the app can't reach the host, which is the goal.
    private static func resolvesPublicly(_ domain: String) -> Bool {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM

        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(domain, "443", &hints, &result) == 0 else { return false }
        defer { freeaddrinfo(result) }

        let blackholes: Set<String> = ["0.0.0.0", "::", "127.0.0.1", "::1"]
        var node = result
        while let info = node?.pointee {
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(info.ai_addr, info.ai_addrlen,
                           &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                if !blackholes.contains(String(cString: host)) { return true }
            }
            node = info.ai_next
        }
        return false
    }
}
