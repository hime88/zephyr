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
| `dxf-goldens [dir]` | Compares every `*.dxf` in `dir` (default `Tools/bench/golden`) against its `*.digest.txt`. Exits non-zero on any mismatch. CI runs this. |
| `dxf-goldens-write [dir]` | **Re-blesses** the golden files from the current parser. Only run this after inspecting the diff — it is the "accept new behaviour" button. |

## The borrow-accessor benchmark

```bash
swiftc -O -parse-as-library -swift-version 6 borrow-accessors.swift -o borrow-accessors && ./borrow-accessors
```

Results and the assembly-level explanation live in `plans/swift-6.4-baseline.md`. Headline: `mutate` on a
single-element write into 8 KB of inline storage is ~197× faster than the `get`+`set` round trip
(0.92 ns vs 181 ns); `borrow` on `Array` only removes a retain/release.

## Adding a golden fixture

1. Drop a `something.dxf` into `golden/`.
2. `ZephyrBench dxf-goldens-write Tools/bench/golden`.
3. Read the generated `something.digest.txt` and confirm it describes what you expect.
4. `ZephyrBench dxf-goldens Tools/bench/golden` → `all N matched`.

Note the digest deliberately excludes entity UUIDs (handles are generated per import) so it is stable
across runs; it covers layer names/colors/line weights, block names and geometry, entity kind, layer,
block, transform and a structural hash of the geometry.
