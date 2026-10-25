import Foundation

// =========================================================================
// MARK: - CurveEval
//
// Normalized parametric evaluation: every bounded curve is P(t), t in [0,1].
// Trim/extend/fillet reduce to splitting or extending [0, 1].
// Spline parameter mapping is affine over the knot domain; ellipse uses
// normalized (sweep-aware) parameter.

public enum CurveEval: Sendable {

    // MARK: - Point evaluation

    /// World-space point P(t); t in [0, 1] for bounded curves (values
    /// outside [0, 1] extend line/ray/xline naturally).
    public static func pointAt(_ curve: Curve2d, t: Double) -> Point2d {
        switch curve {
        case .line(let seg):
            return Point2d(
                x: seg.start.x + (seg.end.x - seg.start.x) * t,
                y: seg.start.y + (seg.end.y - seg.start.y) * t
            )
        case .ray(let r):
            return r.origin + (r.direction * t)
        case .xline(let xl):
            return xl.origin + (xl.direction * t)
        case .arc(let arc):
            let angle = arc.startAngle + arc.sweep * t
            return Point2d(
                x: arc.center.x + arc.radius * cos(angle),
                y: arc.center.y + arc.radius * sin(angle)
            )
        case .circle(let circle):
            let angle = 2.0 * .pi * t
            return Point2d(
                x: circle.center.x + circle.radius * cos(angle),
                y: circle.center.y + circle.radius * sin(angle)
            )
        case .ellipse(let e):
            let angle = e.startAngle + e.sweep * t
            let c = cos(angle), s = sin(angle)
            let minor = e.minorAxis
            return Point2d(
                x: e.center.x + e.majorAxis.x * c + minor.x * s,
                y: e.center.y + e.majorAxis.y * c + minor.y * s)
        case .spline(let spline):
            guard let (u0, u1) = SplineEval.domain(of: spline) else { return .zero }
            return SplineEval.evaluate(spline, at: u0 + (u1 - u0) * t) ?? .zero
        case .polySegment(let seg):
            switch seg.geometry {
            case .line(let l): return pointAt(.line(l), t: t)
            case .arc(let a): return pointAt(.arc(a), t: t)
            }
        }
    }

    // MARK: - Tangents

    /// Unit tangent vector at parameter t.
    public static func tangentAt(_ curve: Curve2d, t: Double) -> Vec2d {
        switch curve {
        case .line(let seg):
            return seg.direction
        case .ray(let r):
            return r.direction
        case .xline(let xl):
            return xl.direction
        case .arc(let arc):
            let angle = arc.startAngle + arc.sweep * t
            let sign = arc.sweep >= 0 ? 1.0 : -1.0
            return Vec2d(x: -sin(angle) * sign, y: cos(angle) * sign)
        case .circle:
            let angle = 2.0 * .pi * t
            return Vec2d(x: -sin(angle), y: cos(angle))
        case .ellipse(let e):
            let angle = e.startAngle + e.sweep * t
            let sign = e.sweep >= 0 ? 1.0 : -1.0
            let minor = e.minorAxis
            let d = Vec2d(
                x: -e.majorAxis.x * sin(angle) + minor.x * cos(angle),
                y: -e.majorAxis.y * sin(angle) + minor.y * cos(angle))
            let n = d.normalized
            return n * sign
        case .spline(let spline):
            guard let (u0, u1) = SplineEval.domain(of: spline) else { return Vec2d() }
            let span = u1 - u0
            guard span > 1e-12 else { return Vec2d() }
            let h = min(1e-4, span * 1e-3)
            let uc = u0 + span * min(max(t, 0.0), 1.0)
            let pA = SplineEval.evaluate(spline, at: max(u0, uc - h)) ?? .zero
            let pB = SplineEval.evaluate(spline, at: min(u1, uc + h)) ?? .zero
            return (pB - pA).normalized
        case .polySegment(let seg):
            switch seg.geometry {
            case .line(let l): return tangentAt(.line(l), t: t)
            case .arc(let a): return tangentAt(.arc(a), t: t)
            }
        }
    }

    // MARK: - Inverse parameter

