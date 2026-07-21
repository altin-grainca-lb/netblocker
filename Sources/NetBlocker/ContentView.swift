import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var store: Store

    @State private var isScanning = false
    @State private var scanningName = ""
    @State private var pendingApp: PendingApp?

    /// App picked from the open panel, waiting for domain selection.
    struct PendingApp: Identifiable {
        let id: String
        let name: String
        let bundlePath: String
        var hits: [DomainHit]
        let existing: ManagedApp?
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if store.apps.isEmpty && !isScanning {
                emptyState
            } else {
                appList
            }

            if isScanning {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Scanning \(scanningName)…").font(.callout).foregroundStyle(.secondary)
                }
                .padding(12)
            }

            Divider()
            footer
        }
        .frame(width: 340)
        .sheet(item: $pendingApp) { pending in
            DomainPickerSheet(pending: pending) { selected in
                confirmDomains(pending: pending, selected: selected)
            }
        }
        .alert("Something went wrong", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } })
    }

    private var header: some View {
        HStack {
            Image(systemName: "shield.slash").foregroundStyle(.tint)
            Text("NetBlocker").font(.headline)
            Spacer()
            Button {
                addApp()
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .disabled(isScanning)
            .help("Add an app to block")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "app.dashed")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("No apps yet").font(.callout).bold()
            Text("Add an app to discover the servers it talks to, then block them.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Add App…") { addApp() }
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
    }

    private var appList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(store.apps) { app in
                    AppRow(
                        app: app,
                        onToggle: { store.setBlocked($0, for: app) },
                        onEdit: { rescan(app) },
                        onRemove: { store.remove(app) }
                    )
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    if app.id != store.apps.last?.id { Divider().padding(.leading, 12) }
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxHeight: 320)
    }

    private var footer: some View {
        HStack {
            Text("Blocks via /etc/hosts")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Actions

    private func addApp() {
        let panel = NSOpenPanel()
        panel.title = "Choose an app to block"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        scan(bundleURL: url, existing: nil)
    }

    private func rescan(_ app: ManagedApp) {
        scan(bundleURL: URL(fileURLWithPath: app.bundlePath), existing: app)
    }

    private func scan(bundleURL: URL, existing: ManagedApp?) {
        let name = bundleURL.deletingPathExtension().lastPathComponent
        let appID = Bundle(url: bundleURL)?.bundleIdentifier
            ?? name.lowercased().replacingOccurrences(of: " ", with: "-")

        isScanning = true
        scanningName = name
        DispatchQueue.global(qos: .userInitiated).async {
            var hits = AppScanner.scan(bundleURL: bundleURL)
            // When editing, reflect the previously selected domains.
            if let existing {
                let chosen = Set(existing.domains)
                for i in hits.indices { hits[i].selected = chosen.contains(hits[i].domain) }
                for domain in chosen where !hits.contains(where: { $0.domain == domain }) {
                    hits.insert(DomainHit(domain: domain, count: 0, selected: true), at: 0)
                }
            }
            DispatchQueue.main.async {
                isScanning = false
                pendingApp = PendingApp(
                    id: appID, name: name, bundlePath: bundleURL.path,
                    hits: hits, existing: existing)
            }
        }
    }

    private func confirmDomains(pending: PendingApp, selected: [String]) {
        var app = ManagedApp(
            id: pending.id, name: pending.name, bundlePath: pending.bundlePath,
            domains: selected, isBlocked: pending.existing?.isBlocked ?? false)
        store.upsert(app)
        // Apply immediately: new apps get blocked right away; edited apps
        // that were already blocked get their hosts section refreshed.
        if pending.existing == nil || app.isBlocked {
            store.setBlocked(true, for: app)
            app.isBlocked = true
        }
    }
}

// MARK: - Rows and sheet

struct AppRow: View {
    let app: ManagedApp
    let onToggle: (Bool) -> Void
    let onEdit: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.bundlePath))
                .resizable()
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name).font(.callout).lineLimit(1)
                Text("\(app.domains.count) domain\(app.domains.count == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onEdit) { Image(systemName: "pencil") }
                .buttonStyle(.borderless)
                .help("Edit blocked domains")
            Button(action: onRemove) { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .help("Remove (and unblock)")
            Toggle("", isOn: Binding(get: { app.isBlocked }, set: onToggle))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .help(app.isBlocked ? "Blocked — toggle to allow" : "Allowed — toggle to block")
        }
    }
}

struct DomainPickerSheet: View {
    let pending: ContentView.PendingApp
    let onConfirm: ([String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var hits: [DomainHit] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Block \(pending.name)").font(.headline)
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
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(pending.existing == nil ? "Block" : "Save") {
                    onConfirm(hits.filter(\.selected).map(\.domain))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(hits.allSatisfy { !$0.selected })
            }
            .padding(12)
        }
        .frame(width: 380)
        .onAppear { hits = pending.hits }
    }
}
