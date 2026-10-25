# ZephyrKernel Integration — Performance & Memory Guided Plan

## 1. Context

Proposal under review: extract a zero-dependency `ZephyrKernel` target (`Primitives2D`, `CurveEval`,
`Intersector2D`, `Projector2D`, `Offset2D`) + `CADEntityKernelBridge`, then rewire
`TrimGeometryEngine`, `OffsetGeometryEngine`/`FilletChamferCommands`, `CADSnapEngine`, and
`ZephyrLisp` (`inters`, `vla-IntersectWith`, `vlax-curve-getClosestPointTo`) onto it.

Goals: exact bulge math ($b = \tan(\Delta/4)$), one canonical tolerance + solver, no chord
tessellation for trim/offset/fillet.

**This plan is a performance/memory-gated revision of that proposal.** The geometry is sound;
the risk is where and how often it runs. Snap runs per mouse-move, trim/offset run on large
polylines, and several proposed snippets allocate per entity-pair per query.

Toolchain reality (from repo): `Package.swift` is `swift-tools-version: 6.2`, build must go
through `compile.ps1` (VS Native Tools for Swift Clang importer on Win ARM64). The proposal
assumes 6.4. That mismatch must be resolved first — it affects `@frozen`, `Sendable`, and
`static let` isolation behavior.

## 2. Branch

All work happens on its own branch, cut from `main` before any kernel work:

```powershell
# from C:/dev/as-built (repo root)
git checkout main; git pull; git checkout -b feature/zephyr-kernel-single-shot
git push -u origin feature/zephyr-kernel-single-shot
```

Rules for this branch: single-shot landing (per user decision) — kernel target + bridge +
all rewires (snap, trim, offset/fillet, Lisp) in one PR-sized change, revisions after review.
No commits to `main` until `ZephyrBench` goldens + kernel benches pass on the branch.
`compile.ps1` already assumes the Swift 6.4 toolchain (swiftbuild default handling), so the
`swift-tools-version: 6.4` bump is consistent — no 6.2 backport path.

## 3. Approach (single-shot on a feature branch — user decision)

User decisions locked: **6.4 approved, full kernel (spline/ellipse/ray/xline included), absolute precision preserved, single-shot rollout with revisions after, own branch (`feature/zephyr-kernel-single-shot`).**

Single-shot means: one branch lands kernel + bridge + all rewires together. The perf/memory safeguards in §3 are *pre-merge gates on the branch*, not separate landings. If any gate fails, fix on the branch — do not partially merge.

1. **Prove no-regression on paper first** — baseline benchmarks (10k smooth / 50k acceptable-entity snap bench) + absolute-precision fuzz at state-plane magnitudes before rewiring callers.
2. **Land full kernel on the branch, additive first** — new target including spline (via `NURBSEvaluator` subdivision/evaluate, not a reimplementation), ellipse (analytic), ray/xline; no callers rewired until kernel-only tests + benches pass (bulge round-trip, line-line/line-arc/arc-arc fuzz vs. `CADGeometryMath` / `CADPolyline.arcParameters`).
3. **Rewire all hot paths on the same branch in dependency order, single merge** —
   snap (highest frequency, broadphase preserved), then trim, then offset/fillet, then Lisp.
   Each must pass `ZephyrBench` gates before the branch is submitted; post-review revisions allowed.
4. **No silent drops** — the current engines handle transforms/splines/ellipses/rays (via `explode` + `NURBSEvaluator`); the kernel as proposed returns `[]`/`nil` for them. Full-kernel scope means the branch ships no rewire that silently drops them (see R6).

What we are explicitly NOT doing yet: pooling/UnsafeBuffer optimization, SIMD, or replacing
`CADVertexBufferBuilder` (Float conversion stays at render upload — already correct).

## 4. Performance & memory risks found in the proposal

