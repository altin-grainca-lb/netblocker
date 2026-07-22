import SwiftUI
import AppKit
import ServiceManagement
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    @State private var proxyStatus = DNSProxyStatus()
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var listHeight: CGFloat = 0

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
        HStack(spacing: 10) {
            Image(systemName: "shield.slash").foregroundStyle(.tint)
            Text("NetBlocker").font(.headline)
            Spacer()
            // Master switch: block/unblock every app at once (one prompt).
            Toggle("", isOn: Binding(
                get: { !store.apps.isEmpty && store.apps.allSatisfy(\.isBlocked) },
                set: { store.setAllBlocked($0) }))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .tint(.red)
                .disabled(store.apps.isEmpty)
                .pointingHandCursor(!store.apps.isEmpty)
                .help("Turn all blocking on or off")
            Button {
                addApp()
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .help("Add an app to block")
            .pointingHandCursor()
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
                .pointingHandCursor()
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
                        isDisabled: proxyStatus.bypassed,
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
            .background(GeometryReader { proxy in
                Color.clear.preference(key: AppListHeightKey.self, value: proxy.size.height)
            })
        }
        // The menu-bar window sizes to the content's *ideal* height, and a
        // ScrollView's ideal height is zero — without an explicit height the
        // list collapses and disappears. Measure the rows and cap at 320.
        .frame(height: min(max(listHeight, 44), 320))
        .onPreferenceChange(AppListHeightKey.self) { listHeight = $0 }
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
                .pointingHandCursor()
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .controlSize(.small)
                .pointingHandCursor()
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

    /// Close the menu-bar popup so it doesn't sit on top of the open panel
    /// or the picker window. dismiss() alone doesn't reliably close a
    /// MenuBarExtra window on macOS 13, so also close SwiftUI's private
    /// popup window (class "MenuBarExtraWindow") directly.
    private func closePopup() {
        dismiss()
        for window in NSApp.windows where window.className.contains("MenuBarExtraWindow") {
            window.close()
        }
    }

    private func addApp() {
        closePopup()
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

    /// The picker is a standalone window; close the menu-bar popup first so
    /// the two don't overlap (already closed when coming from addApp).
    private func presentPicker(bundleURL: URL, existing: ManagedApp?) {
        closePopup()
        PickerWindow.present(
            DomainPickerWindow(bundleURL: bundleURL, existing: existing)
                .environmentObject(store))
    }
}

private struct AppListHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Rows and sheet

struct AppRow: View {
    let app: ManagedApp
    /// Blocking is ineffective (a DNS proxy bypasses /etc/hosts): grey the row
    /// and freeze the block controls. Removal stays available regardless.
    var isDisabled: Bool = false
    let onToggle: (Bool) -> Void
    let onEdit: () -> Void
    let onRemove: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            // Real container (not Group) so the tap/hover frame below covers
            // the icon, name AND the Spacer gap up to the trash button.
            HStack(spacing: 10) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.bundlePath))
                    .resizable()
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.name).font(.callout).lineLimit(1)
                    Text("\(app.domains.count) domain\(app.domains.count == 1 ? "" : "s")\(app.isBlocked ? " blocked" : "")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .opacity(isDisabled ? 0.4 : 1)
            Spacer()
            // Space is always reserved; the button only fades in on row hover.
            DeleteButton(action: onRemove)
                .opacity(isHovered ? 1 : 0)
            Toggle("", isOn: Binding(get: { app.isBlocked }, set: onToggle))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .tint(.red)
                .disabled(isDisabled)
                .pointingHandCursor(!isDisabled)
                .help(isDisabled
                      ? "Blocking is bypassed by a DNS proxy — remove is still available"
                      : (app.isBlocked ? "Blocked — toggle to allow" : "Allowed — toggle to block"))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(isHovered && !isDisabled ? 0.07 : 0))
        )
        // The whole row opens edit; the trash button and toggle consume their
        // own taps first, so clicking those doesn't trigger an edit.
        .contentShape(Rectangle())
        .onTapGesture { if !isDisabled { onEdit() } }
        .onHover { isHovered = $0 }
        .pointingHandCursor(!isDisabled)
    }
}

/// Remove affordance: a subtle trash glyph that lights up red inside a soft
/// circular background when pointed at. Kept small and quiet so it doesn't
/// dominate the row (it also only appears on row hover).
struct DeleteButton: View {
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "trash")
                .font(.system(size: 12))
                .foregroundStyle(hover ? Color.red : Color.secondary)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.red.opacity(hover ? 0.15 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Remove (and unblock)")
        .onHover { hover = $0 }
        .pointingHandCursor()
    }
}
