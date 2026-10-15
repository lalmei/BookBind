import CoreGraphics
import Foundation
import ImageIO

/// One thing that would print wrong, or that the binder should know before printing.
struct PreflightIssue: Identifiable, Equatable {
    enum Severity: Int, Comparable {
        case info
        case warning
        case error

        static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// One-click remedy offered next to the issue.
    enum Fix: Equatable {
        case applyCreep(points: Double)
        case enableCropMarks
        case matchCoverToTrim
    }

    let id: String
    let severity: Severity
    let title: String
    let detail: String
    let tool: ProjectTool
    var fix: Fix?

    var fixTitle: String? {
        switch fix {
        case .applyCreep: return "Apply Creep"
        case .enableCropMarks: return "Turn On Marks"
        case .matchCoverToTrim: return "Match Cover"
        case nil: return nil
        }
    }
}

/// Live print checks for a project — what a binder wants to know before committing paper.
///
/// Pure function of its input (plus an injectable image-size lookup) so it can run on every
/// change and in tests. Idea modelled on DesignCraft's live preflight
/// (storytold/designcraft, MIT OR Apache-2.0); the checks here are specific to binding.
enum PreflightService {
    struct Input {
        var project: BinderyProject
        var job: BindingJob
        var sources: [SourceDocument]
        var assembledPageCount: Int
        var plan: BindingPlan?
    }

    /// Pixel size of a raster image, or `nil` when it can't be read.
    typealias ImageSizeLookup = (URL) -> CGSize?
    /// Whether a file can be read.
    typealias FileCheck = (URL) -> Bool

    /// Below this, placed images print visibly soft.
    static let minimumPPI = 150.0
    /// Print-quality target for artwork.
    static let recommendedPPI = 300.0

    static func run(
        _ input: Input,
        imageSize: ImageSizeLookup = PreflightService.imagePixelSize,
        fileExists: FileCheck = PreflightService.fileIsReadable
    ) -> [PreflightIssue] {
        var issues: [PreflightIssue] = []
        let project = input.project
        if project.allows(.imposition) {
            issues += impositionIssues(input, fileExists: fileExists)
        }
        if project.allows(.cover) {
            issues += coverIssues(input, imageSize: imageSize, fileExists: fileExists)
        }
        if project.allows(.endpapers) {
            issues += endpaperIssues(project, imageSize: imageSize, fileExists: fileExists)
        }
        return issues.sorted { lhs, rhs in
            lhs.severity != rhs.severity ? lhs.severity > rhs.severity : lhs.id < rhs.id
        }
    }

    // MARK: - Imposition

    private static func impositionIssues(_ input: Input, fileExists: FileCheck) -> [PreflightIssue] {
        var issues: [PreflightIssue] = []
        let job = input.job

        for source in input.sources where !fileExists(source.resolvedURL()) {
            issues.append(PreflightIssue(
                id: "source-missing-\(source.id)",
                severity: .error,
                title: "Missing source: \(source.name)",
                detail: "The PDF was moved or deleted. Remove it from Sources and add it again.",
                tool: .imposition
            ))
        }

        guard input.assembledPageCount > 0 else {
            issues.append(PreflightIssue(
                id: "no-pages",
                severity: .info,
                title: "No pages yet",
                detail: "Add PDFs or blank pages in Sources to build the book block.",
                tool: .imposition
            ))
            return issues
        }

        if let plan = input.plan, plan.padPages > 0 {
            issues.append(PreflightIssue(
                id: "padding",
                severity: .info,
                title: "\(plan.padPages) blank page\(plan.padPages == 1 ? "" : "s") added",
                detail: "The last \(job.impositionScheme.usesFolioImpose ? "signature" : "sheet") is filled out with blanks at the end of the book.",
                tool: .imposition
            ))
        }

        // Mixed source sizes get scaled to one trim.
        let sizes = input.sources.map(\.pageSize).filter { $0.width > 0 && $0.height > 0 }
        if let first = sizes.first,
           sizes.contains(where: { abs($0.width - first.width) > 2 || abs($0.height - first.height) > 2 }) {
            issues.append(PreflightIssue(
                id: "mixed-sizes",
                severity: .warning,
                title: "Sources have different page sizes",
                detail: "Pages are scaled to one trim size, so some will print larger or smaller than designed.",
                tool: .imposition
            ))
        }

        if let trim = job.resolvedTrimSize, trim.width > 0, trim.height > 0 {
            let trimAspect = trim.width / trim.height
            let offShape = input.sources.filter { source in
                let size = source.pageSize
                guard size.width > 0, size.height > 0 else { return false }
                // Orientation is normalized separately; compare portrait-to-portrait.
                let aspect = min(size.width, size.height) / max(size.width, size.height)
                let target = min(trimAspect, 1 / trimAspect)
                return abs(aspect - target) / target > 0.03
            }
            if !offShape.isEmpty {
                issues.append(PreflightIssue(
                    id: "aspect",
                    severity: .warning,
                    title: "Page shape differs from trim",
                    detail: "\(offShape.map(\.name).joined(separator: ", ")) will be scaled to fit \(mmLabel(trim)), leaving margins.",
                    tool: .imposition
                ))
            }
        }

        if job.impositionScheme.usesFolioImpose, let plan = input.plan {
            let sheets = max(1, plan.pagesPerSignature / 4)
            if sheets >= 4, job.creepPoints <= 0 {
                let suggestion = CalculatorMath.signaturePlan(.init(
                    pageCount: input.assembledPageCount,
                    sheetsPerSignature: sheets,
                    gsm: input.project.textPaperGSM
                ))
                issues.append(PreflightIssue(
                    id: "creep",
                    severity: .warning,
                    title: "No creep on \(plan.pagesPerSignature)-page signatures",
                    detail: String(
                        format: "Inner pages will push out ~%.2f mm at the fore-edge and lose margin when trimmed.",
                        suggestion.creepMM
                    ),
                    tool: .imposition,
                    fix: .applyCreep(points: suggestion.creepPoints)
                ))
            }
        }

        if job.bleedPoints > 0, !job.addCropMarks {
            issues.append(PreflightIssue(
                id: "bleed-no-marks",
                severity: .warning,
                title: "Bleed without crop marks",
                detail: "Artwork runs past the trim but nothing marks where to cut.",
                tool: .imposition,
                fix: .enableCropMarks
            ))
        }
        return issues
    }

