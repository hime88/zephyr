# Changelog

Monthly digest condensed from the git history. Instead of per-release notes, all changes are grouped by calendar month and summarized by topic under **Features**, **Bug Fixes**, and **Performance**.

> Generated from 297 commits (2026-06-23 → 2026-10-22).

## October 2026

109 commits · 2026-10-08 – 2026-10-22

### Features
- AutoLISP support: native engine (FDScript merge), full dispatch, file picker, persistent session, `c:` command dispatch, and examples
- Scripted CAD commands with multi-call support
- AUTOCONTRAST command and TrueColor contrast toggle
- Gradient hatches via -HATCH, GF* system variables, and `entmake`; island detection in the Hatch UI
- Layer property sorting
- UNDO/REDO registered as commands with ribbon buttons
- INSERT, DWG/DXF external references (xrefs), and ATTACH media references
- DXF MLINE support; DXF entity handles preserved in xdata
- AutoCAD-style OFFSET command
- Properties panel: multi-select entity picker, copy support, and empty state
- Multi-window tab management: tab reorder, float/dock OS windows, split panes, independent model views, per-window status bars, ImGui contexts, and radial nav
- Linux support with Snap, AppImage, and Flatpak packaging (x64 and ARM64)
- Catppuccin themes and dropdown/slider contrast; Hatch and PenStroke UI theming
- Improved TRIM command
- Swift 6.4 migration; SDL3 3.4.18 and SDL3_image 3.4.8
- macOS Universal binary and bundled Swift runtime
- Website and docs: Linux support, AutoLISP, OFFSET, corrected downloads, roadmap

### Bug Fixes
- SHX shape fonts: fractional arcs, clockwise octant arcs, multi-stroke outline behavior, and hole nudging
- Exploding rectangles and compound entities into separate elements
- Angled gradient hatch projection
- Concurrent CADDocument access crash prevention
- AutoLISP: Enter handling, CRLF comments, stuck "Lisp running" prompt, and load failures
- Hatch editing undo/redo history registration
- Float-window input dead zones, pane divider drag, click-to-raise, and white flash on view swap
- Enter-to-finish in LINE and Polyline; command bar and autocomplete always render on top
- ODA download 404 and teardown hardening; first-run setup popup
- Windows builds missing DLLs; engine init crash; `igInputText` warnings
- Swift 6.4/macOS build fixes (reverted APIs requiring macOS 26/27, header-only shim targets, zlib-ng)
- CI fixes across Windows, macOS, and Linux; DXC pinned for glibc 2.35 compatibility; REFPATHTYPE 0/2 mapping

### Performance
- DXF import: 1.99 s → 0.91 s (per-entity string format hoisting, byte-scanning of group pairs, skipping code-page conversion)
- NURBS: single scratch buffer per evaluation instead of three arrays
- EAB/SHX single byte helper with safe loads, gated by golden digests
- Performance harness and baseline for the Swift 6.4 branch

## September 2026

No commits.

## August 2026

11 commits · 2026-08-02 – 2026-08-12

### Features
- PEN command: freehand drawing, pen erase, and pen splines
- Pen strokes exported to DXF as solid hatches
- REVCLOUD support
- Hatch pattern parsing from `.pat` files
- CLIP command (work in progress)
- DXF writer: hatch export and table support

### Bug Fixes
- Rotated panning in NAV
- DXF hatch export fixes

## July 2026

117 commits · 2026-07-01 – 2026-07-28

### Features
- Native DXF export: writer with layout/output handling, round-trip payload support, and SORTENTSTABLE parsing
- `libdxfrw` replaced with a native Swift DXF reader (iconv removed); Windows code-page encoding/decoding
- Hatch and data tables go native: hatchPath geometry, mirrored hatch handling, data-table import rework and interaction
- Text overhaul: text styles, shape-font parser, encoding, indentation/tab stops, and per-entity style overrides
- ATTDEF and attribute handling improvements
- Leader commands: classic leaders, arrow/block leaders, legacy overrides, PDMODE
- New commands: ARRAY, ALIGN, TORIENT, LENGTHEN, MEASURE/DIVIDE, FILLET, CHAMFER
- DWG converter command and ODA install command
- Native open/save dialogs and drag-and-drop file open
- Ortho axis alignment honors SNAPANG
- User settings and language selection; view background color followed for line/fill colors
- Region support; renderer refresh on open/view switch
- macOS 11 support; SDL/Swift version bumps

### Bug Fixes
- DXF write fixes: arcs, hatches, version on save, layer opacity, linetypes, ellipse hatches
- DXF import fixes: sheets support, parentHandle overwrite, insert transforms, 32-bit floating point precision loss
- Hatch/gradient not persisting on save; scale and rotation not preserved
- Windows release build and compile.ps1 fixes; macOS hotkey vs Windows keymapping
- Crash on minimize; GPU desync crash prevention; memory fixes
- Zoom extents; spline trim at touching line cutters; retraced polyline linetype rendering
- Point/vertex dot rendering too large; anti-aliased line thickness; line width handling at zoom
- Hatch rendering around dimensional text; hatch/dimension orientation
- Window focus issue; libdwg linking; macOS build actions in CI

### Performance
- Reduced texture atlas memory
- Big-O/allocation optimizations in hot paths

## June 2026 — project launch

60 commits · 2026-06-23 – 2026-06-30

### Features
- Initial release: project renamed, GPLv3 license, README with macOS/Windows build downloads
- DWG import/export via LibreDWG, plus a UI scale override
- Initial dimension support (linear, radial, diameter) with presentation and editing
- Complete hatch creation/editing workflow: UI, background fills, gradients, hole detection and preservation, scaling
- NURBS/spline work: knot insertion, 3-degree splines, tessellation quality, and JOIN converting lines & arcs to cubic splines
- Bulge-aware LWPOLYLINE support
- AutoCAD-style direct numeric entry for all drawing commands
- Ortho mode and move-with-distance
- Text alignment/justification and block attributes; block UI improvements
- New commands: UNITS, MATCHPROP, grip-object/grip-max settings
- Improved file browser UI; Windows font registry lookup for font resolution

### Bug Fixes
- Save crash on Windows; macOS x64 build, compile, and startup fixes
- EAB file corruption, ImGui clipper crashes, drag undo, and focus handling
- Line thickness, plot style, and solid fill rendering fixes
- Dashed-line vertex move preview
- Spline trimming inside closed curves
- Copy/paste/drag issues
- Cross-platform `strdup` replacement; LibreDWG CMake wrapped in vcvars context for Windows `cl.exe`

### Performance
- Non-blocking save with progress bar, plus autosave
- ImGui max vertex count raised to 4 billion for very large documents
