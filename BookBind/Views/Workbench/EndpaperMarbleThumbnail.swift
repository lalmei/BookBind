import AppKit
import SwiftUI

/// Compact async marbling preview for the Imposition Endpapers inspector.
struct EndpaperMarbleThumbnail: View {
    let spec: MarbledPaperSpec

    @State private var image: NSImage?
    @State private var renderTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Color(nsColor: .controlBackgroundColor)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            } else {
                ProgressView()
                    .controlSize(.mini)
            }
        }
        .onAppear { scheduleRender() }
        .onChange(of: spec) { _ in scheduleRender() }
        .onDisappear { renderTask?.cancel() }
    }

    private func scheduleRender() {
        renderTask?.cancel()
        let snapshot = spec
        renderTask = Task {
            let rendered: NSImage? = await Task.detached(priority: .utility) {
                guard let cg = MarbledPaperGenerator.render(spec: snapshot, width: 66, height: 84) else {
                    return nil
                }
                return NSImage(cgImage: cg, size: NSSize(width: 44, height: 56))
            }.value
            guard !Task.isCancelled else { return }
            await MainActor.run { image = rendered }
        }
    }
}
