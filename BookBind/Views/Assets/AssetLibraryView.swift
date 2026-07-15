import AppKit
import SwiftUI

struct AssetLibraryView: View {
    let library: AssetLibrary
    let isAvailable: Bool
    let items: [AssetLibraryItem]

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 14)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                if library.isCloudStub {
                    cloudPlaceholder
                } else if !isAvailable {
                    unavailableState
                } else if items.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                        ForEach(items) { item in
                            AssetLibraryItemCard(item: item)
                        }
                    }
                }
            }
            .padding(36)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(ArtisanTheme.surfaceBright)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(library.name)
                    .font(ArtisanTheme.displayFontCompact)
            } icon: {
                Image(systemName: systemImage)
                    .foregroundStyle(ArtisanTheme.primary)
            }
            .foregroundStyle(ArtisanTheme.primary)

            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private var cloudPlaceholder: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cloud libraries are planned.")
                .font(ArtisanTheme.sectionFont)
                .foregroundStyle(ArtisanTheme.primary)
            Text("This connection point is here so BookBind can grow into iCloud Drive, Dropbox, and similar libraries without changing the sidebar model.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 520, alignment: .leading)
            Button("Connect Coming Soon") {}
                .buttonStyle(.borderedProminent)
                .disabled(true)
        }
        .padding(24)
        .background(ArtisanTheme.surfaceContainerLowest, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(ArtisanTheme.outlineVariant, lineWidth: 1)
        }
    }

    private var unavailableState: some View {
        AssetLibraryStateView(
            title: "Library unavailable",
            systemImage: "folder.badge.questionmark",
            message: "BookBind cannot currently read this folder. Re-add it from the sidebar to refresh its permission."
        )
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            AssetLibraryStateView(
                title: "No assets yet",
                systemImage: "photo.on.rectangle.angled",
                message: "Drop PDFs or images into this folder, then reselect the library to refresh the view."
            )
            if let url = localURL {
                Button("Open in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: 520, alignment: .leading)
    }

    private var subtitle: String {
        if library.isCloudStub {
            return library.pathHint ?? "Cloud connection"
        }
        if let pathHint = library.pathHint {
            return pathHint
        }
        return isAvailable ? "Local asset folder" : "Permission needed"
    }

    private var systemImage: String {
        switch library.kind {
        case .localFolder:
            return isAvailable ? "folder" : "folder.badge.questionmark"
        case .cloudStub(let provider):
            return provider.systemImage
        }
    }

    private var localURL: URL? {
        guard let pathHint = library.pathHint else { return nil }
        return URL(fileURLWithPath: NSString(string: pathHint).expandingTildeInPath)
    }
}

private struct AssetLibraryStateView: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)
            Text(title)
                .font(ArtisanTheme.sectionFont)
                .foregroundStyle(ArtisanTheme.primary)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .padding(28)
        .frame(maxWidth: 520)
        .background(ArtisanTheme.surfaceContainerLowest, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(ArtisanTheme.outlineVariant, lineWidth: 1)
        }
    }
}

private struct AssetLibraryItemCard: View {
    let item: AssetLibraryItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(ArtisanTheme.surfaceContainerLow)
                Image(systemName: item.kind == .pdf ? "doc.richtext" : "photo")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(ArtisanTheme.primary)
            }
            .frame(height: 112)

            Text(item.name)
                .font(.callout.weight(.semibold))
                .foregroundStyle(ArtisanTheme.onSurface)
                .lineLimit(2)

            Text(item.kind == .pdf ? "PDF" : "Image")
                .font(ArtisanTheme.technicalCaption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(ArtisanTheme.surfaceContainerLowest, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(ArtisanTheme.outlineVariant.opacity(0.7), lineWidth: 1)
        }
    }
}

#Preview {
    AssetLibraryView(
        library: AssetLibrary(
            name: "BookBind Assets",
            pathHint: "~/Library/Application Support/BookBind/Assets",
            isAutoLinked: true
        ),
        isAvailable: true,
        items: [
            AssetLibraryItem(url: URL(fileURLWithPath: "/tmp/endpaper.png"), name: "endpaper.png", kind: .image),
            AssetLibraryItem(url: URL(fileURLWithPath: "/tmp/cover.pdf"), name: "cover.pdf", kind: .pdf)
        ]
    )
    .frame(width: 900, height: 600)
}
