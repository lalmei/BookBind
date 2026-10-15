import AppKit
import SceneKit

/// Builds and drives a hinged book `SCNScene` for the Preview workbench.
enum BookPreview3DBuilder {
    static let bookRootName = "bookRoot"
    static let frontHingeName = "frontHinge"
    static let backHingeName = "backHinge"
    static let frontBoardName = "frontBoard"
    static let backBoardName = "backBoard"
    static let textBlockName = "textBlock"
    static let spineName = "spine"
    static let cameraName = "previewCamera"

    /// Max open rotation (radians) from closed.
    static let maxOpenRadians: Float = 2.8 // ~160°

    struct SceneBundle {
        let scene: SCNScene
        let bookRoot: SCNNode
        let frontHinge: SCNNode
        let backHinge: SCNNode
    }

    static func makeScene(
        dimensions: PhysicalBookDimensions,
        textures: BookPreviewTextures,
        openAmount: Float = 0
    ) -> SceneBundle {
        let scene = SCNScene()
        // Background is applied by the host view so it tracks the app's canvas color.

        let root = SCNNode()
        root.name = bookRootName
        scene.rootNode.addChildNode(root)

        let w = dimensions.boardWidthScene
        let h = dimensions.boardHeightScene
        let boardT = dimensions.boardThicknessScene
        let blockT = dimensions.textBlockThicknessScene
        let mid = max(dimensions.midsectionScene, 0.05)
        let closedDepth = blockT + boardT * 2

        // Text block: ±Z faces carry flyleaf endpapers so an open book doesn’t
        // show a blank paper face beside the marbled pastedown.
        let block = makeBox(
            width: w * 0.97,
            height: h * 0.97,
            length: max(0.08, blockT),
            name: textBlockName
        )
        applyTextBlockMaterials(
            to: block,
            frontFlyleaf: textures.frontFlyleaf,
            backFlyleaf: textures.backFlyleaf
        )
        root.addChildNode(block)

        // Spine wrap on the left (−X).
        let spine = makeBox(width: mid, height: h, length: closedDepth * 0.95, name: spineName)
        applyMaterial(textures.spineOuter, to: spine)
        spine.position = SCNVector3(-w / 2 - mid / 2, 0, 0)
        root.addChildNode(spine)

        let frontHinge = SCNNode()
        frontHinge.name = frontHingeName
        frontHinge.position = SCNVector3(-w / 2, 0, blockT / 2 + boardT / 2)
        root.addChildNode(frontHinge)

        let frontBoard = makeBox(width: w, height: h, length: boardT, name: frontBoardName)
        applyBoardMaterials(
            outer: textures.frontOuter,
            inner: textures.frontInner,
            edge: NSColor(calibratedWhite: 0.72, alpha: 1),
            to: frontBoard,
            isFront: true
        )
        frontBoard.position = SCNVector3(w / 2, 0, 0)
        frontHinge.addChildNode(frontBoard)

        let backHinge = SCNNode()
        backHinge.name = backHingeName
        backHinge.position = SCNVector3(-w / 2, 0, -(blockT / 2 + boardT / 2))
        root.addChildNode(backHinge)

        let backBoard = makeBox(width: w, height: h, length: boardT, name: backBoardName)
        applyBoardMaterials(
            outer: textures.backOuter,
            inner: textures.backInner,
            edge: NSColor(calibratedWhite: 0.72, alpha: 1),
            to: backBoard,
            isFront: false
        )
        backBoard.position = SCNVector3(w / 2, 0, 0)
        backHinge.addChildNode(backBoard)

        applyOpenAmount(openAmount, frontHinge: frontHinge, backHinge: backHinge)
        addLighting(to: scene)
        addCamera(to: scene, lookingAt: root, bookSize: max(w, h, closedDepth))

        return SceneBundle(scene: scene, bookRoot: root, frontHinge: frontHinge, backHinge: backHinge)
    }

    /// `amount` in 0…1 (0 = closed, 1 = fully open).
    static func applyOpenAmount(_ amount: Float, frontHinge: SCNNode, backHinge: SCNNode) {
        let t = min(1, max(0, amount))
        let angle = t * maxOpenRadians
        frontHinge.eulerAngles = SCNVector3(0, -angle, 0)
        backHinge.eulerAngles = SCNVector3(0, angle, 0)
    }

    static func applyOpenAmount(_ amount: Float, in scene: SCNScene) {
        guard let front = scene.rootNode.childNode(withName: frontHingeName, recursively: true),
              let back = scene.rootNode.childNode(withName: backHingeName, recursively: true) else {
            return
        }
        applyOpenAmount(amount, frontHinge: front, backHinge: back)
    }

