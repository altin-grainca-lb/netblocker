import Foundation
import SwiftUI

struct ManagedApp: Codable, Identifiable, Equatable {
    var id: String            // stable key used in /etc/hosts markers (bundle id or sanitized name)
    var name: String
    var bundlePath: String
    var domains: [String]     // domains selected for blocking
    var isBlocked: Bool
}

struct DomainHit: Identifiable, Equatable {
    var id: String { domain }
    let domain: String
    let count: Int
    var selected: Bool
}

/// Buckets for the domain picker so related domains read as one group.
/// Declaration order is display order; `.app` (the app's own domains) first.
enum DomainCategory: String, CaseIterable {
    case app = "App domains"
    case payments = "Payments"
    case analytics = "Analytics & Crash Reporting"
    case updates = "Updates & Downloads"
    case ai = "AI Services"
    case developer = "Developer & Code"
    case social = "Social & Marketing"
    case other = "Other"

    private static let keywords: [(DomainCategory, [String])] = [
        (.payments, ["lemonsqueezy", "stripe", "paddle", "paypal", "gumroad",
                     "braintree", "chargebee", "revenuecat", "fastspring",
                     "checkout.com", "polar.sh"]),
        (.analytics, ["sentry", "crashlytics", "mixpanel", "segment.", "amplitude",
                      "posthog", "telemetry", "analytics", "datadog", "bugsnag",
                      "appcenter", "firebase", "statsig", "hotjar"]),
        (.updates, ["sparkle-project", "appcast", "updates.", "update.",
                    "dl.", "download", "releases."]),
        (.ai, ["anthropic", "openai", "kimi", "z.ai", "mistral", "groq",
               "gemini", "deepseek", "perplexity"]),
        (.developer, ["github", "gitlab", "bitbucket", "npmjs", "docker"]),
        (.social, ["twitter", "x.com", "facebook", "instagram", "linkedin",
                   "discord", "slack", "telegram", "youtube", "tiktok"]),
    ]

    var symbol: String {
        switch self {
        case .app:       return "app.fill"
        case .payments:  return "creditcard.fill"
        case .analytics: return "chart.bar.fill"
        case .updates:   return "arrow.down.circle.fill"
        case .ai:        return "sparkles"
        case .developer: return "chevron.left.forwardslash.chevron.right"
        case .social:    return "bubble.left.and.bubble.right.fill"
        case .other:     return "globe"
        }
    }

    var tint: Color {
        switch self {
        case .app:       return .accentColor
        case .payments:  return .green
        case .analytics: return .orange
        case .updates:   return .blue
        case .ai:        return .purple
        case .developer: return .teal
        case .social:    return .pink
        case .other:     return .gray
        }
    }

    /// `appName` routes the app's own domains (e.g. "Vibe Island" →
    /// vibeisland.app) into `.app` ahead of the keyword buckets.
    static func classify(_ domain: String, appName: String) -> DomainCategory {
        let d = domain.lowercased()
        let squashed = appName.lowercased().filter { $0.isLetter || $0.isNumber }
        if !squashed.isEmpty, d.replacingOccurrences(of: "-", with: "").contains(squashed) {
            return .app
        }
        for (category, needles) in keywords where needles.contains(where: d.contains) {
            return category
        }
        return .other
    }
}

@MainActor
final class Store: ObservableObject {
    @Published var apps: [ManagedApp] = []
    @Published var errorMessage: String?

    private static let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NetBlocker", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("apps.json")
    }()

    init() {
        load()
        reconcileWithHostsFile()
    }

    func load() {
        guard let data = try? Data(contentsOf: Self.fileURL),
              let decoded = try? JSONDecoder().decode([ManagedApp].self, from: data) else { return }
        apps = decoded
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(apps) {
            try? data.write(to: Self.fileURL, options: .atomic)
        }
    }

    /// The hosts file is the source of truth for what is actually blocked
    /// (the user may have edited it, or a block may have been applied by an
    /// earlier install). Sync our flags with it on launch.
    func reconcileWithHostsFile() {
        let content = HostsManager.currentContent()
        for i in apps.indices {
            apps[i].isBlocked = HostsManager.isBlocked(appID: apps[i].id, in: content)
        }
        save()
    }

    func upsert(_ app: ManagedApp) {
        if let i = apps.firstIndex(where: { $0.id == app.id }) {
            apps[i] = app
        } else {
            apps.append(app)
        }
        save()
    }

    func setBlocked(_ blocked: Bool, for app: ManagedApp) {
        do {
            let current = HostsManager.currentContent()
            let updated = HostsManager.contentApplying(
                block: blocked, appID: app.id, domains: app.domains, to: current)
            try HostsManager.apply(newContent: updated)
            if let i = apps.firstIndex(where: { $0.id == app.id }) {
                apps[i].isBlocked = blocked
                save()
            }
        } catch HostsError.cancelled {
            // User dismissed the password prompt — leave state as-is.
            objectWillChange.send()
        } catch {
            errorMessage = error.localizedDescription
            objectWillChange.send()
        }
    }

    /// Block or unblock every managed app in one hosts write (a single
    /// password prompt), used by the header master switch.
    func setAllBlocked(_ blocked: Bool) {
        guard !apps.isEmpty else { return }
        do {
            var content = HostsManager.currentContent()
            for app in apps {
                content = HostsManager.contentApplying(
                    block: blocked, appID: app.id, domains: app.domains, to: content)
            }
            try HostsManager.apply(newContent: content)
            for i in apps.indices { apps[i].isBlocked = blocked }
            save()
        } catch HostsError.cancelled {
            objectWillChange.send()
        } catch {
            errorMessage = error.localizedDescription
            objectWillChange.send()
        }
    }

    func remove(_ app: ManagedApp) {
        if app.isBlocked {
            setBlocked(false, for: app)
            // If unblocking failed (e.g. cancelled prompt), keep the entry.
            if apps.first(where: { $0.id == app.id })?.isBlocked == true { return }
        }
        apps.removeAll { $0.id == app.id }
        save()
    }
}
