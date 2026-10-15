import CoreGraphics
import Foundation

/// Axis-aligned element frame used by shared alignment / grouping math.
struct DesignFrame: Equatable, Identifiable {
    var id: UUID
    var xMM: Double
    var yMM: Double
    var widthMM: Double
    var heightMM: Double
    var rotationDegrees: Double
    var groupID: UUID?

    var minX: Double { xMM }
    var maxX: Double { xMM + widthMM }
    var minY: Double { yMM }
    var maxY: Double { yMM + heightMM }
    var midX: Double { xMM + widthMM * 0.5 }
    var midY: Double { yMM + heightMM * 0.5 }

    var bounds: CGRect {
        CGRect(x: xMM, y: yMM, width: max(0.1, widthMM), height: max(0.1, heightMM))
    }

    mutating func translate(dx: Double, dy: Double) {
        xMM += dx
        yMM += dy
    }
}

enum DesignAlignEdge: String, CaseIterable, Identifiable {
    case left, centerX, right, top, centerY, bottom
    var id: String { rawValue }

    var title: String {
        switch self {
        case .left: return "Align Left"
        case .centerX: return "Align Horizontal Centers"
        case .right: return "Align Right"
        case .top: return "Align Top"
        case .centerY: return "Align Vertical Centers"
        case .bottom: return "Align Bottom"
        }
    }
}

enum DesignDistributeAxis: String, CaseIterable, Identifiable {
    case horizontal, vertical
    var id: String { rawValue }
    var title: String {
        switch self {
        case .horizontal: return "Distribute Horizontally"
        case .vertical: return "Distribute Vertically"
        }
    }
}

/// Pure geometry helpers for multi-select, grouping, and alignment.
enum DesignEditorMath {
    /// Union bounds of frames (axis-aligned).
    static func selectionBounds(_ frames: [DesignFrame]) -> CGRect? {
        guard let first = frames.first else { return nil }
        return frames.dropFirst().reduce(first.bounds) { $0.union($1.bounds) }
    }

    /// Align frames to the selection union (or optional artboard).
    static func align(
        _ frames: [DesignFrame],
        edge: DesignAlignEdge,
        toArtboard artboard: CGRect? = nil
    ) -> [DesignFrame] {
        guard frames.count >= 2 || artboard != nil else { return frames }
        let reference = artboard ?? selectionBounds(frames) ?? .zero
        return frames.map { frame in
            var next = frame
            switch edge {
            case .left:
                next.xMM = reference.minX
            case .centerX:
                next.xMM = reference.midX - frame.widthMM * 0.5
            case .right:
                next.xMM = reference.maxX - frame.widthMM
            case .top:
                next.yMM = reference.minY
            case .centerY:
                next.yMM = reference.midY - frame.heightMM * 0.5
            case .bottom:
                next.yMM = reference.maxY - frame.heightMM
            }
            return next
        }
    }

    /// Evenly distribute frames along an axis (requires 3+).
    static func distribute(_ frames: [DesignFrame], axis: DesignDistributeAxis) -> [DesignFrame] {
        guard frames.count >= 3 else { return frames }
        switch axis {
        case .horizontal:
            let sorted = frames.sorted { $0.midX < $1.midX }
            guard let first = sorted.first, let last = sorted.last else { return frames }
            let span = last.midX - first.midX
            guard span > 0.01 else { return frames }
            let step = span / Double(sorted.count - 1)
            var result: [UUID: DesignFrame] = Dictionary(uniqueKeysWithValues: frames.map { ($0.id, $0) })
            for (i, frame) in sorted.enumerated() {
                var next = frame
                let targetMid = first.midX + step * Double(i)
                next.xMM = targetMid - frame.widthMM * 0.5
                result[frame.id] = next
            }
            return frames.compactMap { result[$0.id] }
        case .vertical:
            let sorted = frames.sorted { $0.midY < $1.midY }
            guard let first = sorted.first, let last = sorted.last else { return frames }
            let span = last.midY - first.midY
            guard span > 0.01 else { return frames }
            let step = span / Double(sorted.count - 1)
            var result: [UUID: DesignFrame] = Dictionary(uniqueKeysWithValues: frames.map { ($0.id, $0) })
            for (i, frame) in sorted.enumerated() {
                var next = frame
                let targetMid = first.midY + step * Double(i)
                next.yMM = targetMid - frame.heightMM * 0.5
                result[frame.id] = next
            }
            return frames.compactMap { result[$0.id] }
        }
    }

    /// Assign a shared group ID to frames (creates one if needed).
    static func group(_ frames: [DesignFrame], groupID: UUID = UUID()) -> [DesignFrame] {
        guard frames.count >= 2 else { return frames }
        return frames.map { frame in
            var next = frame
            next.groupID = groupID
            return next
        }
    }

    /// Clear group membership.
    static func ungroup(_ frames: [DesignFrame]) -> [DesignFrame] {
        frames.map { frame in
            var next = frame
            next.groupID = nil
            return next
        }
    }

    /// Translate all frames by the same delta.
    static func translate(_ frames: [DesignFrame], dx: Double, dy: Double) -> [DesignFrame] {
        frames.map { frame in
            var next = frame
            next.translate(dx: dx, dy: dy)
            return next
        }
    }

    /// Expand selection to include every element sharing a group ID with any selected id.
    static func expandSelection(
        selectedIDs: Set<UUID>,
        frames: [DesignFrame]
    ) -> Set<UUID> {
        var result = selectedIDs
        let groupIDs = Set(frames.filter { selectedIDs.contains($0.id) }.compactMap(\.groupID))
        guard !groupIDs.isEmpty else { return result }
        for frame in frames where frame.groupID.map(groupIDs.contains) == true {
            result.insert(frame.id)
        }
        return result
    }
}

extension CoverDesignElement {
    /// Board-space top-left frame for shared editor math.
    func designFrame(geometry: CoverBlueprintService.Geometry) -> DesignFrame {
        let bounds = CoverEditorMath.displayBounds(for: self, geometry: geometry)
        return DesignFrame(
            id: id,
            xMM: bounds.centerX - bounds.width * 0.5,
            yMM: bounds.centerY - bounds.height * 0.5,
            widthMM: bounds.width,
            heightMM: bounds.height,
            rotationDegrees: rotationDegrees,
            groupID: groupID
        )
    }
}

extension DesignElement {
    var designFrame: DesignFrame {
        DesignFrame(
            id: id,
            xMM: xMM,
            yMM: yMM,
            widthMM: widthMM,
            heightMM: heightMM,
            rotationDegrees: rotationDegrees,
            groupID: groupID
        )
    }
}
