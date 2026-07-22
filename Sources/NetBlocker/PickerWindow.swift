import SwiftUI
import AppKit
import Combine

/// The menu-bar popover closes as soon as an open panel takes focus, so the
/// domain picker gets its own floating window — it must appear on screen
/// right after the user chooses an app, without reopening the popover.
@MainActor
enum PickerWindow {
    private static var window: NSWindow?
    private static let centerer = Centerer()

    static func present<V: View>(_ view: V) {
        close()
        let hosting = NSHostingController(rootView: view)
        let win = NSWindow(contentViewController: hosting)
        win.title = "NetBlocker"
        win.styleMask = [.titled, .closable]
        win.isReleasedWhenClosed = false
        // Don't let macOS restore/reopen this window on the next launch — it
        // should appear only when the user actually opens the picker.
        win.isRestorable = false
        win.level = .floating
        // Re-center on every resize: the window starts at the "scanning"
        // spinner size and grows when the domain list loads, so a one-shot
        // center at creation ends up off after the content settles.
        win.delegate = centerer
        window = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
        centerOnScreen(win)
    }

    /// True center of the active screen's visible area (below the menu bar,
    /// above the Dock). center() biases toward the top third, so compute it.
    fileprivate static func centerOnScreen(_ win: NSWindow) {
        guard let screen = win.screen ?? NSScreen.main else { return }
        let area = screen.visibleFrame
        let size = win.frame.size
        win.setFrameOrigin(NSPoint(
            x: area.midX - size.width / 2,
            y: area.midY - size.height / 2))
    }

    static func close() {
        window?.close()
        window = nil
    }

    private final class Centerer: NSObject, NSWindowDelegate {
        func windowDidResize(_ notification: Notification) {
            guard let win = notification.object as? NSWindow else { return }
            PickerWindow.centerOnScreen(win)
        }
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
                    bundlePath: bundleURL.path,
                    isEdit: existing != nil,
                    initialHits: hits,
                    onCancel: { PickerWindow.close() },
                    onConfirm: { selected in
                        confirm(selected)
                        PickerWindow.close()
                    },
                    // Offer "remove" only for an already-managed app.
                    onRemove: existing.map { app in { store.remove(app); PickerWindow.close() } })
            } else {
                ScanningView(appName: appName,
                             icon: NSWorkspace.shared.icon(forFile: bundleURL.path))
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

/// Scanning placeholder: the app's icon does a single spin, pauses, then
/// spins again — repeating. A timer drives each spin so there's a real wait
/// between them (a plain repeatForever would spin continuously).
private struct ScanningView: View {
    let appName: String
    let icon: NSImage

    private let spin = 0.7   // seconds each rotation takes
    // Fires once per cycle (spin 0.7s + pause 0.6s); each firing does one spin.
    private let timer = Timer.publish(every: 1.3, on: .main, in: .common).autoconnect()
    @State private var rotation: Double = 0

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 64, height: 64)
                .rotationEffect(.degrees(rotation))
            Text("Scanning \(appName)…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(width: 400, height: 180)
        .onAppear { spinOnce() }
        .onReceive(timer) { _ in spinOnce() }
    }

    private func spinOnce() {
        withAnimation(.easeInOut(duration: spin)) { rotation += 360 }
    }
}

struct DomainPickerView: View {
    let name: String
    let bundlePath: String
    let isEdit: Bool
    let onCancel: () -> Void
    let onConfirm: ([String]) -> Void
    /// Non-nil only when editing a managed app: removes it from NetBlocker.
    let onRemove: (() -> Void)?

    @State private var hits: [DomainHit]
    /// Categories the user has collapsed (accordion). Empty = all expanded.
    @State private var collapsed: Set<DomainCategory> = []

    /// Cached once — NSWorkspace.icon(forFile:) returns a fresh NSImage each
    /// call, so recomputing it per render made the icon flash when a category
    /// expand/collapse animation re-evaluated the body.
    private let appIcon: NSImage