| # | Risk | Where | Why it matters |
|---|------|-------|----------------|
| R1 | `findKernelIntersections` snippet is O(C²) per cursor move | `CADSnapEngine.swift` (~Tier 1–3, `worldBoundingBox` broadphase + `spatialGrid`) | Current snap is O(candidates) with cached AABB reject of 99%+. Pairwise `i×j × curvesA×curvesB` intersect per mouse-move will jank on 10k-entity drawings. Must keep AABB/broadphase-first, intersect-only-candidates-near-cursor. |
| R2 | `toKernelCurves()` / `toKernelSegments()` allocate per query | Bridge, snap Tier 3, trim `collectIntersectionParams` | Per-frame `[Curve2d]` + `[PolySegment2d]` arrays (each wrapping enums + widths) = ARC traffic + heap allocs on the mouse path. Need lazy/single-segment extraction or stack-resident value path. |
| R3 | Single absolute tolerance `linear = 1e-9` at large coordinates | `KernelTolerance` | At ~2.4e6, 1 ULP ≈ 4.7e-10 so 1e-9 ≈ 2 ULP — solver discriminants cancel. User requires ABSOLUTE precision (no relative loosening), so the fix is **local-frame shifting** (solve relative to segment-midpoint/arc-center, add back after) + compensated discriminant, keeping 1e-9 absolute semantics. Gate: zero-miss fuzz at `(2_450_192.8475, 1_948_271.1250)`. |
| R4 | Enum-heavy value copies (`Curve2d`, `PolySegment2d.Geometry`) + synthesized `Hashable/Codable` | `Primitives2D.swift` | `@frozen + Hashable + Codable` on every hot type bloats conformance code and copies whole payloads per call. `Codable` is unneeded on the hot path; `Hashable` only if used as dict keys. Split: hot math types minimal, persistence Codable elsewhere. |
| R5 | `offsetPolylineSegments` stitch loop is O(n²) intersects + mutates `result` while iterating joints | `Offset2D.swift` §7 | OFFSET of a 5k-vertex polyline does ~5k analytical intersects even for rectangles. Needs AABB precheck per joint + fast path for line-line joints (current `OffsetGeometryEngine` already has corner logic — reuse, don't duplicate). |
| R6 | Trim rewrite drops `entity.transform`, `TrimCriterion` fence/rect, spline/ellipse/ray handling | `TrimGeometryEngine.explode` (caps: 4096 segs, `segmentsPerRadian:48`, spline `512–4096`) | Full-kernel scope (user requirement) means the kernel must cover spline (reuse `NURBSEvaluator.evaluate/evaluateAt/subdivide` + existing curve-vs-segment intersection), ellipse (analytic ellipse-line via quadratic, ellipse-ellipse via subdivision fallback), and ray/xline — `intersect` returning `[]`/`nil` for them is a ship-blocker, not a v1 fallback. Transform must be applied (world-space solve, local-space rebuild). |
| R7 | Fillet via double-offset + full intersect is heavier than current corner solver | `Projector2D.filletCurves` vs `FilletChamferCommands.swift` corner math | 2× offset alloc + unbounded `extendA/B:true` intersect + 2× `closestPoint(clamped:false)` per fillet. Fine for single fillet, but must not run per-frame; also `clamped:false` on arcs needs sweep-clamp or tangent points drift. |
| R8 | Duplicate bulge→arc math creates drift risk | `Arc2d.fromBulge` vs `CADPolyline.arcParameters(forSegment:)` (`CADEntity.swift:376`) | Two implementations of $b=\tan(\Delta/4)$ with different guards (`bulgeZero 1e-7` vs `1e-12`, `cotHalf` formulation) will disagree on near-zero bulges. One must delegate to the other (fuzz to prove it). |
| R9 | `swift-tools-version: 6.4` bump | `Package.swift` (currently 6.2), `compile.ps1` | Approved by user. `compile.ps1` already handles the Swift 6.4 swiftbuild default (multi-platform `--build-system native` fallback), so bump is consistent. Still verify clean `compile.ps1` + `compile-macos.sh`/`compile-linux.sh` runs on the branch. |
| R10 | `CurveEval.splitAt` on `.circle` sweep normalization + `isClosedCircle` trim interval wrap | `CurveEval.swift` / trim snippet | `(tB, tA)` wrap interval assumes downstream `fromKernelCurve` handles wrap (it doesn't — produces negative-sweep arc). Needs explicit wrap-split into two arcs. |

## 5. Files to modify (single-shot branch order)

- `Engine/EngineAsBuilt/Package.swift` — add `ZephyrKernel` + `ZephyrKernelTests` (Phase 1 only; no 6.4 bump until toolchain check passes).
- `Engine/EngineAsBuilt/Sources/ZephyrKernel/*.swift` — new, additive only in Phase 1.
- `Engine/EngineAsBuilt/Sources/ZephyrCore/CAD/CADEntityKernelBridge.swift` — new in Phase 2 (behind flag).
- `Engine/EngineAsBuilt/Sources/ZephyrCore/CAD/CADSnapEngine.swift` — Tier 3 narrow-phase only (Phase 3).
- `Engine/EngineAsBuilt/Sources/ZephyrCore/Commands/TrimGeometryEngine.swift` — single-curve path only (Phase 4).
- `Engine/EngineAsBuilt/Sources/ZephyrCore/Commands/OffsetGeometryEngine.swift`, `FilletChamferCommands.swift` — delegate, don't duplicate (Phase 5).
- `Engine/EngineAsBuilt/Sources/ZephyrLisp/LispBuiltinsMath.swift` (`inters`), VLA builtins — last (Phase 6).
- `Engine/EngineAsBuilt/Sources/ZephyrBench/*.swift` — add `kernel` cases first (gates everything).

## 6. Reuse (do not reimplement)

- `CADPolyline.arcParameters(forSegment:)` (`CADEntity.swift:376`) — canonical bulge→arc; kernel must match or delegate.
- `CADPolyline.tessellatedPoints(segmentsPerRadian:)` / `boundingPoints()` (`CADEntity.swift`) — tessellation + quadrant extrema already correct; keep for render/spline paths.
- `TrimGeometryEngine.explode` caps (`curvedSegmentCount`, 4096 max, spline `NURBSEvaluator.evaluateByKnotSpans`) — keep as fallback for spline/ellipse until kernel covers them.
- `CADGeometryMath` (`segmentSegmentIntersection`, `nearestPointOnArc/Circle`, `circleThroughThreePoints`, `angleIsOnCCWSweep`) — differential-test kernel against these, then delegate.
- `SnapEngine` Tier 1 AABB (`worldBoundingBox.expanded(by:)`, `CADEntity.swift:1062` cached field) + `CADEntitySpatialIndex` grid + per-entity `spatialGrid.candidateIndices` — kernel must sit *inside* Tier 3, never replace Tier 1.
- `OffsetGeometryEngine.isOffsettable`, `OffsetGapType` (`.extend/.filleted/.chamfered`), `OffsetSettings`, width-scale in `CADPolyline.transformed(by:)` — proposal renames cases (`.fillet/.chamfer`) and drops width handling; keep existing names/semantics.
- `ZephyrBench` harness (`measure best-of-N` + `peakResidentBytes`, golden gates, `canary`) — extend with kernel cases; this is the perf/memory verdict mechanism.
- `CADVertexBufferBuilder.TessInput` — Float conversion stays at upload; out of scope.

## 7. Steps (single merge gate, implemented in this order on the branch)

- [x] **Step 0 — Branch + toolchain + baseline.** Cut `feature/zephyr-kernel-single-shot` from `main`. Bump to 6.4, verify `compile.ps1` (Win ARM64) + macOS/Linux scripts. Run `ZephyrBench` (`dxf`, `nurbs`, goldens) release, save numbers as the regression floor.
- [x] **Step 1 — Absolute-precision solver design.** Keep `linear=1e-9` absolute; implement local-frame shifting in `Intersector2D` (all three solvers) + compensated discriminant. Fuzz line-line/line-arc/arc-arc at state-plane coords `(2_450_192.8475, 1_948_271.1250)`; require zero misses vs. current math. Add spline/ellipse/ray/xline kernel coverage reusing `NURBSEvaluator` (subdivide/evaluate/intersect) + analytic ellipse-line.
- [x] **Step 2 — Full `ZephyrKernel` on the branch (no callers yet).** Add target + tests: line/arc/circle/polyline-segment + spline/ellipse/ray/xline. Slim hot types: drop `Codable` from hot path unless persistence needs it. `Arc2d.fromBulge` must fuzz-match `arcParameters(forSegment:)` (bulge round-trip ≤ 1e-12, near-zero-bulge agreement).
- [x] **Step 3 — Bench on the branch (merge gate).** Add `ZephyrBench kernel` cases: bulge round-trip 100k segs, line-arc batch, arc-arc batch, spline-intersect batch, ellipse batch, polyline-offset 5k verts, **synthetic 10k/50k-entity snap query** (Tier 1 + Tier 3); report ms + peak RSS. Budgets: snap Tier 3 ≤ 2 ms p95 @10k entities, trim/offset ≤ current `explode` path.
- [x] **Step 4 — Snap (narrow-phase only, Tier 1 preserved).** Route `.nearest/.perpendicular/.tangent` Tier 3 through `Projector2D` (line/arc/circle/polyline-segment + spline/ellipse via `NURBSEvaluator`); keep Tier 1 AABB + anchor priority + transforms (`localCursor` → solve → world map). Forbid pairwise entity×entity intersects on the cursor path. Verify 10k-entity bench ≤ 2 ms p95.
- [x] **Step 5 — Trim (all curve types, full kernel).** Rewire `.line/.arc/.circle` + polyline-bulge + spline/ellipse/ray targets to `Intersector2D + CurveEval.splitAt` with transform applied (no `explode` fallback — full kernel ships). Fix circle-wrap split (two arcs, not negative sweep) and the proposal snippet's polyline `isClosed:false` bug; extract only clicked segment + neighbors (not whole-polyline `flatMap` per cutter). Fuzz width interpolation across splits.
- [ ] **Step 6 — Offset/fillet delegate + Lisp + cleanup.** Route `OffsetGeometryEngine` line/arc/polyline paths to `Offset2D` (keep spline/ellipse→spline fitting + `isOffsettable` + `OffsetGapType` names); add joint AABB precheck + line-line fast path. Route fillet line-line first, arc cases after (verify over-offset / zero-radius `nil` semantics). Then wire `inters` / `vla-IntersectWith` / `vlax-curve-getClosestPointTo`, remove duplicated math (kernel or `CADGeometryMath`, not both), resolve `KernelTolerance` isolation + `CurveEval` cleanups, run full goldens + bench, submit.

## 8. Verification

- `compile.ps1` (Windows ARM64, VS Native Tools context) — never raw `swift build`.
- `swift run -c release ZephyrBench kernel` — new cases report ms + peak RSS; must be ≤ Step-0 baseline budgets.
- `swift run -c release ZephyrBench dxf-goldens <dir>` + `eab-roundtrip` / `shx-render` gates — no digest changes.
- Targeted fuzz: bulge round-trip (`|arc.bulge − bulge| ≤ 1e-12`), tangent/secant line-arc + arc-arc at state-plane coords, circle-wrap trim → two valid arcs, polyline width interpolation.
- Manual: snap sweep over dense drawing (no jank), trim/fillet/offset on bulged polyline + spline + ellipse (no silent no-ops).

## 9. Resolved decisions (user-confirmed)

1. **Toolchain: 6.4 approved.** Bump on the branch; verify `compile.ps1` + macOS/Linux scripts.
2. **Scope: full kernel.** Spline (reuse `NURBSEvaluator`), ellipse, ray/xline all in-kernel — no fallback shipping.
3. **Tolerance: absolute precision preserved.** Keep `linear = 1e-9`; large-coordinate robustness via local-frame shifting + compensated discriminant.
4. **Snap budget (recommended): 10k smooth (≤ 2 ms p95 Tier 3), 50k acceptable** — enforced by new `ZephyrBench kernel-snap` case.
5. **Rollout: single-shot on `feature/zephyr-kernel-single-shot`**, revisions after review.

