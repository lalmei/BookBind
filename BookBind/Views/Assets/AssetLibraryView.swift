import AppKit
import SwiftUI

/// Contents of one asset library. Laid out like Home: the window title and subtitle name the
/// library and its folder; the page holds a section label and a grid of cards.
struct AssetLibraryView: View {
    let library: AssetLibrary
    let isAvailable: Bool
    let items: [AssetLibraryItem]

    private let columns = [
        GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 14, alignment: .top)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if library.isCloudStub {
                    ContentSectionTitle("Connection")
                    AssetLibraryStateView(
                        title: "Cloud libraries are coming",
                        systemImage: library.kind.systemImage(isAvailable: true),
                        message: "\(library.name) will appear here once cloud connections are supported. Local folders work today — add one with + next to Libraries."
                    )
                } else if !isAvailable {
                    ContentSectionTitle("Assets")
                    AssetLibraryStateView(
                        title: "Library unavailable",
                        systemImage: "folder.badge.questionmark",
                        message: "InABind can't read this folder right now. Remove it and add it again from the sidebar to refresh access."
                    )
                } else if items.isEmpty {
                    ContentSectionTitle("Assets")
                    AssetLibraryStateView(
                        title: "No assets yet",
                        systemImage: "photo.on.rectangle.angled",
                        message: "Drop PDFs or images into this folder, then reselect the library to refresh."
                    )
                } else {
                    ContentSectionTitle(items.count == 1 ? "1 Asset" : "\(items.count) Assets")
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                        ForEach(items) { item in
                            AssetLibraryItemCard(item: item)
                        }
                    }
                }
            }
            .padding(.horizontal, ArtisanTheme.marginDesktop)
            .padding(.vertical, 32)
            .frame(maxWidth: 1500, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(ArtisanTheme.contentBackground)
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if let url = localURL {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                } label: {
                    Label("Show in Finder", systemImage: "folder")
                }
                .disabled(localURL == nil || !isAvailable)
                .help("Show this library's folder in Finder")
            }
        }
    }

    private var subtitle: String {
        if library.isCloudStub {
            return "Not connected"
        }
        guard let pathHint = library.pathHint else {
            return isAvailable ? "Local folder" : "Permission needed"
        }
        return NSString(string: pathHint).abbreviatingWithTildeInPath
    }

    private var localURL: URL? {
        guard !library.isCloudStub, let pathHint = library.pathHint else { return nil }
        return URL(fileURLWithPath: NSString(string: pathHint).expandingTildeInPath)
    }
}

private extension AssetLibraryKind {
    func systemImage(isAvailable: Bool) -> String {
        switch self {
        case .localFolder:
            return isAvailable ? "folder" : "folder.badge.questionmark"
        case .cloudStub(let provider):
            return provider.systemImage
        }
    }
}

/// Empty / unavailable message in a Home-style card.
private struct AssetLibraryStateView: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(ArtisanTheme.textSecondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ArtisanTheme.textPrimary)
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(ArtisanTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: 560, alignment: .leading)
        .background(ArtisanTheme.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(ArtisanTheme.separator.opacity(0.45), lineWidth: 1)
        }
    }
}

/// One file: preview well, name, and kind — same card metrics as Home's project cards.
private struct AssetLibraryItemCard: View {
    let item: AssetLibraryItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(ArtisanTheme.canvasBackground)
                Image(systemName: item.kind == .pdf ? "doc.richtext" : "photo")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(ArtisanTheme.textSecondary)
            }
            .frame(height: 104)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ArtisanTheme.textPrimary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                Text(item.kind == .pdf ? "PDF" : "IMAGE")
                    .font(ArtisanTheme.labelFont)
                    .foregroundStyle(ArtisanTheme.textSecondary.opacity(0.55))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ArtisanTheme.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(ArtisanTheme.separator.opacity(0.45), lineWidth: 1)
        }
        .help(item.url.path)
    }
}

#Preview {
    AssetLibraryView(
        library: AssetLibrary(
            name: "InABind Assets",
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
