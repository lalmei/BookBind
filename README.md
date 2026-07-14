# BookBind

Native macOS app for hobby binders and small presses. Merge PDFs, add endpapers, number pages, and impose folio signatures for section-sewn or saddle-stitch binding — all on-device.

## One-shot workflow

1. Drop one or more PDFs (order = book order)
2. Choose binding style, signature size, endpapers, page numbers / watermark
3. **Bind** — merges, pads blanks, decorates, imposes printer spreads
4. **Export PDF** — 2-up sheets ready to print, fold, and sew

## Requirements

- macOS 13+
- [Xcode](https://developer.apple.com/xcode/) 15+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Build & run

```bash
cd BookBind
xcodegen generate
open BookBind.xcodeproj
```

In Xcode: select the **BookBind** scheme → **My Mac** → Run (⌘R).

## Binding notes

| Style | Behavior |
|---|---|
| **Section-sewn** | Multiple signatures of 4–32 pages (folio). Pads the last signature with blanks. |
| **Saddle-stitch** | One nested signature for the whole book. Pads to a multiple of 4. |

Output pages are **printer spreads** (left \| right on a landscape sheet) in sheet order: front, back, front, back… Fold each sheet, nest within a signature, sew or stitch.

EPUB support is paused for a later release.

## Project layout

```
BookBind/
  Models/          Binding job, plan, paper sizes
  Services/        Merge, decorate, impose
  ViewModels/      One-shot workspace
  Views/           SwiftUI + PDFKit preview
BookBindTests/     Imposition math tests
```

## Privacy

Everything runs on your Mac. No accounts, no uploads, no network requirement for binding.
