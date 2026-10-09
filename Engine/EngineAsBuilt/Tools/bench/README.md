# Zephyr bench harness

Two things live here:

| Path | What it is |
|---|---|
| `borrow-accessors.swift` | Standalone benchmark for Swift 6.4 `get` vs `borrow` vs `mutate`. Compile it directly — no package build needed. |
| `golden/` | DXF fixtures + `*.digest.txt` golden digests used as the parser regression gate. |
| `../../Sources/ZephyrBench` | The in-package executable that runs the canary, the perf baseline, the digest gate and the tokenizer equivalence check. |

## Running the in-package harness

```bash
cd Engine/EngineAsBuilt
swift build -c release
.build/*/release/ZephyrBench <command>       # path is .build/<triple>/release on Windows
```

Commands:

| Command | Purpose |
|---|---|
| `canary` | Compile-time + runtime check of every Swift 6.4 feature this branch relies on. Exits non-zero on failure. Both CI jobs run this. |
| `dxf <file>` | Timings + peak RSS for `DXFReader` and `DXFImporter`. |
| `shx <file>` | Timings for SHX font parse and glyph rendering. |
| `nurbs` | Timings for the NURBS evaluator. |
| `dxf-digest <file>` | Prints a canonical, UUID-free digest of everything the importer produces from a file, plus its hash. |
| `dxf-compare <file>` | Parses the same file with **both** pair parsers (byte scanner and the legacy decode-then-split) and reports whether their pair sequences are identical, with timings. This is the equivalence proof for the Phase 1 tokenizer swap. |
| `dxf-goldens [dir]` | Compares every `*.dxf` in `dir` (default `Tools/bench/golden`) **plus the built-in gates** (`eab-scalars`, `eab-roundtrip`, `shx-render`, `vertex-build`) against their `*.digest.txt`. Exits non-zero on any mismatch. CI runs this. |
| `dxf-goldens-write [dir]` | **Re-blesses** the golden files from the current build. Only run this after inspecting the diff — it is the "accept new behaviour" button. |
| `eab-scalars` | Prints the exact bytes `BinaryWriter` produces for a fixed scalar sequence (byte order / width / reserve-fill pin). |
| `eab-roundtrip` | Serializes a document covering every primitive kind, reads it back, prints a UUID-free digest of the result. |
| `shx-render <font>` | Parses an SHX font and digests the geometry rendered for a fixed string. |

**Digests are identical in debug and release**, so iterate with a debug build (~25 s) and only use
`-c release` when you need the timings.

## The borrow-accessor benchmark

```bash
swiftc -O -parse-as-library -swift-version 6 borrow-accessors.swift -o borrow-accessors && ./borrow-accessors
```

Results and the assembly-level explanation live in `plans/swift-6.4-baseline.md`. Headline: `mutate` on a
single-element write into 8 KB of inline storage is ~197× faster than the `get`+`set` round trip
(0.92 ns vs 181 ns); `borrow` on `Array` only removes a retain/release.

## Golden fixtures and gates

`golden/` holds the DXF fixtures, the SHX font used by the `shx-render` gate, and one `*.digest.txt` per
check. Ten checks run under `dxf-goldens`:

| Gate | What a change in it means |
|---|---|
| 6 × `*.dxf` fixtures | The DXF parser or importer changed its output (LF/CRLF/CR, indented codes, padded values, blank lines, stray code lines). |
| `eab-scalars` | An EAB scalar changed width, byte order, or the reserve/fill patching. |
| `eab-roundtrip` | EAB serialization or deserialization changed what a document round-trips to. |
| `shx-render` | SHX font parsing or glyph rendering changed. |
| `vertex-build` | Vertex tessellation changed (entity-index tagging and batch layout included). |
| `nurbs` | Any NURBS evaluator changed its result (all four public entry points + `findClosestParameter`). |
| `dxf-roundtrip` | DXF **export** changed: each fixture is imported, exported, re-imported and digested. |

## Adding a golden fixture

1. Drop a `something.dxf` into `golden/`.
2. `ZephyrBench dxf-goldens-write Tools/bench/golden`.
3. Read the generated `something.digest.txt` and confirm it describes what you expect.
4. `ZephyrBench dxf-goldens Tools/bench/golden` → `all N matched`.

Note the digest deliberately excludes entity UUIDs (handles are generated per import) so it is stable
across runs; it covers layer names/colors/line weights, block names and geometry, entity kind, layer,
block, transform and a structural hash of the geometry.
