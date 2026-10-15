import AppKit
import SceneKit
import SwiftUI

/// SceneKit host with orbit controls for the 3D book preview.
struct BookPreview3DView: NSViewRepresentable {
    let scene: SCNScene
    var resetToken: Int

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.scene = scene
        view.autoenablesDefaultLighting = false
        view.allowsCameraControl = true
        view.antialiasingMode = .multisampling4X
        if let camera = scene.rootNode.childNode(withName: BookPreview3DBuilder.cameraName, recursively: true) {
            view.pointOfView = camera
        }
        context.coordinator.lastResetToken = resetToken
        applyCanvasBackground(to: view)
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        if view.scene !== scene {
            view.scene = scene
            if let camera = scene.rootNode.childNode(withName: BookPreview3DBuilder.cameraName, recursively: true) {
                view.pointOfView = camera
            }
        }
        applyCanvasBackground(to: view)
        if context.coordinator.lastResetToken != resetToken {
            context.coordinator.lastResetToken = resetToken
            resetCamera(on: view)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var lastResetToken = 0
    }

    /// Matches the 2D tools' canvas. Dynamic NSColors must be resolved for SceneKit,
    /// which otherwise snapshots them in whatever appearance is current at render time.
    private func applyCanvasBackground(to view: SCNView) {
        var resolved = NSColor.black
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            resolved = ArtisanTheme.canvasNSColor.usingColorSpace(.deviceRGB) ?? .black
        }
        view.backgroundColor = resolved
        view.scene?.background.contents = resolved
    }

    private func resetCamera(on view: SCNView) {
        guard let scene = view.scene,
              let camera = scene.rootNode.childNode(withName: BookPreview3DBuilder.cameraName, recursively: true),
              let book = scene.rootNode.childNode(withName: BookPreview3DBuilder.bookRootName, recursively: true)
        else { return }
        camera.removeFromParentNode()
        // Rebuild default camera relative to current book.
        let size = max(
            abs(Float(book.boundingBox.max.x - book.boundingBox.min.x)),
            abs(Float(book.boundingBox.max.y - book.boundingBox.min.y)),
            abs(Float(book.boundingBox.max.z - book.boundingBox.min.z))
        )
        let distance = max(18, size * 2.8)
        let node = SCNNode()
        node.name = BookPreview3DBuilder.cameraName
        let cam = SCNCamera()
        cam.fieldOfView = 40
        cam.zNear = 0.1
        cam.zFar = 200
        node.camera = cam
        node.position = SCNVector3(distance * 0.55, distance * 0.35, distance)
        node.look(at: book.worldPosition)
        scene.rootNode.addChildNode(node)
        view.pointOfView = node
    }
}
