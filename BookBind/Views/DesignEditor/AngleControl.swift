import AppKit
import SwiftUI

/// Numeric rotation control with mouse-wheel fine adjustment (illustration-editor convention).
struct AngleControl: View {
    let degrees: Double
    var fractionDigits: Int = 0
    var onCommit: (Double) -> Void
    var onEditingChanged: ((Bool) -> Void)?

    @State private var isHovered = false
    @State private var isFocused = false

    var body: some View {
        HStack(spacing: 8) {
            CoverInspectorNumberField(
                value: degrees,
                fractionDigits: fractionDigits,
                width: 56,
                onCommit: onCommit,
                onEditingChanged: { editing in
                    isFocused = editing
                    onEditingChanged?(editing)
                }
            )
            .help("Rotation in degrees. Scroll while hovered to nudge.")

            Text("°")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Button("-90°") { onCommit(-90) }
                .buttonStyle(.borderless)
                .help("Set rotation to −90°")

            Button("0°") { onCommit(0) }
                .buttonStyle(.borderless)
                .help("Reset rotation")
        }
        .background(
            AngleScrollCatcher(
                isActive: isHovered || isFocused,
                onScroll: { deltaY, shift in
                    let step = shift ? 15.0 : 1.0
                    let direction = deltaY > 0 ? -step : step
                    onCommit(degrees + direction)
                }
            )
        )
        .onHover { isHovered = $0 }
    }
}

/// AppKit scroll-wheel bridge for fine angle nudging.
private struct AngleScrollCatcher: NSViewRepresentable {
    var isActive: Bool
    var onScroll: (CGFloat, Bool) -> Void

    func makeNSView(context: Context) -> AngleScrollView {
        let view = AngleScrollView()
        view.onScroll = onScroll
        view.isActive = isActive
        return view
    }

    func updateNSView(_ nsView: AngleScrollView, context: Context) {
        nsView.onScroll = onScroll
        nsView.isActive = isActive
    }

    final class AngleScrollView: NSView {
        var isActive = false
        var onScroll: ((CGFloat, Bool) -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func scrollWheel(with event: NSEvent) {
            guard isActive else {
                super.scrollWheel(with: event)
                return
            }
            let delta = event.scrollingDeltaY != 0 ? event.scrollingDeltaY : event.deltaY
            guard abs(delta) > 0.01 else {
                super.scrollWheel(with: event)
                return
            }
            onScroll?(delta, event.modifierFlags.contains(.shift))
        }
    }
}
