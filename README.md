# InABind

Native macOS app for hobby binders and small presses. Assemble a full book from PDFs (covers, inserts, extras), add endpapers, number pages, and impose folio signatures — or one-sheet zines and accordion folds — for section-sewn, saddle-stitch, and DIY print layouts, all on-device.

## Information architecture

**Global sidebar** (quick work, always available):

| Destination | Role |
|---|---|
| **Home** | Dashboard of masterworks |
| **Calculators** | Bench calculators with scaled blueprints: **Case & Boards** (board, spine stiffener, covering material + corner cuts), **Signatures** (count, blanks, creep), **Sewing** (station positions, thread length, 1:1 punching-template PDF), **Sheet Yield** (grain-correct folios per parent sheet), **Paper** (GSM ↔ bond, caliper, PPI) |
| **Guides** | Orientation and binding guides |
| **Projects** | Your masterworks; the **+** menu (and File ▸ New Quick Project) starts a single-purpose project — imposition, zine layout, cover, or materials — with only that tool unlocked |
| **Libraries** | Local asset folders for PDFs and artwork, plus cloud connection placeholders |

Defaults and preferences live in **InABind ▸ Settings…** (⌘,).

**Window layout** is the same for every project tool: project title (click to rename) on the left of the toolbar, tool switcher centered, that tool's actions plus the inspector toggle (⌥⌘I) on the right.

**Project workbench** (inside an open masterwork):

| Tool | Role |
|---|---|
| **Imposition** | Sources, signatures / zine & fold layouts, creep, bind, export |
| **Cover** | SVG cover & spine editor — boards, grooves, turn-in cut/fold marks, foil / deboss stamps |
| **Endpapers** | Folded endsheet artboard — pastedown, flyleaf, flat-sheet export; **Marble editor** (Marblizer-class tools + Swift recipes) |
| **Preview** | Interactive 3D book — cover art, spine proportions, open/close hinges |
| **Materials** | Inventory notes for that book |

Imposition’s **Open Endpapers** jumps to the endsheet artboard. From Endpapers (or a marbled cover fill), **Marble editor** opens an interactive composition surface: ink drop, spatter, line/wavy/circular tines, vortex, undo/redo, force-field overlay, PNG export, and Swift recipe generators (Tutorial, Concentric circles, style presets). Print/export still embeds regeneratable raster marbling in SVG.

**New Masterwork** unlocks all workbench tools. Quick Actions create a saved scratch project (e.g. `Signature A1B2`) with only the started tool available — the others stay grayed out until you click one and confirm creating that section. Calculators stay global for one-off measurements.

## Project workflow

1. **New Masterwork** with title / trim / architecture — or a **Quick Action** for a single tool
2. In **Imposition** — drop PDFs and configure; the imposed preview re-binds automatically as you edit, then **Export PDF** (when that tool is unlocked)
3. On a full masterwork, switch to **Cover** / **Endpapers** / **Preview** / **Materials**; Quick Action projects stay scoped to their tool
4. Use **Calculators** anytime for one-off measurements
5. Use **Libraries** to keep reusable PDFs, scans, and artwork linked outside a single masterwork
6. Rename the scratch project anytime from the sidebar
7. Open **Preview** to orbit and open/close a 3D mockup of the assembled book

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

- Job / project persistence across launches

### Later

- EPUB → print-ready PDF
- Direct print / booklet dialog

### Done recently

- Measurement fields accept any unit and arithmetic (`6in`, `152mm`, `1p6`, `210-6`, `50%`); Settings ▸ Units picks mm or inches for display
- Printer's marks: crop marks outside the bleed, bleed marks, spine fold marks, and a slug line naming each sheet (title · signature · sheet front/back · pages · date)
- Live preflight in the project toolbar: missing files, low-resolution art, mixed page sizes, missing creep, bleed without marks — with one-click fixes
- Swatch palette in every colour well, with Adobe Swatch Exchange (`.ase`) import/export
- Imposition re-binds automatically as you edit; Export waits for a current preview

- Zine & fold layouts: half-fold booklet, 8-page mini-zine (folds + center cut), 16-page mini-zine, accordion panels — plus a **Zine Layout** quick action
- Cover turn-in allowance: extra covering material around the boards with fold + 45° miter cut marks on the canvas and PDF/SVG blueprints; pastedown insets to reveal the turn-in border in the 3D preview
- Interactive 3D book Preview tab (SceneKit): cover wrap textures, endpaper peeks, open/close hinges
- App shell: global nav vs project workbench (Imposition / Cover / Endpapers / Preview / Materials)
- Standalone Calculators (spine, GSM, creep)
- Creep compensation for thick signatures
- Orientation normalize for mixed landscape/portrait
- Bleed margin + custom trim sizes + crop marks
- Decorative endpapers from image or PDF
- Procedural marbled endpapers (seedable styles: Stone, Nonpareil, Peacock, Combed)
- Interactive Marble editor (Marblizer tools, undo/redo, Swift recipes, PNG export)
- Cover editor: illustration-style stroke dash/gap, fill paint, shape tools, duplicate in toolbar
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

### Cover production geometry (assumptions)

There is no single universal case-binding convention. InABind uses these defaults (all overridable in the Cover inspector):

| Concept | Default / rule |
|---|---|
| **Board-space** | Origin at top-left of the back board; panels = back · joint · spine · joint · front |
| **Material-space** | Origin at top-left of the covering-material sheet; board origin = `(turnIn, turnIn)` |
| **Turn-in** | 15 mm casebound / section-sewn, 12 mm coptic, 0 for soft wraps; only when `architecture.wrapsTurnIn` |
| **Spine midsection** | From BindingMath (text block + boards + hinges); spine face = midsection − 2·hinge |
| **Corner cuts** | Default **miter** (45°); also square butt, rounded, or custom (miter fallback) |
| **Relief cuts** | Optional short slits near hinges on head/tail turn-ins (off by default) |
| **Bleed** | Outer allowance beyond the material cut edge (default 0); distinct from turn-in |
| **Safe area** | Reference inset from board edges (default 5 mm); not a cut |
| **Guides** | Production marks live in separate SVG groups (`data-production-guide`); **Clean artwork SVG** omits them entirely |

Cover and Endpapers share the same design-document model (layers, shapes, fill/stroke including regeneratable marbled paper, multi-select, group, align). Marbling stores either parametric style settings or an editable operation history from the Marble editor.

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

## Acknowledgements

Measurement-field parsing, printer's marks, live preflight, and `.ase` swatch exchange are independent Swift implementations of approaches from [DesignCraft](https://github.com/storytold/designcraft) (MIT OR Apache-2.0).
