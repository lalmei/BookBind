import SwiftUI

/// Compatibility wrapper — the dedicated marble surface is now `MarblingEditorView`.
struct EndpaperDesignerView: View {
    @ObservedObject var workspace: BindingWorkspace
    @Binding var isPresented: Bool
    var initiallyEditingFront: Bool = true

    @State private var editingFront = true
    @State private var draftSpec: MarbledPaperSpec = MarbledPaperSpec()

    private var pageSize: CGSize {
        if let trim = workspace.job.resolvedTrimSize {
            return CGSize(
                width: trim.width + workspace.job.bleedPoints * 2,
                height: trim.height + workspace.job.bleedPoints * 2
            )
        }
        return CGSize(width: 612, height: 792)
    }

    var body: some View {
        MarblingEditorView(
            spec: $draftSpec,
            pageSize: pageSize,
            onDone: {
                commit()
                isPresented = false
            }
        )
        .onAppear {
            editingFront = initiallyEditingFront
            let face = editingFront ? workspace.job.endpapers.front : workspace.job.endpapers.back
            draftSpec = face.marbling ?? MarbledPaperSpec()
        }
        .onChange(of: draftSpec) { newSpec in
            if editingFront {
                workspace.job.endpapers.front.mode = .marbled
                workspace.job.endpapers.front.marbling = newSpec
            } else {
                workspace.job.endpapers.back.mode = .marbled
                workspace.job.endpapers.back.marbling = newSpec
            }
            workspace.markChanged()
        }
    }

    private func commit() {
        if editingFront {
            workspace.job.endpapers.front.mode = .marbled
            workspace.job.endpapers.front.marbling = draftSpec
        } else {
            workspace.job.endpapers.back.mode = .marbled
            workspace.job.endpapers.back.marbling = draftSpec
        }
        workspace.markChanged()
    }
}
