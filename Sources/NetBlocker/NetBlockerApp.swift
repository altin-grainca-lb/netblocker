import SwiftUI
import AppKit

@main
struct NetBlockerApp: App {
    @StateObject private var store = Store()

    /// Filled shield while at least one block is active, slashed shield otherwise.
    private var menuBarSymbol: String {
        store.apps.contains(where: \.isBlocked) ? "shield.fill" : "shield.slash"
    }

    /// Render the symbol at an explicit point size as a template image. The
    /// shield is a tall glyph, so letting the system auto-size it made it read
    /// larger than the other (wider) menu-bar icons; 15pt matches them.
    private var menuBarImage: NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        let image = NSImage(systemSymbolName: menuBarSymbol, accessibilityDescription: "NetBlocker")?
            .withSymbolConfiguration(config) ?? NSImage()
        image.isTemplate = true
        return image
    }

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(store)
        } label: {
            Image(nsImage: menuBarImage)
        }
        .menuBarExtraStyle(.window)
    }
}
