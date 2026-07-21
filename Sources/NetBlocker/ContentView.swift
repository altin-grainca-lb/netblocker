import SwiftUI
import AppKit
import ServiceManagement
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var store: Store

    @State private var proxyStatus = DNSProxyStatus()
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if let warning = proxyStatus.warningText {
                proxyBanner(warning)
                Divider()
            }

            if store.apps.isEmpty {
                emptyState
            } else {
                appList
            }

            Divider()
            footer
        }
        .frame(width: 340)
        .alert("Something went wrong", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            refreshProxyStatus()
        }
        .onChange(of: store.apps) { _ in refreshProxyStatus() }
    }

    private func refreshProxyStatus() {
        let sample = store.apps.filter(\.isBlocked).flatMap(\.domains)
        DispatchQueue.global(qos: .utility).async {
            let status = DNSProxyDetector.detect(blockedDomains: sample)
            DispatchQueue.main.async { proxyStatus = status }
        }
    }

    private func proxyBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: proxyStatus.bypassed
                  ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(proxyStatus.bypassed ? .red : .yellow)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((proxyStatus.bypassed ? Color.red : Color.yellow).opacity(0.08))
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
            Toggle("Launch at login", isOn: $launchAtLogin)
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .font(.caption)
                .onChange(of: launchAtLogin) { enable in
                    setLaunchAtLogin(enable)
                }
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func setLaunchAtLogin(_ enable: Bool) {
        let current = SMAppService.mainApp.status == .enabled
        guard enable != current else { return }
        do {
            if enable {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLogin = current
            store.errorMessage = "Could not update login item: \(error.localizedDescription)"
        }
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
        presentPicker(bundleURL: url, existing: nil)
    }

    private func rescan(_ app: ManagedApp) {
        presentPicker(bundleURL: URL(fileURLWithPath: app.bundlePath), existing: app)
    }

    /// The popover closes when the open panel takes focus, so the picker is
    /// a standalone window that shows up on its own.
    private func presentPicker(bundleURL: URL, existing: ManagedApp?) {
        PickerWindow.present(
            DomainPickerWindow(bundleURL: bundleURL, existing: existing)
                .environmentObject(store))
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
