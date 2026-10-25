import Foundation
import ZephyrCore
import ZephyrKernel

// =========================================================================
// MARK: - ZephyrKernel perf gates (PLAN-kernel-perf.md Step 3)
//
// Merge-gate bench cases for the kernel branch. Each reports wall time +
// peak RSS via the shared `measure` harness. Budgets:
//   * snap Tier 3 <= 2 ms p95 @10k entities (synthetic grid drawing)
//   * trim/offset kernel paths <= current explode-based equivalents
// Run: swift run -c release ZephyrBench kernel

extension Cases {
    /// Differential gate: kernel solvers must agree with the legacy
    /// ZephyrCore math they replace. Any mismatch is fatal (merge gate).
    static func kernelAgreementGate() {
        var checked = 0
        func agree(_ a: Double, _ b: Double, _ tol: Double, _ what: String) {
            checked += 1
            if abs(a - b) > tol { fatalError("kernel agreement FAILED: \(what) \(a) vs \(b)") }
        }
        // Line-line vs CADGeometryMath.segmentSegmentIntersection.
        for i in 0..<500 {
            let f = Double(i) * 0.37
            let a0 = Vector3(x: f, y: sin(f) * 10, z: 0)
            let a1 = Vector3(x: f + 20, y: cos(f) * 10, z: 0)
            let b0 = Vector3(x: f + 5, y: -30, z: 0)
            let b1 = Vector3(x: f + 5, y: 30, z: 0)
            let legacy = CADGeometryMath.segmentSegmentIntersection(a: a0, b: a1, c: b0, d: b1)
            let kern = Intersector2D.intersectLineLine(
                LineSeg2d(start: a0.point2d, end: a1.point2d),
                LineSeg2d(start: b0.point2d, end: b1.point2d),
                extendA: false, extendB: false)
            switch (legacy, kern.first) {
            case (nil, nil): break
            case (let l?, let k?):
                agree(l.t, k.paramA, 1e-9, "line-line t")
                agree(l.point.x, k.point.x, 1e-9, "line-line x")
            default:
                fatalError("kernel agreement FAILED: line-line hit mismatch")
            }
        }
        // Line-arc vs the legacy segment-circle quadratic (independent
        // reference: same closed form TrimGeometryEngine used pre-kernel).
        func legacySegmentCircle(_ a: Vector3, _ b: Vector3, c: Vector3, r: Double) -> [Vector3] {
            let dx = b.x - a.x, dy = b.y - a.y
            let fx = a.x - c.x, fy = a.y - c.y
            let qa = dx * dx + dy * dy
            let qb = 2.0 * (fx * dx + fy * dy)
            let qc = fx * fx + fy * fy - r * r
            let disc = qb * qb - 4.0 * qa * qc
            if disc < 0 { return [] }
            let sq = sqrt(disc)
            let t1 = (-qb - sq) / (2.0 * qa), t2 = (-qb + sq) / (2.0 * qa)
            var out: [Vector3] = []
            if t1 >= -1e-9 && t1 <= 1.0 + 1e-9 {
                out.append(Vector3(x: a.x + t1 * dx, y: a.y + t1 * dy, z: a.z))
            }
            if t2 >= -1e-9 && t2 <= 1.0 + 1e-9 && abs(t2 - t1) > 1e-12 {
                out.append(Vector3(x: a.x + t2 * dx, y: a.y + t2 * dy, z: a.z))
            }
            return out
        }
        for i in 0..<500 {
            let f = Double(i) * 1.13
            let c = Vector3(x: f, y: f * 0.5, z: 0)
            let legacy = legacySegmentCircle(
                Vector3(x: f - 20, y: f * 0.5 + 3, z: 0),
                Vector3(x: f + 20, y: f * 0.5 + 3, z: 0),
                c: c, r: 10)
            let kern = Intersector2D.intersectLineArc(
                LineSeg2d(start: Point2d(x: f - 20, y: f * 0.5 + 3),
                            end: Point2d(x: f + 20, y: f * 0.5 + 3)),
                Arc2d(center: c.point2d, radius: 10, startAngle: 0, sweep: 2.0 * .pi),
                extendLine: true, extendArc: false)
            guard legacy.count == kern.count else {
                fatalError("kernel agreement FAILED: line-circle count \(legacy.count) vs \(kern.count)")
            }
            for (l, k) in zip(legacy.sorted { $0.x < $1.x }, kern.sorted { $0.point.x < $1.point.x }) {
                agree(l.x, k.point.x, 1e-9, "line-circle x")
                agree(l.y, k.point.y, 1e-9, "line-circle y")
            }
        }
        // Spline: kernel De Boor vs NURBSEvaluator at 200 params.
        let cps3 = (0..<8).map { Vector3(x: Double($0) * 3, y: sin(Double($0)) * 4, z: 0) }
        let knots3 = [0, 0, 0, 0.2, 0.35, 0.5, 0.65, 0.8, 1, 1, 1]
        let kern3 = Spline2d(controlPoints: cps3.map { $0.point2d }, knots: knots3, degree: 2)
        for i in 0...200 {
            let u = Double(i) / 200.0
            let ref = NURBSEvaluator.evaluateAt(degree: 2, knots: knots3, controlPoints: cps3,
                                                weights: nil, at: u)
            let got = SplineEval.evaluate(kern3, at: u)
            switch (ref, got) {
            case (let r?, let g?):
                agree(r.x, g.x, 1e-9, "spline x")
                agree(r.y, g.y, 1e-9, "spline y")
            default:
                fatalError("kernel agreement FAILED: spline eval nil mismatch")
            }
        }
        // Arc bulge: kernel fromBulge vs CADPolyline.arcParameters.
        for i in 0..<200 {
            let b = 0.02 + Double(i) * 0.01
            let p0 = Vector3(x: Double(i), y: 0, z: 0)
            let p1 = Vector3(x: Double(i) + 10, y: 5, z: 0)
            let pl = CADPolyline(points: [p0, p1])
            var pv = pl
            pv.vertices[0].bulge = b
            guard let ref = pv.arcParameters(forSegment: 0),
                  let got = Arc2d.fromBulge(start: p0.point2d, end: p1.point2d, bulge: b) else {
                fatalError("kernel agreement FAILED: bulge nil")
            }
            agree(ref.center.x, got.center.x, 1e-9, "bulge cx")
            agree(ref.center.y, got.center.y, 1e-9, "bulge cy")
            agree(ref.radius, got.radius, 1e-9, "bulge r")
            agree(ref.sweep, got.sweep, 1e-12, "bulge sweep")
        }
        print("kernel agreement gate: \(checked) comparisons passed")
        _ = checked
    }

