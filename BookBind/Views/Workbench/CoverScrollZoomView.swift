import AppKit
import SwiftUI

struct CoverScrollZoomView: NSViewRepresentable {
    var onZoom: (CGFloat) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = PassthroughView()
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onZoom = onZoom
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onZoom: onZoom)
    }

    final class Coordinator {
        var onZoom: (CGFloat) -> Void
        private weak var view: NSView?
        private var monitor: Any?

        init(onZoom: @escaping (CGFloat) -> Void) {
            self.onZoom = onZoom
        }

        func attach(to view: NSView) {
            self.view = view
            detach()
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, self.shouldHandle(event) else { return event }
                self.onZoom(event.scrollingDeltaY)
                return nil
            }
        }

        func detach() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }

        private func shouldHandle(_ event: NSEvent) -> Bool {
            guard event.modifierFlags.contains(.command),
                  let view,
                  let window = view.window,
                  event.window === window else {
                return false
            }
            let point = view.convert(event.locationInWindow, from: nil)
            return view.bounds.contains(point)
        }
    }

    private final class PassthroughView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }
    }
}