    /// Normalized parameter t for a point on (or near) the curve.
    /// For bounded curves, t in [0, 1] means the point lies on the span.
    public static func paramAtPoint(_ curve: Curve2d, point: Point2d) -> Double {
        switch curve {
        case .line(let seg):
            let v = seg.end - seg.start
            let lenSq = v.lengthSquared
            guard lenSq > KernelTolerance.linear else { return 0.0 }
            return (point - seg.start).dot(v) / lenSq

        case .ray(let r):
            return (point - r.origin).dot(r.direction)

        case .xline(let xl):
            return (point - xl.origin).dot(xl.direction)

        case .arc(let arc):
            guard abs(arc.sweep) > KernelTolerance.parametric else { return 0.0 }
            let rawAngle = atan2(point.y - arc.center.y, point.x - arc.center.x)
            var delta = (rawAngle - arc.startAngle).truncatingRemainder(dividingBy: 2.0 * .pi)
            if arc.sweep > 0 {
                if delta < 0 { delta += 2.0 * .pi }
            } else {
                if delta > 0 { delta -= 2.0 * .pi }
            }
            return delta / arc.sweep

        case .circle(let circle):
            var angle = atan2(point.y - circle.center.y, point.x - circle.center.x)
            if angle < 0 { angle += 2.0 * .pi }
            return angle / (2.0 * .pi)

        case .ellipse(let e):
            guard abs(e.sweep) > KernelTolerance.parametric else { return 0.0 }
            // Map to ellipse frame: solve angle of closest parametric point
            // via two Newton iterations from the circular seed.
            let rel = point - e.center
            let a = e.majorAxis.length
            guard a > KernelTolerance.linear else { return 0.0 }
            let ux = e.majorAxis.normalized
            let uy = ux.perpCCW
            let b = a * e.minorRatio
            guard b > KernelTolerance.linear else { return paramAtPoint(.line(LineSeg2d(start: e.center + (ux * -a), end: e.center + (ux * a))), point: point) }
            let px = rel.dot(ux), py = rel.dot(uy)
            var ang = atan2(py / b, px / a)
            for _ in 0..<4 {
                let c = cos(ang), s = sin(ang)
                let ex = a * c - px, ey = b * s - py
                let dx = -a * s, dy = b * c
                let denom = dx * dx + dy * dy
                guard denom > 1e-24 else { break }
                ang -= (ex * dx + ey * dy) / denom
            }
            var delta = (ang - e.startAngle).truncatingRemainder(dividingBy: 2.0 * .pi)
            if e.sweep > 0 {
                if delta < 0 { delta += 2.0 * .pi }
            } else {
                if delta > 0 { delta -= 2.0 * .pi }
            }
            return delta / e.sweep

        case .spline(let spline):
            guard let (u0, u1) = SplineEval.domain(of: spline) else { return 0.0 }
            // Coarse-to-fine: sample then refine by ternary-style descent.
            var bestU = u0
            var bestD = Double.greatestFiniteMagnitude
            let coarse = 32
            for i in 0...coarse {
                let u = u0 + (u1 - u0) * Double(i) / Double(coarse)
                if let p = SplineEval.evaluate(spline, at: u) {
                    let d = p.distanceSquared(to: point)
                    if d < bestD { bestD = d; bestU = u }
                }
            }
            var step = (u1 - u0) / Double(coarse)
            for _ in 0..<24 {
                var improved = false
                for cand in [bestU - step, bestU + step] {
                    guard cand >= u0 && cand <= u1,
                          let p = SplineEval.evaluate(spline, at: cand) else { continue }
                    let d = p.distanceSquared(to: point)
                    if d < bestD { bestD = d; bestU = cand; improved = true }
                }
                if !improved { step *= 0.5 }
                if step < 1e-12 * (u1 - u0) { break }
            }
            // Newton polish on f(u) = (P(u) - Q) . P'(u) = 0 (closest-point
            // stationarity). The hill-climb above can stall ~1e-4 away on
            // long splines; Newton converges it to 1e-12.
            let hN = max(1e-9, 1e-6 * (u1 - u0))
            for _ in 0..<20 {
                guard let p = SplineEval.evaluate(spline, at: bestU) else { break }
                let t = CurveEval.tangentAt(.spline(spline), t: (bestU - u0) / (u1 - u0))
                let f = (p - point).dot(t)
                if abs(f) < 1e-13 { break }
                let up = min(u1, bestU + hN), um = max(u0, bestU - hN)
                guard up > um else { break }
                guard let pp = SplineEval.evaluate(spline, at: up),
                      let pm = SplineEval.evaluate(spline, at: um) else { break }
                let tp = CurveEval.tangentAt(.spline(spline), t: (up - u0) / (u1 - u0))
                let tm = CurveEval.tangentAt(.spline(spline), t: (um - u0) / (u1 - u0))
                let df = ((pp - point).dot(tp) - (pm - point).dot(tm)) / (up - um)
                guard abs(df) > 1e-300 else { break }
                var stepN = -f / df
                stepN = min(0.1 * (u1 - u0), max(-0.1 * (u1 - u0), stepN))
                let nu = min(u1, max(u0, bestU + stepN))
                guard let np = SplineEval.evaluate(spline, at: nu) else { break }
                if np.distanceSquared(to: point) >= bestD + 1e-24 { break }
                bestD = np.distanceSquared(to: point)
                bestU = nu
            }
            return (bestU - u0) / (u1 - u0)

        case .polySegment(let seg):
            switch seg.geometry {
            case .line(let l): return paramAtPoint(.line(l), point: point)
            case .arc(let a): return paramAtPoint(.arc(a), point: point)
            }
        }
    }

    // MARK: - Splitting