    static func kernel() {
        print("Kernel: Double-precision 2D solvers (ZephyrKernel)")
        kernelAgreementGate()

        // 1. Bulge round-trip, 100k segments.
        measure("kernel bulge round-trip 100k") {
            var sink = 0.0
            for i in 0..<100_000 {
                let s = Point2d(x: Double(i) * 0.37, y: Double(i) * 0.11)
                let e = Point2d(x: s.x + 10.0, y: s.y + 3.0)
                let b = 0.05 + Double(i % 17) * 0.03
                if let arc = Arc2d.fromBulge(start: s, end: e, bulge: b) {
                    sink += arc.bulge + arc.radius
                }
            }
            if sink == 0 { fatalError("no arcs produced") }
        }

        // 2. Line-arc batch, 20k secant intersects at state-plane coords.
        measure("kernel line-arc 20k (state-plane)") {
            let ox = 2_450_192.8475, oy = 1_948_271.1250
            var hits = 0
            for i in 0..<20_000 {
                let cy = oy + Double(i % 401) - 200.0
                let arc = Arc2d(center: Point2d(x: ox, y: cy), radius: 100,
                                startAngle: 0, sweep: 2.0 * .pi)
                let line = LineSeg2d(start: Point2d(x: ox - 150, y: cy),
                                     end: Point2d(x: ox + 150, y: cy))
                hits += Intersector2D.intersectLineArc(line, arc, extendLine: false, extendArc: false).count
            }
            if hits != 40_000 { fatalError("expected 40000 hits, got \(hits)") }
        }

        // 3. Arc-arc batch, 20k.
        measure("kernel arc-arc 20k") {
            var hits = 0
            for i in 0..<20_000 {
                let off = Double(i % 97) * 0.5
                let a = Arc2d(center: Point2d(x: off, y: 0), radius: 5, startAngle: 0, sweep: 2.0 * .pi)
                let b = Arc2d(center: Point2d(x: off + 6, y: 0), radius: 5, startAngle: 0, sweep: 2.0 * .pi)
                hits += Intersector2D.intersectArcArc(a, b, extendA: false, extendB: false).count
            }
            if hits != 40_000 { fatalError("expected 40000 hits, got \(hits)") }
        }

        // 4. Spline-intersect batch, 2k line-vs-quadratic.
        measure("kernel line-spline 2k") {
            let s = Spline2d(controlPoints: [.zero, Point2d(x: 5, y: 10), Point2d(x: 10, y: 0)],
                             knots: [0, 0, 0, 1, 1, 1], degree: 2)
            var hits = 0
            for i in 0..<2_000 {
                let y = 5.0 + Double(i % 11) * 0.01
                let line = LineSeg2d(start: Point2d(x: -5, y: y), end: Point2d(x: 15, y: y))
                hits += Intersector2D.intersect(.line(line), .spline(s)).count
            }
            if hits == 0 { fatalError("no spline hits") }
        }

        // 5. Ellipse batch, 20k line-ellipse.
        measure("kernel line-ellipse 20k") {
            var hits = 0
            for i in 0..<20_000 {
                let cx = Double(i % 251) * 0.25
                let e = Ellipse2d(center: Point2d(x: cx, y: 0),
                                  majorAxis: Vec2d(x: 10, y: 0), minorRatio: 0.5)
                let line = LineSeg2d(start: Point2d(x: cx - 15, y: 0), end: Point2d(x: cx + 15, y: 0))
                hits += Intersector2D.intersect(.line(line), .ellipse(e)).count
            }
            if hits != 40_000 { fatalError("expected 40000 hits, got \(hits)") }
        }

        // 6. Polyline offset, 5k-vertex closed zigzag.
        measure("kernel offset 5k-vertex polyline") {
            var segs: [PolySegment2d] = []
            segs.reserveCapacity(5_000)
            for i in 0..<5_000 {
                let x0 = Double(i), y0 = Double((i % 2)) * 2.0
                let x1 = Double(i + 1), y1 = Double(((i + 1) % 2)) * 2.0
                segs.append(PolySegment2d(index: i, start: Point2d(x: x0, y: y0),
                                          end: Point2d(x: x1, y: y1), bulge: 0))
            }
            guard let out = Offset2D.offsetPolylineSegments(segs, isClosed: false, signedDistance: 1.0) else {
                fatalError("offset failed")
            }
            if out.isEmpty { fatalError("empty offset result") }
        }

        // 7. Synthetic snap queries: 10k and 50k entity grids, cursor parked
        // near one entity. Exercises Tier 1 AABB reject + Tier 3 on-curve.
        for count in [10_000, 50_000] {
            let layer = UUID()
            var entities: [CADEntity] = []
            entities.reserveCapacity(count)
            let cols = 100
            for i in 0..<count {
                let gx = Double(i % cols) * 50.0
                let gy = Double(i / cols) * 50.0
                let prim: CADPrimitive = (i % 5 == 0)
                    ? .circle(center: Vector3(x: gx, y: gy, z: 0), radius: 5)
                    : .line(start: Vector3(x: gx, y: gy, z: 0),
                            end: Vector3(x: gx + 20, y: gy + 5, z: 0))
                entities.append(CADEntity(layerID: layer, localGeometry: [prim]))
            }
            let engine = SnapEngine(threshold: 5.0)
            // Cursor near entity #4242's neighborhood.
            let qx = Double(4242 % cols) * 50.0 + 10.0
            let qy = Double(4242 / cols) * 50.0 + 2.0
            measure("kernel snap query \(count) entities", repeats: 5) {
                var found = 0
                for k in 0..<20 {
                    let r = engine.nearestSnap(
                        worldX: qx + Double(k) * 0.01, worldY: qy,
                        entities: entities, extensionSnapEnabled: false)
                    if r != nil { found += 1 }
                }
                if found != 20 { fatalError("snap missed (\(found)/20)") }
            }
        }
    }
}
