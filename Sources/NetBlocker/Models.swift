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