    init(name: String, bundlePath: String, isEdit: Bool, initialHits: [DomainHit],
         onCancel: @escaping () -> Void, onConfirm: @escaping ([String]) -> Void,
         onRemove: (() -> Void)? = nil) {
        self.name = name
        self.bundlePath = bundlePath
        self.isEdit = isEdit
        self.onCancel = onCancel
        self.onConfirm = onConfirm
        self.onRemove = onRemove
        self.appIcon = NSWorkspace.shared.icon(forFile: bundlePath)
        _hits = State(initialValue: initialHits)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Block \(name)").font(.headline)
                    Text("\(hits.count) domain\(hits.count == 1 ? "" : "s") found inside the app")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                // Remove this app from NetBlocker (only when already managed).
                if let onRemove {
                    DeleteButton(action: onRemove)
                }
                // Master switch: turns every domain (all categories) on/off.
                Toggle("", isOn: Binding(
                    get: { !hits.isEmpty && hits.allSatisfy(\.selected) },
                    set: { on in for i in hits.indices { hits[i].selected = on } }))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .tint(.red)
                    .pointingHandCursor()
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
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(DomainCategory.allCases, id: \.self) { category in
                            let indices = hits.indices.filter {
                                DomainCategory.classify(hits[$0].domain, appName: name) == category
                            }
                            if !indices.isEmpty {
                                CategorySection(
                                    category: category,
                                    indices: indices,
                                    isExpanded: !collapsed.contains(category),
                                    hits: $hits,
                                    onToggleExpand: { toggleExpand(category) })
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
                .frame(height: 300)
            }

            Divider()

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .pointingHandCursor()
                Button(isEdit ? "Save" : "Block") {
                    onConfirm(hits.filter(\.selected).map(\.domain))
                }
                .keyboardShortcut(.defaultAction)
                .tint(.blue)
                .disabled(hits.allSatisfy { !$0.selected })
                .pointingHandCursor(!hits.allSatisfy { !$0.selected })
            }
            .padding(12)
        }
        .frame(width: 400)
    }

    private func toggleExpand(_ category: DomainCategory) {
        // No withAnimation here: it would animate everything in this pass
        // (including hover backgrounds on other headers), which flashed.
        // CategorySection scopes its own animation to isExpanded instead.
        if collapsed.contains(category) { collapsed.remove(category) }
        else { collapsed.insert(category) }
    }
}

// MARK: - Category section (collapsible)

private struct CategorySection: View {
    let category: DomainCategory
    let indices: [Int]
    let isExpanded: Bool
    @Binding var hits: [DomainHit]
    let onToggleExpand: () -> Void

    @State private var hover = false

    /// Whether every domain in the category is currently selected.
    private var allSelected: Bool {
        !indices.isEmpty && indices.allSatisfy { hits[$0].selected }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
                    .frame(width: 12)
                Image(systemName: category.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(category.tint)
                    .frame(width: 16)
                Text(category.rawValue.uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                Spacer()
                // Master switch: turns every domain in the category on/off.
                Toggle("", isOn: Binding(
                    get: { allSelected },
                    set: { on in for i in indices { hits[i].selected = on } }))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                    .tint(.red)
                    .pointingHandCursor()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(Color.primary.opacity(hover ? 0.06 : 0))
            .onHover { hover = $0 }
            .pointingHandCursor()
            .onTapGesture(perform: onToggleExpand)

            if isExpanded {
                ForEach(indices, id: \.self) { i in
                    DomainRow(hit: $hits[i])
                }
            }
        }
    }
}

// MARK: - Domain row (whole row toggles the switch)

private struct DomainRow: View {
    @Binding var hit: DomainHit
    @State private var hover = false

    var body: some View {
        HStack(spacing: 10) {
            Text(hit.domain)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(hit.selected ? .primary : .secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            // Visual only — the whole row drives the toggle via onTapGesture.
            Toggle("", isOn: $hit.selected)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .tint(.red)
                .allowsHitTesting(false)
        }
        // Indent domains to line up with the category title text
        // (header: 14 leading + 12 chevron + 7 + 16 icon + 7 = 56).
        .padding(.leading, 56)
        .padding(.trailing, 14)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .background(Color.primary.opacity(hover ? 0.06 : 0))
        .onHover { hover = $0 }
        .pointingHandCursor()
        .onTapGesture { hit.selected.toggle() }
    }
}
