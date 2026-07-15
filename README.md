# BookBind

Native macOS app for hobby binders and small presses. Assemble a full book from PDFs (covers, inserts, extras), add endpapers, number pages, and impose folio signatures for section-sewn or saddle-stitch binding — all on-device.

## Information architecture

**Global sidebar** (quick work, always available):

| Destination | Role |
|---|---|
| **Home** | Dashboard of masterworks |
| **Calculators** | Spine width, GSM ↔ bond, creep hints |
| **Libraries** | Local asset folders for PDFs and artwork, plus cloud connection placeholders |
| **Settings** | Defaults and preferences |
| **Support** | Orientation and binding guides |
| **Quick Actions** | Jump straight into imposition, cover, or materials — saves a single-purpose project with only that tool unlocked |

**Project workbench** (inside an open masterwork):

| Tool | Role |
|---|---|
| **Imposition** | Sources, signatures, creep, bind, export |
| **Cover** | SVG cover & spine editor — boards, grooves, foil / deboss stamps |
| **Materials** | Inventory notes for that book |

**New Masterwork** unlocks all three tools. Quick Actions create a saved scratch project (e.g. `Signature A1B2`) with only the started tool available — the others stay grayed out until you click one and confirm creating that section. Calculators stay global for one-off measurements.

## Project workflow

1. **New Masterwork** with title / trim / architecture — or a **Quick Action** for a single tool
2. In **Imposition** — drop PDFs, configure, **Bind**, **Export PDF** (when that tool is unlocked)
3. On a full masterwork, switch to **Cover** / **Materials**; Quick Action projects stay scoped to their tool
4. Use **Calculators** anytime for one-off measurements
5. Use **Libraries** to keep reusable PDFs, scans, and artwork linked outside a single masterwork
6. Rename the scratch project anytime from the sidebar

## Roadmap

Binding stays the core job. Page tools are **in scope** so binders can build the full book block before impose — not as a generic PDF Swiss Army knife.

### Book assembly (next)

| Capability | Why |
|---|---|
| **Organize** | Thumbnail grid: reorder, delete, rotate pages across sources |
| **Insert / add pages** | Blank pages, covers, and extra PDFs at any position in the book |
| **Split / extract** | Pull chapters or ranges out of a large PDF into the book (or aside) |
| **Covers** | Front/back cover slots (separate from blank endpapers) |
| **Watermark / page numbers** | Standalone on the assembled book block, then bind |

Flow becomes: **assemble book block → decorate → impose → export**.

### Binding quality (also planned)

- Decorative endpapers polish (solid color swatches, multi-page PDF cycling UI)
- Job / project persistence across launches

### Later

- EPUB → print-ready PDF
- Direct print / booklet dialog

### Done recently

- App shell: global nav vs project workbench (Imposition / Cover / Materials)
- Standalone Calculators (spine, GSM, creep)
- Creep compensation for thick signatures
- Orientation normalize for mixed landscape/portrait
- Bleed margin + custom trim sizes + crop marks
- Decorative endpapers from image or PDF
- Vector-preferring impose (`CGPDFPage`, raster fallback)
- Imposition summary panel (pages, signatures, sheet size, print sheets)

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
  Theme/           Artisan surface + typography tokens
  Models/          Binding job, plan, paper sizes, projects
  Services/        Merge, decorate, impose, binding math
  ViewModels/      App store + per-project binding workspace
  Views/
    Home/          Dashboard + New Masterwork
    Calculators/   Global quick tools
    Settings/      Preferences + support copy
    Workbench/     Project: Imposition, Cover, Materials
BookBindTests/     Imposition + math tests
```

## Privacy

Everything runs on your Mac. No accounts, no uploads, no network requirement for binding.
