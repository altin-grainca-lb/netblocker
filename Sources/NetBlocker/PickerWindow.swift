import SwiftUI
import AppKit

/// The menu-bar popover closes as soon as an open panel takes focus, so the
/// domain picker gets its own floating window — it must appear on screen
/// right after the user chooses an app, without reopening the popover.
@MainActor
enum PickerWindow {
    private static var window: NSWindow?

    static func present<V: View>(_ view: V) {
        close()
        let hosting = NSHostingController(rootView: view)
        let win = NSWindow(contentViewController: hosting)
        win.title = "NetBlocker"
        win.styleMask = [.titled, .closable]
        win.isReleasedWhenClosed = false
        win.level = .floating
        win.center()
        window = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    static func close() {
        window?.close()
        window = nil
    }
}

/// Scans the chosen app (spinner while working), then shows the domain
/// picker. Confirming saves the app and applies the block.
struct DomainPickerWindow: View {
    let bundleURL: URL
    let existing: ManagedApp?
    @EnvironmentObject var store: Store
    @State private var hits: [DomainHit]?

    private var appName: String { bundleURL.deletingPathExtension().lastPathComponent }

    var body: some View {
        Group {
            if let hits {
                DomainPickerView(
                    name: appName,
                    isEdit: existing != nil,
                    initialHits: hits,
                    onCancel: { PickerWindow.close() },
                    onConfirm: { selected in
                        confirm(selected)
                        PickerWindow.close()
                    })
            } else {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Scanning \(appName)…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 380, height: 160)
            }
        }
        .task {
            let url = bundleURL
            let previous = existing
            hits = await Task.detached(priority: .userInitiated) { () -> [DomainHit] in
                var found = AppScanner.scan(bundleURL: url)
                if let previous {
                    let chosen = Set(previous.domains)
                    for i in found.indices { found[i].selected = chosen.contains(found[i].domain) }
                    for domain in chosen where !found.contains(where: { $0.domain == domain }) {
                        found.insert(DomainHit(domain: domain, count: 0, selected: true), at: 0)
                    }
                }
                return found
            }.value
        }
    }

    private func confirm(_ selected: [String]) {
        let appID = existing?.id
            ?? Bundle(url: bundleURL)?.bundleIdentifier
            ?? appName.lowercased().replacingOccurrences(of: " ", with: "-")
        let app = ManagedApp(
            id: appID, name: appName, bundlePath: bundleURL.path,
            domains: selected, isBlocked: existing?.isBlocked ?? false)
        store.upsert(app)
        // New apps get blocked right away; edited apps that were already
        // blocked get their hosts section refreshed.
        if existing == nil || app.isBlocked {
            store.setBlocked(true, for: app)
        }
    }
}

struct DomainPickerView: View {
    let name: String
    let isEdit: Bool
    let onCancel: () -> Void
    let onConfirm: ([String]) -> Void

    @State private var hits: [DomainHit]

    init(name: String, isEdit: Bool, initialHits: [DomainHit],
         onCancel: @escaping () -> Void, onConfirm: @escaping ([String]) -> Void) {
        self.name = name
        self.isEdit = isEdit
        self.onCancel = onCancel
        self.onConfirm = onConfirm
        _hits = State(initialValue: initialHits)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Block \(name)").font(.headline)
                Text("Domains found inside the app. Checked ones will stop resolving.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)

            Divider()

            if hits.isEmpty {
                Text("No domains found in this app's binaries.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                List($hits) { $hit in
                    Toggle(isOn: $hit.selected) {
                        HStack {
                            Text(hit.domain).font(.system(.callout, design: .monospaced))
                            Spacer()
                            if hit.count > 0 {
                                Text("×\(hit.count)")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .frame(height: 260)
            }

            Divider()

            HStack {
                Button("Select None") { for i in hits.indices { hits[i].selected = false } }
                    .controlSize(.small)
                Button("Select All") { for i in hits.indices { hits[i].selected = true } }
                    .controlSize(.small)
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(isEdit ? "Save" : "Block") {
                    onConfirm(hits.filter(\.selected).map(\.domain))
                }
                .keyboardShortcut(.defaultAction)
                .disabled(hits.allSatisfy { !$0.selected })
            }
            .padding(12)
        }
        .frame(width: 380)
    }
}