    // MARK: - Geometry helpers

    private static func makeBox(width: Float, height: Float, length: Float, name: String) -> SCNNode {
        let box = SCNBox(
            width: CGFloat(width),
            height: CGFloat(height),
            length: CGFloat(length),
            chamferRadius: 0
        )
        let node = SCNNode(geometry: box)
        node.name = name
        return node
    }

    private static func applyMaterial(_ image: NSImage, to node: SCNNode) {
        guard let box = node.geometry as? SCNBox else { return }
        let mat = texturedMaterial(image)
        box.materials = Array(repeating: mat, count: 6)
    }

    /// SCNBox face order: front(+Z), right(+X), back(−Z), left(−X), top(+Y), bottom(−Y).
    private static func applyBoardMaterials(
        outer: NSImage,
        inner: NSImage,
        edge: NSColor,
        to node: SCNNode,
        isFront: Bool
    ) {
        guard let box = node.geometry as? SCNBox else { return }
        let outerMat = texturedMaterial(outer)
        let innerMat = texturedMaterial(inner)
        let edgeMat = solidMaterial(edge)

        // Front board: outer on +Z, inner on −Z.
        // Back board: outer on −Z, inner on +Z.
        if isFront {
            box.materials = [outerMat, edgeMat, innerMat, edgeMat, edgeMat, edgeMat]
        } else {
            box.materials = [innerMat, edgeMat, outerMat, edgeMat, edgeMat, edgeMat]
        }
    }

    private static func applyTextBlockMaterials(
        to node: SCNNode,
        frontFlyleaf: NSImage,
        backFlyleaf: NSImage
    ) {
        guard let box = node.geometry as? SCNBox else { return }
        let frontMat = texturedMaterial(frontFlyleaf)
        let backMat = texturedMaterial(backFlyleaf)
        let edge = solidMaterial(NSColor(calibratedRed: 0.90, green: 0.88, blue: 0.82, alpha: 1))
        let foreEdge = solidMaterial(NSColor(calibratedRed: 0.86, green: 0.84, blue: 0.78, alpha: 1))
        // +Z faces the front cover (front flyleaf); −Z faces the back cover.
        box.materials = [frontMat, foreEdge, backMat, edge, edge, edge]
    }

    private static func texturedMaterial(_ image: NSImage) -> SCNMaterial {
        let mat = SCNMaterial()
        if let cg = cgImage(from: image) {
            mat.diffuse.contents = cg
        } else {
            mat.diffuse.contents = image
        }
        mat.diffuse.wrapS = .clamp
        mat.diffuse.wrapT = .clamp
        // Avoid mip-smear turning marble into a flat wash on thin/oblique faces.
        mat.diffuse.mipFilter = .linear
        mat.diffuse.minificationFilter = .linear
        mat.diffuse.magnificationFilter = .linear
        mat.lightingModel = .lambert
        mat.locksAmbientWithDiffuse = true
        mat.isDoubleSided = false
        return mat
    }

    private static func solidMaterial(_ color: NSColor) -> SCNMaterial {
        let mat = SCNMaterial()
        mat.diffuse.contents = color
        mat.lightingModel = .lambert
        mat.locksAmbientWithDiffuse = true
        return mat
    }

    private static func cgImage(from image: NSImage) -> CGImage? {
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
            ?? image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    private static func addLighting(to scene: SCNScene) {
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 520
        ambient.light?.color = NSColor(calibratedWhite: 0.92, alpha: 1)
        scene.rootNode.addChildNode(ambient)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 750
        key.light?.castsShadow = true
        key.eulerAngles = SCNVector3(-0.7, 0.6, 0)
        scene.rootNode.addChildNode(key)

        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .directional
        fill.light?.intensity = 380
        fill.eulerAngles = SCNVector3(-0.2, -0.9, 0.1)
        scene.rootNode.addChildNode(fill)
    }

    private static func addCamera(to scene: SCNScene, lookingAt target: SCNNode, bookSize: Float) {
        let camera = SCNCamera()
        camera.fieldOfView = 40
        camera.zNear = 0.1
        camera.zFar = 200
        let node = SCNNode()
        node.name = cameraName
        node.camera = camera
        let distance = max(18, bookSize * 2.8)
        node.position = SCNVector3(distance * 0.55, distance * 0.35, distance)
        node.look(at: target.worldPosition)
        scene.rootNode.addChildNode(node)
    }
}
