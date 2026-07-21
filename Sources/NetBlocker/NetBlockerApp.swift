import SwiftUI

@main
struct NetBlockerApp: App {
    @StateObject private var store = Store()

    var body: some Scene {
        MenuBarExtra("NetBlocker", systemImage: "shield.slash") {
            ContentView()
                .environmentObject(store)
        }
        .menuBarExtraStyle(.window)
    }
}
