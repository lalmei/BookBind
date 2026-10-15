import Foundation

/// Aggregated physical book proportions for 3D preview (millimeters).
/// Source of truth remains `CoverBlueprintService.Geometry` + `BindingMath`.
struct PhysicalBookDimensions: Equatable {
    let boardWidthMM: Double
    let boardHeightMM: Double
    let boardThicknessMM: Double
    let hingeMM: Double
    let spineFaceMM: Double
    let midsectionMM: Double
    let textBlockThicknessMM: Double
    let spineWidthMM: Double
    let pageCount: Int
    let gsm: Double
    let architecture: BindingArchitecture

    /// SceneKit-friendly scale: 1 unit = 1 cm.
    var sceneScale: Float { 0.1 }

    var boardWidthScene: Float { Float(boardWidthMM) * sceneScale }
    var boardHeightScene: Float { Float(boardHeightMM) * sceneScale }
    var boardThicknessScene: Float { Float(effectiveBoardThicknessMM) * sceneScale }
    var hingeScene: Float { Float(hingeMM) * sceneScale }
    var spineFaceScene: Float { Float(spineFaceMM) * sceneScale }
    var midsectionScene: Float { Float(midsectionMM) * sceneScale }
    var textBlockThicknessScene: Float { Float(max(1.5, textBlockThicknessMM)) * sceneScale }

    /// Architecture-adjusted board thickness for the mockup silhouette.
    var effectiveBoardThicknessMM: Double {
        switch architecture {
        case .caseBound, .sectionSewn:
            return max(1.5, boardThicknessMM)
        case .perfectBound:
            return max(1.0, boardThicknessMM * 0.85)
        case .coptic:
            return max(0.8, boardThicknessMM * 0.55)
        case .saddleStitch:
            return max(0.6, boardThicknessMM * 0.4)
        }
    }

    /// Closed book depth: text block + both boards.
    var closedDepthMM: Double {
        max(1.5, textBlockThicknessMM) + (effectiveBoardThicknessMM * 2)
    }

    var closedDepthScene: Float { Float(closedDepthMM) * sceneScale }

    static func resolving(
        project: BinderyProject,
        assembledPageCount: Int = 0
    ) -> PhysicalBookDimensions {
        let pageCount = assembledPageCount > 0
            ? assembledPageCount
            : max(0, project.estimatedPageCount)
        let gsm = max(1, project.textPaperGSM)
        let spineWidth = project.effectiveSpineWidthMM(pageCount: pageCount)
        let geo = CoverBlueprintService.Geometry(project: project, spineWidthMM: spineWidth)
        let block = BindingMath.textBlockThicknessMM(pageCount: pageCount, gsm: gsm)

        return PhysicalBookDimensions(
            boardWidthMM: geo.boardW,
            boardHeightMM: geo.boardH,
            boardThicknessMM: max(0.5, project.boardThicknessMM),
            hingeMM: geo.hinge,
            spineFaceMM: geo.spineFace,
            midsectionMM: geo.midsection,
            textBlockThicknessMM: block,
            spineWidthMM: spineWidth,
            pageCount: pageCount,
            gsm: gsm,
            architecture: project.architecture
        )
    }
}