    /// Sub-curve spanning [t1, t2]. Powers TRIM/EXTEND/FILLET.
    /// Circle wraps (t2 < t1 after normalization) must be split by the
    /// caller into two arcs — splitAt never emits negative sweeps.
    public static func splitAt(_ curve: Curve2d, t1: Double, t2: Double) -> Curve2d? {
        guard abs(t2 - t1) > KernelTolerance.parametric else { return nil }
        let lo = min(t1, t2)
        switch curve {
        case .line(let seg):
            let p1 = pointAt(.line(seg), t: t1)
            let p2 = pointAt(.line(seg), t: t2)
            return .line(LineSeg2d(start: p1, end: p2))

        case .arc(let arc):
            let newStart = arc.startAngle + arc.sweep * t1
            let newSweep = arc.sweep * (t2 - t1)
            return .arc(Arc2d(center: arc.center, radius: arc.radius, startAngle: newStart, sweep: newSweep))

        case .circle(let circle):
            guard t2 > t1 else { return nil }
            let startAngle = 2.0 * .pi * t1
            let sweep = 2.0 * .pi * (t2 - t1)
            return .arc(Arc2d(center: circle.center, radius: circle.radius, startAngle: startAngle, sweep: sweep))

        case .ellipse(let e):
            let newStart = e.startAngle + e.sweep * t1
            let newSweep = e.sweep * (t2 - t1)
            return .ellipse(Ellipse2d(center: e.center, majorAxis: e.majorAxis,
                                      minorRatio: e.minorRatio, startAngle: newStart, sweep: newSweep))

        case .spline(let spline):
            guard let (u0, u1) = SplineEval.domain(of: spline) else { return nil }
            let ua = u0 + (u1 - u0) * lo
            let ub = u0 + (u1 - u0) * max(t1, t2)
            // Isolate [ua, ub] by splitting twice.
            let afterA: Spline2d
            if ua <= u0 + 1e-12 {
                afterA = spline
            } else {
                guard let (_, right) = SplineEval.split(spline, at: ua) else { return nil }
                afterA = right
            }
            guard let (ua2, ub2) = SplineEval.domain(of: afterA) else { return nil }
            if ub >= ub2 - 1e-9 * (ub2 - ua2) { return .spline(afterA) }
            guard let (left, _) = SplineEval.split(afterA, at: ub) else { return nil }
            return .spline(left)

        case .polySegment(let seg):
            // Interpolate widths linearly across [t1, t2].
            let w1 = seg.startWidth + (seg.endWidth - seg.startWidth) * t1
            let w2 = seg.startWidth + (seg.endWidth - seg.startWidth) * t2
            switch seg.geometry {
            case .line(let l):
                guard case .line(let subLine)? = splitAt(.line(l), t1: t1, t2: t2) else { return nil }
                return .polySegment(PolySegment2d(index: seg.index, geometry: .line(subLine), startWidth: w1, endWidth: w2))
            case .arc(let a):
                guard case .arc(let subArc)? = splitAt(.arc(a), t1: t1, t2: t2) else { return nil }
                return .polySegment(PolySegment2d(index: seg.index, geometry: .arc(subArc), startWidth: w1, endWidth: w2))
            }

        case .ray, .xline:
            return nil
        }
    }

    // MARK: - Bounding boxes

    public static func boundingBox(_ curve: Curve2d) -> BoundingBox2d? {
        switch curve {
        case .line(let seg):
            return BoundingBox2d(min: seg.start, max: seg.end)
        case .arc(let arc):
            var box = BoundingBox2d(point: arc.startPoint)
            box.include(arc.endPoint)
            // Include axis extrema inside the sweep.
            let twoPi = 2.0 * .pi
            func norm(_ v: Double) -> Double {
                var r = v.truncatingRemainder(dividingBy: twoPi)
                if r < 0 { r += twoPi }
                return r
            }
            let sweepLen = abs(arc.sweep)
            for k in 0..<4 {
                let ang = Double(k) * .pi / 2.0
                let d = arc.sweep >= 0
                    ? norm(ang - arc.startAngle)
                    : norm(arc.startAngle - ang)
                if d <= sweepLen + 1e-12 {
                    box.include(Point2d(x: arc.center.x + arc.radius * cos(ang),
                                        y: arc.center.y + arc.radius * sin(ang)))
                }
            }
            return box
        case .circle(let c):
            return BoundingBox2d(
                min: Point2d(x: c.center.x - c.radius, y: c.center.y - c.radius),
                max: Point2d(x: c.center.x + c.radius, y: c.center.y + c.radius))
        case .ellipse(let e):
            // Conservative: sample extrema of parametric form.
            var box: BoundingBox2d? = nil
            for i in 0...64 {
                let p = pointAt(.ellipse(e), t: Double(i) / 64.0)
                if box == nil { box = BoundingBox2d(point: p) } else { box!.include(p) }
            }
            return box
        case .spline(let s):
            if let cb = SplineEval.controlBounds(s) { return cb }
            return nil
        case .ray(let r):
            return BoundingBox2d(point: r.origin)
        case .xline(let xl):
            return BoundingBox2d(point: xl.origin)
        case .polySegment(let seg):
            switch seg.geometry {
            case .line(let l): return boundingBox(.line(l))
            case .arc(let a): return boundingBox(.arc(a))
            }
        }
    }
}
