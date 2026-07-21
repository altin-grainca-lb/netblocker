import Foundation

struct DNSProxyStatus: Equatable {
    var proxies: [String] = []          // active DNS-proxy products (best effort)
    var bypassed: Bool = false          // a blocked domain still resolves publicly

    var warningText: String? {
        if !proxies.isEmpty {
            return "Disable \(proxies.joined(separator: ", ")) to use NetBlocker."
        }
        if bypassed {
            return "A DNS proxy is bypassing /etc/hosts — disable it to use NetBlocker."
        }
        return nil
    }
}

/// Detects DNS proxies/VPNs that resolve names upstream without consulting
/// /etc/hosts (NextDNS, AdGuard, Cloudflare WARP, …).
///
/// The ground truth is the functional probe: if a domain we blocked still
/// resolves to a real address, something is bypassing the hosts file. When
/// domains are blocked, that probe alone decides — a proxy app that is
/// merely installed (or running but disabled) must not trigger the banner.
/// Only when nothing is blocked yet do we fall back to configuration
/// signals: an active DNS-proxy resolver in `scutil --dns`.
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

        if !blockedDomains.isEmpty {
            status.bypassed = blockedDomains.prefix(3).contains { resolvesPublicly($0) }
            if status.bypassed {
                status.proxies = namedRunningProxies()
            }
            // Hosts file demonstrably working -> stay silent.
            return status
        }

        // Nothing blocked yet: warn only if a DNS proxy is actively
        // registered in the system resolver configuration.
        if hasActiveProxyResolver() {
            status.proxies = namedRunningProxies()
            status.bypassed = status.proxies.isEmpty // generic fallback message
        }
        return status
    }

    // MARK: - Configuration signal (scutil --dns)

    /// Network-extension DNS proxies register resolvers pointing at reserved
    /// benchmark/documentation addresses (NextDNS uses 192.0.2.x, others use
    /// 198.18.x.x). A normal setup never has nameservers there.
    private static func hasActiveProxyResolver() -> Bool {
        let output = run("/usr/sbin/scutil", ["--dns"])
        for line in output.split(separator: "\n") where line.contains("nameserver") {
            if line.contains(" 192.0.2.") || line.contains(" 198.18.") || line.contains(" 198.19.") {
                return true
            }
        }
        return false
    }

    // MARK: - Naming the culprit (process scan, best effort)

    private static func namedRunningProxies() -> [String] {
        let commands = run("/bin/ps", ["-axo", "comm="])
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\n]", with: "", options: .regularExpression)

        var found: [String] = []
        for (pattern, name) in knownProxies
        where commands.contains(pattern) && !found.contains(name) {
            found.append(name)
        }
        return found
    }

    private static func run(_ path: String, _ args: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        guard (try? process.run()) != nil else { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Functional probe

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
