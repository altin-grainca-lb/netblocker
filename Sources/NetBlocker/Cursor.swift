import SwiftUI
import AppKit

extension View {
    /// Shows the pointing-hand cursor while the pointer is over this view —
    /// the standard cue that something is clickable. `enabled: false` leaves
    /// the normal arrow (e.g. for a disabled control).
    func pointingHandCursor(_ enabled: Bool = true) -> some View {
        modifier(PointingHandCursor(enabled: enabled))
    }
}

private struct PointingHandCursor: ViewModifier {
    let enabled: Bool
    @State private var inside = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                inside = hovering
                if hovering && enabled { NSCursor.pointingHand.push() }
                else { NSCursor.pop() }
            }
            // Pop if the view is removed while hovered (e.g. a collapsing
            // section) so the pointing-hand cursor can't get stranded.
            .onDisappear { if inside { NSCursor.pop(); inside = false } }
    }
}