    // MARK: - Cover

    private static func coverIssues(_ input: Input, imageSize: ImageSizeLookup, fileExists: FileCheck) -> [PreflightIssue] {
        var issues: [PreflightIssue] = []
        let project = input.project

        for element in project.coverElements where element.kind == .image && element.isVisible {
            let name = element.imageName.isEmpty ? "Cover image" : element.imageName
            guard let url = element.resolvedImageURL(), fileExists(url) else {
                issues.append(PreflightIssue(
                    id: "cover-image-missing-\(element.id)",
                    severity: .error,
                    title: "Missing image: \(name)",
                    detail: "The file was moved or deleted. Replace it from the cover inspector.",
                    tool: .cover
                ))
                continue
            }
            if let issue = resolutionIssue(
                id: "cover-image-ppi-\(element.id)",
                name: name,
                pixels: imageSize(url),
                widthMM: element.widthMM,
                heightMM: element.heightMM,
                tool: .cover
            ) {
                issues.append(issue)
            }
        }

        if project.allows(.imposition), let trim = input.job.resolvedTrimSize {
            let trimW = BindingMath.millimeters(fromPoints: trim.width)
            let trimH = BindingMath.millimeters(fromPoints: trim.height)
            if project.widthMM + 0.5 < trimW || project.heightMM + 0.5 < trimH {
                issues.append(PreflightIssue(
                    id: "cover-smaller-than-block",
                    severity: .warning,
                    title: "Cover is smaller than the book block",
                    detail: String(
                        format: "Cover %.0f × %.0f mm vs imposition trim %.0f × %.0f mm.",
                        project.widthMM, project.heightMM, trimW, trimH
                    ),
                    tool: .cover,
                    fix: .matchCoverToTrim
                ))
            }
        }
        return issues
    }

    // MARK: - Endpapers

    private static func endpaperIssues(_ project: BinderyProject, imageSize: ImageSizeLookup, fileExists: FileCheck) -> [PreflightIssue] {
        var issues: [PreflightIssue] = []
        for (label, face) in [("Front", project.endsheets.front), ("Back", project.endsheets.back)] {
            guard face.mode == .artwork, let artwork = face.artwork else { continue }
            let url = artwork.resolvedURL()
            guard fileExists(url) else {
                issues.append(PreflightIssue(
                    id: "endpaper-missing-\(label)",
                    severity: .error,
                    title: "\(label) endpaper artwork missing",
                    detail: "\(artwork.name) was moved or deleted.",
                    tool: .endpapers
                ))
                continue
            }
            guard !artwork.isPDF else { continue }
            if let issue = resolutionIssue(
                id: "endpaper-ppi-\(label)",
                name: "\(label) endpaper (\(artwork.name))",
                pixels: imageSize(url),
                widthMM: project.widthMM,
                heightMM: project.heightMM,
                tool: .endpapers
            ) {
                issues.append(issue)
            }
        }
        return issues
    }

    // MARK: - Helpers

    /// Effective resolution of an image printed at `widthMM × heightMM`.
    static func effectivePPI(pixels: CGSize, widthMM: Double, heightMM: Double) -> Double? {
        guard pixels.width > 0, pixels.height > 0, widthMM > 0, heightMM > 0 else { return nil }
        return min(Double(pixels.width) / (widthMM / 25.4), Double(pixels.height) / (heightMM / 25.4))
    }

    private static func resolutionIssue(
        id: String,
        name: String,
        pixels: CGSize?,
        widthMM: Double,
        heightMM: Double,
        tool: ProjectTool
    ) -> PreflightIssue? {
        guard let pixels, let ppi = effectivePPI(pixels: pixels, widthMM: widthMM, heightMM: heightMM),
              ppi < recommendedPPI else { return nil }
        let isSoft = ppi < minimumPPI
        return PreflightIssue(
            id: id,
            severity: isSoft ? .error : .warning,
            title: "\(name) is \(Int(ppi.rounded())) ppi",
            detail: isSoft
                ? "It will print visibly soft. Use a larger image or place it smaller."
                : "Fine for proofs; \(Int(recommendedPPI)) ppi or more is crisper for final print.",
            tool: tool
        )
    }

    private static func mmLabel(_ size: CGSize) -> String {
        String(
            format: "%.0f × %.0f mm",
            BindingMath.millimeters(fromPoints: size.width),
            BindingMath.millimeters(fromPoints: size.height)
        )
    }

    // MARK: - Default lookups

    private static let sizeCache = NSCache<NSURL, NSValue>()

    /// Reads only the image header (no full decode), cached per URL.
    static func imagePixelSize(_ url: URL) -> CGSize? {
        if let cached = sizeCache.object(forKey: url as NSURL) {
            return cached.sizeValue
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            return nil
        }
        let size = CGSize(width: width, height: height)
        sizeCache.setObject(NSValue(size: size), forKey: url as NSURL)
        return size
    }

    static func fileIsReadable(_ url: URL) -> Bool {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return FileManager.default.isReadableFile(atPath: url.path)
    }
}
