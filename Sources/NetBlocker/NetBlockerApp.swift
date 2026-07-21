import SwiftUI

@main
struct NetBlockerApp: App {
    @StateObject private var store = Store()

    /// Filled shield while at least one block is active, slashed shield otherwise.
    private var menuBarSymbol: String {
        store.apps.contains(where: \.isBlocked) ? "shield.fill" : "shield.slash"
    }

    var body: some Scene {
        MenuBarExtra("NetBlocker", systemImage: menuBarSymbol) {
            ContentView()
                .environmentObject(store)
        }
        .menuBarExtraStyle(.window)
    }
}
