import Foundation

struct DNSProxyStatus: Equatable {
    var proxies: [String] = []          // detected DNS-proxy products
    var bypassed: Bool = false          // a blocked domain still resolves publicly

    var warningText: String? {
        if bypassed {
            let who = proxies.isEmpty ? "A DNS proxy" : proxies.joined(separator: ", ")
            return "\(who) is answering DNS without reading /etc/hosts — blocks are being bypassed. Add the domains to its denylist instead."
        }
        if !proxies.isEmpty {
            return "\(proxies.joined(separator: ", ")) detected — it may bypass /etc/hosts blocks."
        }
        return nil
    }
}

/// Detects DNS proxies/VPNs that resolve names upstream without consulting
/// /etc/hosts (NextDNS, AdGuard, Cloudflare WARP, …). Two signals:
/// 1. Known proxy processes in the process list.
/// 2. The ground truth: a domain we have blocked still resolving to a real
///    address means something is bypassing the hosts file.
enum DNSProxyDetector {

    private static let knownProxies: [(pattern: String, name: String)] = [
        ("nextdns", "NextDNS"),
        ("adguard", "AdGuard"),
        ("dnscrypt", "dnscrypt-proxy"),
        ("cloudflarewarp", "Cloudflare WARP"),
        ("warpsvc", "Cloudflare WARP"),
        ("mullvad", "Mullvad VPN"),
        ("protonvpn", "Proton VPN"),
        ("zscaler", "Zscaler"),
    ]

    /// `blockedDomains`: a sample of domains that should currently be
    /// null-routed (used for the functional bypass probe).
    static func detect(blockedDomains: [String]) -> DNSProxyStatus {
        var status = DNSProxyStatus()
        status.proxies = runningProxies()
        status.bypassed = blockedDomains.prefix(3).contains { resolvesPublicly($0) }
        return status
    }

    // MARK: - Signal 1: known proxy processes

    private static func runningProxies() -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "comm="]
        let pipe = Pipe()
        process.standardOutput = pipe
        guard (try? process.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let commands = String(decoding: data, as: UTF8.self)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\n]", with: "", options: .regularExpression)

        var found: [String] = []
        for (pattern, name) in knownProxies
        where commands.contains(pattern) && !found.contains(name) {
            found.append(name)
        }
        return found
    }

    // MARK: - Signal 2: functional probe

    /// True when the domain resolves to a real (non-blackhole) address even
    /// though we blocked it. Resolution failures return false — offline or
    /// NXDOMAIN both mean the app can't reach the host, which is what the
    /// user wanted.
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
