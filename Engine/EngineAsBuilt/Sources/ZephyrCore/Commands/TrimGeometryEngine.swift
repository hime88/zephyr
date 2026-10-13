import Foundation
import SwiftSDL

// =========================================================================
// MARK: - TrimCriterion
// =========================================================================

/// Criteria used to determine which portion/interval of an entity to trim.
public enum TrimCriterion: Sendable {
    /// Single point click in world coordinates.
    case click(point: Vector3)
    /// Fence segment in world coordinates.
    case fence(p1: Vector3, p2: Vector3)
    /// Selection box in world coordinates (min, max, crossing vs window).
    case rect(min: Vector3, max: Vector3, isCrossing: Bool)
}

// =========================================================================
// MARK: - TrimGeometryEngine
// =========================================================================

/// Pure geometric engine for computing intersections and trimming CAD primitives.
@MainActor
public enum TrimGeometryEngine {

    // MARK: - Geometry Decomposition

    /// Explodes a primitive into a list of world-space line segments using the given transform.
    public static func explode(primitive: CADPrimitive, t: Transform3D) -> [(Vector3, Vector3)] {
        func curvedSegmentCount(radius: Double, span: Double = 2.0 * .pi) -> Int {
            guard radius > 1e-12, span > 0 else { return 2 }
            let relativeChordError = 1e-7
            let maxStep = 2.0 * acos(max(-1.0, min(1.0, 1.0 - relativeChordError)))
            guard maxStep.isFinite, maxStep > 0 else { return 4096 }
            return max(2, min(4096, Int(ceil(span / maxStep))))
        }

        var segs: [(Vector3, Vector3)] = []
        switch primitive {
        case .line(let ls, let le, _):
            segs.append((t.transformPoint(ls), t.transformPoint(le)))
        case .polygon(let pts, _), .fillPolygon(let pts, _), .fillComplexPolygon(let pts, _, _), .gradient(let pts, _, _, _, _, _):
            guard pts.count >= 2 else { return [] }
            for i in 0..<(pts.count - 1) { segs.append((t.transformPoint(pts[i]), t.transformPoint(pts[i+1]))) }
            segs.append((t.transformPoint(pts.last!), t.transformPoint(pts.first!)))
        case .polyline(let path, _):
            let pts = path.tessellatedPoints(segmentsPerRadian: 48)
            guard pts.count >= 2 else { return [] }
            for i in 0..<(pts.count - 1) { segs.append((t.transformPoint(pts[i]), t.transformPoint(pts[i+1]))) }
        case .circle(let center, let radius, _):
            let seg = curvedSegmentCount(radius: radius)
            var pts: [Vector3] = []
            for i in 0..<seg {
                let a = 2.0 * Double.pi * Double(i) / Double(seg)
                pts.append(t.transformPoint(Vector3(x: center.x + cos(a) * radius, y: center.y + sin(a) * radius, z: center.z)))
            }
            for i in 0..<(pts.count - 1) { segs.append((pts[i], pts[i+1])) }
            segs.append((pts.last!, pts.first!))
        case .arc(let center, let radius, let startAngle, let endAngle, _):
            var span = endAngle - startAngle
            if span < 0 { span += 2.0 * Double.pi }
            let seg = curvedSegmentCount(radius: radius, span: span)
            var pts: [Vector3] = []
            for i in 0...seg {
                let a = startAngle + span * Double(i) / Double(seg)
                pts.append(t.transformPoint(Vector3(x: center.x + cos(a) * radius, y: center.y + sin(a) * radius, z: center.z)))
            }
            for i in 0..<(pts.count - 1) { segs.append((pts[i], pts[i+1])) }
        case .ellipse(let center, let majorAxis, let minorRatio, _):
            let majorLen = majorAxis.magnitude
            let minorLen = majorLen * minorRatio
            let segsCount = curvedSegmentCount(radius: max(majorLen, abs(minorLen)))
            let rot = atan2(majorAxis.y, majorAxis.x)
            let cosRot = cos(rot); let sinRot = sin(rot)
            for i in 0..<segsCount {
                let t1 = Double(i) * 2.0 * .pi / Double(segsCount)
                let t2a = Double((i + 1) % segsCount) * 2.0 * .pi / Double(segsCount)
                let p1 = Vector3(
                    x: majorLen * cos(t1) * cosRot - minorLen * sin(t1) * sinRot + center.x,
                    y: majorLen * cos(t1) * sinRot + minorLen * sin(t1) * cosRot + center.y,
                    z: center.z)
                let p2 = Vector3(
                    x: majorLen * cos(t2a) * cosRot - minorLen * sin(t2a) * sinRot + center.x,
                    y: majorLen * cos(t2a) * sinRot + minorLen * sin(t2a) * cosRot + center.y,
                    z: center.z)
                segs.append((t.transformPoint(p1), t.transformPoint(p2)))
            }
        case .spline(let controlPoints, let knots, let degree, let weights, _):
            let w = weights ?? Array(repeating: 1.0, count: controlPoints.count)
            let segmentCount = min(4096, max(512, controlPoints.count * 128))
            let evaluated = NURBSEvaluator.evaluateByKnotSpans(
                degree: degree,
                knots: knots,
                controlPoints: controlPoints,
                weights: w,
                segmentsPerSpan: max(4, segmentCount / 8))
            if evaluated.count >= 2 {
                for i in 0..<(evaluated.count - 1) {
                    segs.append((t.transformPoint(evaluated[i]), t.transformPoint(evaluated[i+1])))
                }
            }
        case .penStroke(let vertices, _, _):
            guard vertices.count >= 2 else { break }
            for i in 0..<(vertices.count - 1) {
                segs.append((t.transformPoint(vertices[i].position), t.transformPoint(vertices[i+1].position)))
            }
        case .rect(let origin, let size, _), .fillRect(let origin, let size, _):
            let corners = [
                origin,
                Vector3(x: origin.x + size.x, y: origin.y, z: origin.z),
                Vector3(x: origin.x + size.x, y: origin.y + size.y, z: origin.z),
                Vector3(x: origin.x, y: origin.y + size.y, z: origin.z),
            ]
            for i in 0..<4 {
                segs.append((t.transformPoint(corners[i]), t.transformPoint(corners[(i+1)%4])))
            }
        default: break
        }
        return segs
    }

    /// Computes intersection points between a finite line segment and a circle.
    public static func intersectSegmentCircle(
        segmentA: Vector3, segmentB: Vector3,
        circleCenter: Vector3, radius: Double
    ) -> [Vector3] {
        let dir = Vector3(x: segmentB.x - segmentA.x, y: segmentB.y - segmentA.y, z: segmentB.z - segmentA.z)
        let dx = dir.x; let dy = dir.y
        let fx = segmentA.x - circleCenter.x; let fy = segmentA.y - circleCenter.y

        let a = dx * dx + dy * dy
        let b = 2.0 * (fx * dx + fy * dy)
        let c = fx * fx + fy * fy - radius * radius

        let discriminant = b * b - 4.0 * a * c
        if discriminant < 0 { return [] }

        let sqrtD = sqrt(discriminant)
        let t1 = (-b - sqrtD) / (2.0 * a)
        let t2 = (-b + sqrtD) / (2.0 * a)

        var result: [Vector3] = []
        if t1 >= -1e-9 && t1 <= 1.0 + 1e-9 {
            result.append(Vector3(x: segmentA.x + t1 * dx, y: segmentA.y + t1 * dy, z: segmentA.z))
        }
        if t2 >= -1e-9 && t2 <= 1.0 + 1e-9 && abs(t2 - t1) > 1e-12 {
            result.append(Vector3(x: segmentA.x + t2 * dx, y: segmentA.y + t2 * dy, z: segmentA.z))
        }
        return result
    }

    /// Extracts the color from a primitive, if it carries one.
    public static func colorForPrimitive(_ p: CADPrimitive) -> ColorRGBA? {
        switch p {
        case .line(_, _, let c): return c
        case .arc(_, _, _, _, let c): return c
        case .circle(_, _, let c): return c
        case .ellipse(_, _, _, let c): return c
        case .spline(_, _, _, _, let c): return c
        case .penStroke(_, _, let c): return c
        case .polygon(_, let c): return c
        case .polyline(_, let c): return c
        case .rect(_, _, let c): return c
        case .fillPolygon(_, let c): return c
        case .fillRect(_, _, let c): return c
        default: return nil
        }
    }

    /// Normalizes angle to [0, 2pi).
    public static func normAngle(_ v: Double) -> Double {
        let twoPi = 2.0 * Double.pi
        var r = v.truncatingRemainder(dividingBy: twoPi)
        if r < 0 { r += twoPi }
        return r
    }

    // MARK: - Cutting Edge Collection

    /// Collects cutting segments in world space from the document.
    /// - If `cuttingHandles` is non-nil and not empty: collects only from those entities.
    /// - If `cuttingHandles` is nil or empty: collects from all visible entities in the document.
    public static func collectCuttingSegments(
        document: CADDocument,
        cuttingHandles: Set<UUID>?,
        excludedHandle: UUID? = nil
    ) -> (cuttingSegments: [(Vector3, Vector3)], exactLineCuttingSegments: [(Vector3, Vector3)]) {
        var cuttingSegments: [(Vector3, Vector3)] = []
        var exactLineCuttingSegments: [(Vector3, Vector3)] = []

        let entities: [CADEntity]
        if let handles = cuttingHandles, !handles.isEmpty {
            entities = handles.compactMap { document.entity(for: $0) }
        } else {
            entities = Array(document.entitiesView)
        }

        for otherEntity in entities {
            if let excluded = excludedHandle, otherEntity.handle == excluded { continue }
            guard let layer = document.layer(for: otherEntity.layerID), layer.isVisible else { continue }
            guard otherEntity.blockID == nil else { continue }
            guard let geom = document.resolvedGeometry(for: otherEntity) else { continue }

            for prim in geom {
                if case .line(let start, let end, _) = prim {
                    let segment = (otherEntity.transform.transformPoint(start), otherEntity.transform.transformPoint(end))
                    cuttingSegments.append(segment)
                    exactLineCuttingSegments.append(segment)
                } else {
                    cuttingSegments.append(contentsOf: explode(primitive: prim, t: otherEntity.transform))
                }
            }
        }

        return (cuttingSegments, exactLineCuttingSegments)
    }

    // MARK: - Primitive Trimming Solvers

    /// Trims an entire entity against cutting edges using the provided criterion.
    public static func trimEntity(
        entity: CADEntity,
        document: CADDocument,
        criterion: TrimCriterion,
        cuttingSegments: [(Vector3, Vector3)],
        exactLines: [(Vector3, Vector3)],
        zoom: Double
    ) -> (newGeometry: [CADPrimitive]?, modified: Bool, errorMsg: String?) {
        guard let localGeom = entity.localGeometry, !localGeom.isEmpty else {
            return (nil, false, "Entity has no local geometry.")
        }

        let transform = entity.transform

        switch criterion {
        case .click(let rawClick):
            // Single click: find the closest primitive to the click point
            var bestPrimIndex: Int? = nil
            var bestPrimDistSq: Double = .infinity

            for (i, prim) in localGeom.enumerated() {
                if let d = CADHitTesting.distanceSqToPrimitive(prim, point: rawClick, transform: transform, t2: .infinity) {
                    if d < bestPrimDistSq {
                        bestPrimDistSq = d
                        bestPrimIndex = i
                    }
                }
            }

            guard let primIndex = bestPrimIndex else {
                return (nil, false, "No primitive found near click.")
            }

            let targetPrim = localGeom[primIndex]
            let (newPrims, modified, errorMsg) = trimPrimitive(
                primitive: targetPrim,
                transform: transform,
                criterion: criterion,
                cuttingSegments: cuttingSegments,
                exactLines: exactLines,
                zoom: zoom
            )

            if let errorMsg {
                return (nil, false, errorMsg)
            }
            guard modified else {
                return (nil, false, nil)
            }

            var updatedGeom = localGeom
            updatedGeom.remove(at: primIndex)
            if let replacements = newPrims {
                updatedGeom.insert(contentsOf: replacements, at: primIndex)
            }
            return (updatedGeom, true, nil)

        case .fence, .rect:
            // Batch trim: evaluate each primitive against the criterion
            var updatedGeom: [CADPrimitive] = []
            var anyModified = false

            for prim in localGeom {
                let (newPrims, modified, _) = trimPrimitive(
                    primitive: prim,
                    transform: transform,
                    criterion: criterion,
                    cuttingSegments: cuttingSegments,
                    exactLines: exactLines,
                    zoom: zoom
                )

                if modified {
                    anyModified = true
                    if let replacements = newPrims {
                        updatedGeom.append(contentsOf: replacements)
                    }
                } else {
                    updatedGeom.append(prim)
                }
            }

            guard anyModified else {
                return (nil, false, nil)
            }
            return (updatedGeom, true, nil)
        }
    }

    /// Trims a single primitive. Returns the replacement primitives (or empty array if fully trimmed),
    /// whether it was modified, and an optional error message.
    public static func trimPrimitive(
        primitive: CADPrimitive,
        transform: Transform3D,
        criterion: TrimCriterion,
        cuttingSegments: [(Vector3, Vector3)],
        exactLines: [(Vector3, Vector3)],
        zoom: Double
    ) -> (result: [CADPrimitive]?, modified: Bool, errorMsg: String?) {
        switch primitive {
        case .line(let ls, let le, let color):
            return trimLine(
                ls: ls, le: le, color: color,
                transform: transform, criterion: criterion, cuttingSegments: cuttingSegments
            )

        case .arc(let center, let radius, let startAngle, let endAngle, let color):
            return trimArc(
                center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, color: color,
                transform: transform, criterion: criterion, cuttingSegments: cuttingSegments
            )

        case .circle(let center, let radius, let color):
            return trimCircle(
                center: center, radius: radius, color: color,
                transform: transform, criterion: criterion, cuttingSegments: cuttingSegments
            )

        case .spline(let controlPoints, let knots, let degree, let weights, let color):
            return trimSpline(
                controlPoints: controlPoints, knots: knots, degree: degree, weights: weights, color: color,
                transform: transform, criterion: criterion, cuttingSegments: cuttingSegments,
                exactLines: exactLines, zoom: zoom
            )

        default:
            return trimExploded(
                primitive: primitive,
                transform: transform, criterion: criterion, cuttingSegments: cuttingSegments
            )
        }
    }

    // MARK: - Line Solver

    private static func trimLine(
        ls: Vector3, le: Vector3, color: ColorRGBA?,
        transform: Transform3D,
        criterion: TrimCriterion,
        cuttingSegments: [(Vector3, Vector3)]
    ) -> (result: [CADPrimitive]?, modified: Bool, errorMsg: String?) {
        let ws = transform.transformPoint(ls)
        let we = transform.transformPoint(le)
        let segDX = we.x - ws.x; let segDY = we.y - ws.y
        let segLenSq = segDX * segDX + segDY * segDY
        if segLenSq <= 1e-18 {
            return ([], true, nil)
        }

        // Find intersections with cutting segments in world space
        var hitsT: [Double] = []
        for edge in cuttingSegments {
            guard let res = CADGeometryMath.segmentSegmentIntersection(a: ws, b: we, c: edge.0, d: edge.1) else { continue }
            if res.t > 1e-9 && res.t < 1.0 - 1e-9 {
                if !hitsT.contains(where: { abs($0 - res.t) < 1e-6 }) {
                    hitsT.append(res.t)
                }
            }
        }

        guard !hitsT.isEmpty else {
            return (nil, false, nil)
        }

        hitsT.sort()
        let tPoints = [0.0] + hitsT + [1.0]

        // Evaluate intervals
        var keptSpans: [(Double, Double)] = []
        var anyTrimmed = false

        for k in 0..<(tPoints.count - 1) {
            let tA = tPoints[k]
            let tB = tPoints[k + 1]
            let pA = Vector3(x: ws.x + tA * segDX, y: ws.y + tA * segDY, z: ws.z)
            let pB = Vector3(x: ws.x + tB * segDX, y: ws.y + tB * segDY, z: ws.z)
            let mid = Vector3(x: (pA.x + pB.x) * 0.5, y: (pA.y + pB.y) * 0.5, z: ws.z)

            var shouldTrim = false
            switch criterion {
            case .click(let rawClick):
                let dpX = rawClick.x - ws.x
                let dpY = rawClick.y - ws.y
                let dot = dpX * segDX + dpY * segDY
                let tClick = max(0.0, min(1.0, dot / segLenSq))
                if tClick >= tA - 1e-9 && tClick <= tB + 1e-9 {
                    shouldTrim = true
                }

            case .fence(let fp1, let fp2):
                if CADRectSelect.segmentsIntersect(pA, pB, fp1, fp2) {
                    shouldTrim = true
                }

            case .rect(let bMin, let bMax, let isCrossing):
                if isCrossing {
                    if (mid.x >= bMin.x && mid.x <= bMax.x && mid.y >= bMin.y && mid.y <= bMax.y)
                        || CADRectSelect.segmentIntersectsRect(p1: pA, p2: pB, rectMin: bMin, rectMax: bMax) {
                        shouldTrim = true
                    }
                } else {
                    if pA.x >= bMin.x && pA.x <= bMax.x && pA.y >= bMin.y && pA.y <= bMax.y &&
                       pB.x >= bMin.x && pB.x <= bMax.x && pB.y >= bMin.y && pB.y <= bMax.y {
                        shouldTrim = true
                    }
                }
            }

            if shouldTrim {
                anyTrimmed = true
            } else {
                if let last = keptSpans.last, abs(last.1 - tA) < 1e-8 {
                    keptSpans[keptSpans.count - 1].1 = tB
                } else {
                    keptSpans.append((tA, tB))
                }
            }
        }

        guard anyTrimmed else {
            return (nil, false, nil)
        }

        var newPrims: [CADPrimitive] = []
        for span in keptSpans {
            let locA = Vector3(x: ls.x + span.0 * (le.x - ls.x), y: ls.y + span.0 * (le.y - ls.y), z: ls.z)
            let locB = Vector3(x: ls.x + span.1 * (le.x - ls.x), y: ls.y + span.1 * (le.y - ls.y), z: ls.z)
            newPrims.append(.line(start: locA, end: locB, color: color))
        }

        return (newPrims, true, nil)
    }

    // MARK: - Arc Solver

    private static func trimArc(
        center: Vector3, radius: Double, startAngle: Double, endAngle: Double, color: ColorRGBA?,
        transform: Transform3D,
        criterion: TrimCriterion,
        cuttingSegments: [(Vector3, Vector3)]
    ) -> (result: [CADPrimitive]?, modified: Bool, errorMsg: String?) {
        let wc = transform.transformPoint(center)
        let s = transform.scale
        let wr = radius * max(abs(s.x), abs(s.y))
        let wsa = startAngle + transform.rotation
        let wea = endAngle + transform.rotation
        var span = wea - wsa
        if span < 0 { span += 2.0 * .pi }

        var hitOffsets: [Double] = []
        for edge in cuttingSegments {
            let pts = intersectSegmentCircle(segmentA: edge.0, segmentB: edge.1, circleCenter: wc, radius: wr)
            for pt in pts {
                let a = atan2(pt.y - wc.y, pt.x - wc.x)
                if CADGeometryMath.angleIsOnCCWSweep(angle: a, start: wsa, end: wsa + span) {
                    let off = normAngle(a - wsa)
                    if off > 1e-5 && off < span - 1e-5 {
                        if !hitOffsets.contains(where: { abs($0 - off) < 1e-5 }) {
                            hitOffsets.append(off)
                        }
                    }
                }
            }
        }

        guard !hitOffsets.isEmpty else {
            return (nil, false, nil)
        }

        hitOffsets.sort()
        let arcPoints = [0.0] + hitOffsets + [span]

        var keptSpans: [(Double, Double)] = []
        var anyTrimmed = false

        for k in 0..<(arcPoints.count - 1) {
            let offA = arcPoints[k]
            let offB = arcPoints[k + 1]
            let midOff = (offA + offB) * 0.5
            let midA = wsa + midOff
            let midP = Vector3(x: wc.x + cos(midA) * wr, y: wc.y + sin(midA) * wr, z: wc.z)
            let pA = Vector3(x: wc.x + cos(wsa + offA) * wr, y: wc.y + sin(wsa + offA) * wr, z: wc.z)
            let pB = Vector3(x: wc.x + cos(wsa + offB) * wr, y: wc.y + sin(wsa + offB) * wr, z: wc.z)

            var shouldTrim = false
            switch criterion {
            case .click(let rawClick):
                let rawAngle = atan2(rawClick.y - wc.y, rawClick.x - wc.x)
                let clickT = normAngle(rawAngle - wsa)
                if clickT >= offA - 1e-5 && clickT <= offB + 1e-5 {
                    shouldTrim = true
                }

            case .fence(let fp1, let fp2):
                let pts = intersectSegmentCircle(segmentA: fp1, segmentB: fp2, circleCenter: wc, radius: wr)
                for p in pts {
                    let a = atan2(p.y - wc.y, p.x - wc.x)
                    let off = normAngle(a - wsa)
                    if off >= offA - 1e-5 && off <= offB + 1e-5 {
                        shouldTrim = true
                    }
                }

            case .rect(let bMin, let bMax, let isCrossing):
                if isCrossing {
                    if (midP.x >= bMin.x && midP.x <= bMax.x && midP.y >= bMin.y && midP.y <= bMax.y)
                        || CADRectSelect.segmentIntersectsRect(p1: pA, p2: pB, rectMin: bMin, rectMax: bMax) {
                        shouldTrim = true
                    }
                } else {
                    if midP.x >= bMin.x && midP.x <= bMax.x && midP.y >= bMin.y && midP.y <= bMax.y &&
                       pA.x >= bMin.x && pA.x <= bMax.x && pA.y >= bMin.y && pA.y <= bMax.y &&
                       pB.x >= bMin.x && pB.x <= bMax.x && pB.y >= bMin.y && pB.y <= bMax.y {
                        shouldTrim = true
                    }
                }
            }

            if shouldTrim {
                anyTrimmed = true
            } else {
                if let last = keptSpans.last, abs(last.1 - offA) < 1e-8 {
                    keptSpans[keptSpans.count - 1].1 = offB
                } else {
                    keptSpans.append((offA, offB))
                }
            }
        }

        guard anyTrimmed else {
            return (nil, false, nil)
        }

        var newPrims: [CADPrimitive] = []
        for span in keptSpans {
            let locStart = startAngle + span.0
            let locEnd = startAngle + span.1
            newPrims.append(.arc(center: center, radius: radius, startAngle: locStart, endAngle: locEnd, color: color))
        }

        return (newPrims, true, nil)
    }

    // MARK: - Circle Solver

    private static func trimCircle(
        center: Vector3, radius: Double, color: ColorRGBA?,
        transform: Transform3D,
        criterion: TrimCriterion,
        cuttingSegments: [(Vector3, Vector3)]
    ) -> (result: [CADPrimitive]?, modified: Bool, errorMsg: String?) {
        let wc = transform.transformPoint(center)
        let s = transform.scale
        let wr = radius * max(abs(s.x), abs(s.y))

        var hitsAngle: [Double] = []
        for edge in cuttingSegments {
            let pts = intersectSegmentCircle(segmentA: edge.0, segmentB: edge.1, circleCenter: wc, radius: wr)
            for pt in pts {
                let a = normAngle(atan2(pt.y - wc.y, pt.x - wc.x))
                if !hitsAngle.contains(where: { abs($0 - a) < 1e-5 || abs($0 - a) > (2.0 * .pi - 1e-5) }) {
                    hitsAngle.append(a)
                }
            }
        }

        guard hitsAngle.count >= 2 else {
            return (nil, false, hitsAngle.isEmpty ? nil : "Circle needs at least 2 distinct intersections to trim.")
        }

        hitsAngle.sort()
        let count = hitsAngle.count

        var keptSectors: [(Double, Double)] = []
        var anyTrimmed = false

        for i in 0..<count {
            let startW = hitsAngle[i]
            let endW = hitsAngle[(i + 1) % count]
            var span = endW - startW
            if span < 0 { span += 2.0 * .pi }

            let midA = normAngle(startW + span * 0.5)
            let midP = Vector3(x: wc.x + cos(midA) * wr, y: wc.y + sin(midA) * wr, z: wc.z)
            let pA = Vector3(x: wc.x + cos(startW) * wr, y: wc.y + sin(startW) * wr, z: wc.z)
            let pB = Vector3(x: wc.x + cos(endW) * wr, y: wc.y + sin(endW) * wr, z: wc.z)

            var shouldTrim = false
            switch criterion {
            case .click(let rawClick):
                let cAngle = normAngle(atan2(rawClick.y - wc.y, rawClick.x - wc.x))
                let rel = normAngle(cAngle - startW)
                if rel >= 0 && rel <= span {
                    shouldTrim = true
                }

            case .fence(let fp1, let fp2):
                let pts = intersectSegmentCircle(segmentA: fp1, segmentB: fp2, circleCenter: wc, radius: wr)
                for p in pts {
                    let a = normAngle(atan2(p.y - wc.y, p.x - wc.x))
                    let rel = normAngle(a - startW)
                    if rel >= 0 && rel <= span {
                        shouldTrim = true
                    }
                }

            case .rect(let bMin, let bMax, let isCrossing):
                if isCrossing {
                    if (midP.x >= bMin.x && midP.x <= bMax.x && midP.y >= bMin.y && midP.y <= bMax.y)
                        || CADRectSelect.segmentIntersectsRect(p1: pA, p2: pB, rectMin: bMin, rectMax: bMax) {
                        shouldTrim = true
                    }
                } else {
                    if midP.x >= bMin.x && midP.x <= bMax.x && midP.y >= bMin.y && midP.y <= bMax.y &&
                       pA.x >= bMin.x && pA.x <= bMax.x && pA.y >= bMin.y && pA.y <= bMax.y &&
                       pB.x >= bMin.x && pB.x <= bMax.x && pB.y >= bMin.y && pB.y <= bMax.y {
                        shouldTrim = true
                    }
                }
            }

            if shouldTrim {
                anyTrimmed = true
            } else {
                keptSectors.append((startW, endW))
            }
        }

        guard anyTrimmed else {
            return (nil, false, nil)
        }

        var newPrims: [CADPrimitive] = []
        for sector in keptSectors {
            let localStart = sector.0 - transform.rotation
            let localEnd = sector.1 - transform.rotation
            newPrims.append(.arc(center: center, radius: radius, startAngle: localStart, endAngle: localEnd, color: color))
        }

        return (newPrims, true, nil)
    }

    // MARK: - Spline Solver

    private static func trimSpline(
        controlPoints: [Vector3], knots: [Double], degree: Int, weights: [Double]?, color: ColorRGBA?,
        transform: Transform3D,
        criterion: TrimCriterion,
        cuttingSegments: [(Vector3, Vector3)],
        exactLines: [(Vector3, Vector3)],
        zoom: Double
    ) -> (result: [CADPrimitive]?, modified: Bool, errorMsg: String?) {
        let invTransform = transform.inverse()
        let w = weights ?? Array(repeating: 1.0, count: controlPoints.count)
        let p = degree
        let minT = knots[p]
        let maxT = knots[controlPoints.count]
        let parameterDuplicateTolerance = max(1e-6, (maxT - minT) * 1e-7)
        let scale = max(abs(transform.scale.x), abs(transform.scale.y), 1e-9)
        let localTolerance = max(1e-7, (4.0 / zoom) / scale)
        let localToleranceSq = localTolerance * localTolerance

        let localEdges: [(Vector3, Vector3)] = cuttingSegments.map {
            (invTransform.transformPoint($0.0), invTransform.transformPoint($0.1))
        }
        let localExactLineEdges: [(Vector3, Vector3)] = exactLines.map {
            (invTransform.transformPoint($0.0), invTransform.transformPoint($0.1))
        }

        struct SplineHit { let t: Double; let point: Vector3 }
        var hits: [SplineHit] = []

        func appendHit(t: Double, point: Vector3) {
            guard t > minT + 1e-8, t < maxT - 1e-8 else { return }
            if !hits.contains(where: { abs($0.t - t) < parameterDuplicateTolerance }) {
                hits.append(SplineHit(t: t, point: point))
            }
        }

        func extendedEdge(_ edge: (Vector3, Vector3), by amount: Double) -> (Vector3, Vector3) {
            let dx = edge.1.x - edge.0.x
            let dy = edge.1.y - edge.0.y
            let len = hypot(dx, dy)
            guard len > 1e-12 else { return edge }
            let ux = dx / len; let uy = dy / len
            return (
                Vector3(x: edge.0.x - ux * amount, y: edge.0.y - uy * amount, z: edge.0.z),
                Vector3(x: edge.1.x + ux * amount, y: edge.1.y + uy * amount, z: edge.1.z)
            )
        }

        func addEndpointTouchHit(_ endpoint: Vector3) {
            let t = NURBSEvaluator.findClosestParameter(
                degree: p, knots: knots, controlPoints: controlPoints, weights: w, to: endpoint, segments: 256
            )
            guard let point = NURBSEvaluator.evaluateAt(
                degree: p, knots: knots, controlPoints: controlPoints, weights: w, at: t
            ) else { return }
            let dx = point.x - endpoint.x
            let dy = point.y - endpoint.y
            if dx * dx + dy * dy <= localToleranceSq {
                appendHit(t: t, point: point)
            }
        }

        func findHits(on edge: (Vector3, Vector3), searchSegments: Int) {
            let results = NURBSEvaluator.findIntersectionParameters(
                degree: p, knots: knots, controlPoints: controlPoints, weights: w,
                segmentA: edge.0, segmentB: edge.1, searchSegments: searchSegments
            )
            for res in results { appendHit(t: res.t, point: res.point) }
        }

        for edge in localEdges { findHits(on: edge, searchSegments: 96) }
        for edge in localExactLineEdges {
            findHits(on: extendedEdge(edge, by: localTolerance), searchSegments: 256)
            addEndpointTouchHit(edge.0)
            addEndpointTouchHit(edge.1)
        }

        guard !hits.isEmpty else {
            return (nil, false, nil)
        }

        // Determine click parameter based on criterion
        let tClick: Double
        switch criterion {
        case .click(let rawClick):
            let invClick = invTransform.transformPoint(rawClick)
            tClick = NURBSEvaluator.findClosestParameter(
                degree: p, knots: knots, controlPoints: controlPoints, weights: w, to: invClick, segments: 96
            )

        case .fence(let fp1, let fp2):
            let lfp1 = invTransform.transformPoint(fp1)
            let lfp2 = invTransform.transformPoint(fp2)
            let fenceIntersections = NURBSEvaluator.findIntersectionParameters(
                degree: p, knots: knots, controlPoints: controlPoints, weights: w,
                segmentA: lfp1, segmentB: lfp2, searchSegments: 128
            )
            guard let firstHit = fenceIntersections.first else { return (nil, false, nil) }
            tClick = firstHit.t

        case .rect(let bMin, let bMax, _):
            // Center of rect converted to local space
            let center = Vector3(x: (bMin.x + bMax.x) * 0.5, y: (bMin.y + bMax.y) * 0.5, z: 0)
            let lCenter = invTransform.transformPoint(center)
            tClick = NURBSEvaluator.findClosestParameter(
                degree: p, knots: knots, controlPoints: controlPoints, weights: w, to: lCenter, segments: 96
            )
        }

        var tBefore = minT
        var tAfter = maxT
        for h in hits {
            if h.t < tClick && h.t > tBefore { tBefore = h.t }
            if h.t > tClick && h.t < tAfter { tAfter = h.t }
        }

        var newPrims: [CADPrimitive] = []
        var subdivisionFailed = false

        if tBefore > minT + 1e-6 {
            if let split = NURBSEvaluator.subdivide(
                degree: p, knots: knots, controlPoints: controlPoints, weights: w, at: tBefore
            ) {
                newPrims.append(.spline(
                    controlPoints: split.left.controlPoints, knots: split.left.knots,
                    degree: p, weights: split.left.weights, color: color
                ))
            } else {
                subdivisionFailed = true
            }
        }

        if tAfter < maxT - 1e-6 {
            if let split = NURBSEvaluator.subdivide(
                degree: p, knots: knots, controlPoints: controlPoints, weights: w, at: tAfter
            ) {
                newPrims.append(.spline(
                    controlPoints: split.right.controlPoints, knots: split.right.knots,
                    degree: p, weights: split.right.weights, color: color
                ))
            } else {
                subdivisionFailed = true
            }
        }

        if subdivisionFailed {
            // Fallback to exploded polyline trim
            return trimExploded(
                primitive: .spline(controlPoints: controlPoints, knots: knots, degree: degree, weights: weights, color: color),
                transform: transform, criterion: criterion, cuttingSegments: cuttingSegments
            )
        }

        return (newPrims, true, nil)
    }

    // MARK: - Exploded Polyline Fallback

    private static func trimExploded(
        primitive: CADPrimitive,
        transform: Transform3D,
        criterion: TrimCriterion,
        cuttingSegments: [(Vector3, Vector3)]
    ) -> (result: [CADPrimitive]?, modified: Bool, errorMsg: String?) {
        let invTransform = transform.inverse()
        let targetSegs = explode(primitive: primitive, t: .identity)
        guard !targetSegs.isEmpty else { return ([], true, nil) }

        var cumLen: [Double] = [0]
        for s in targetSegs {
            let dx = s.1.x - s.0.x
            let dy = s.1.y - s.0.y
            cumLen.append(cumLen.last! + sqrt(dx * dx + dy * dy))
        }
        let totalLen = cumLen.last!
        guard totalLen > 1e-9 else { return ([], true, nil) }

        // Local cutting edges
        struct Hit { let localPoint: Vector3; let t: Double }
        var hits: [Hit] = []

        for edge in cuttingSegments {
            let localEdge0 = invTransform.transformPoint(edge.0)
            let localEdge1 = invTransform.transformPoint(edge.1)

            for (i, s) in targetSegs.enumerated() {
                guard let res = CADGeometryMath.segmentSegmentIntersection(a: s.0, b: s.1, c: localEdge0, d: localEdge1) else { continue }
                if res.t >= -1e-9 && res.t <= 1.0 + 1e-9 {
                    let segLen = cumLen[i+1] - cumLen[i]
                    let globalT = (cumLen[i] + res.t * segLen) / totalLen
                    if globalT > 1e-9 && globalT < 1.0 - 1e-9 {
                        hits.append(Hit(localPoint: res.point, t: globalT))
                    }
                }
            }
        }

        guard !hits.isEmpty else {
            return (nil, false, nil)
        }

        // Determine click parameter along polyline
        let tClick: Double
        switch criterion {
        case .click(let rawClick):
            let invClick = invTransform.transformPoint(rawClick)
            var bestDistSq = Double.infinity
            var bestIdx = 0
            var bestSegT = 0.0

            for (i, s) in targetSegs.enumerated() {
                let dx = s.1.x - s.0.x; let dy = s.1.y - s.0.y
                let ls = dx * dx + dy * dy
                var t = 0.0
                if ls > 1e-18 {
                    t = max(0.0, min(1.0, ((invClick.x - s.0.x) * dx + (invClick.y - s.0.y) * dy) / ls))
                }
                let qx = s.0.x + t * dx; let qy = s.0.y + t * dy
                let dSq = (invClick.x - qx) * (invClick.x - qx) + (invClick.y - qy) * (invClick.y - qy)
                if dSq < bestDistSq {
                    bestDistSq = dSq; bestIdx = i; bestSegT = t
                }
            }
            tClick = (cumLen[bestIdx] + bestSegT * (cumLen[bestIdx+1] - cumLen[bestIdx])) / totalLen

        case .fence(let fp1, let fp2):
            let lfp0 = invTransform.transformPoint(fp1)
            let lfp1 = invTransform.transformPoint(fp2)
            var foundT: Double? = nil
            for (i, s) in targetSegs.enumerated() {
                if let res = CADGeometryMath.segmentSegmentIntersection(a: s.0, b: s.1, c: lfp0, d: lfp1) {
                    let segLen = cumLen[i+1] - cumLen[i]
                    foundT = (cumLen[i] + res.t * segLen) / totalLen
                    break
                }
            }
            guard let fT = foundT else { return (nil, false, nil) }
            tClick = fT

        case .rect(let bMin, let bMax, _):
            let center = Vector3(x: (bMin.x + bMax.x) * 0.5, y: (bMin.y + bMax.y) * 0.5, z: 0)
            let invCenter = invTransform.transformPoint(center)
            var bestDistSq = Double.infinity
            var bestIdx = 0
            var bestSegT = 0.0
            for (i, s) in targetSegs.enumerated() {
                let dx = s.1.x - s.0.x; let dy = s.1.y - s.0.y
                let ls = dx * dx + dy * dy
                var t = 0.0
                if ls > 1e-18 {
                    t = max(0.0, min(1.0, ((invCenter.x - s.0.x) * dx + (invCenter.y - s.0.y) * dy) / ls))
                }
                let qx = s.0.x + t * dx; let qy = s.0.y + t * dy
                let dSq = (invCenter.x - qx) * (invCenter.x - qx) + (invCenter.y - qy) * (invCenter.y - qy)
                if dSq < bestDistSq {
                    bestDistSq = dSq; bestIdx = i; bestSegT = t
                }
            }
            tClick = (cumLen[bestIdx] + bestSegT * (cumLen[bestIdx+1] - cumLen[bestIdx])) / totalLen
        }

        var tBefore = 0.0
        var tAfter = 1.0
        for h in hits {
            if h.t < tClick && h.t > tBefore { tBefore = h.t }
            if h.t > tClick && h.t < tAfter { tAfter = h.t }
        }

        var newPrims: [CADPrimitive] = []
        let color = colorForPrimitive(primitive)

        func buildLines(fromT startT: Double, toT endT: Double) {
            guard endT > startT else { return }
            for (i, s) in targetSegs.enumerated() {
                let segStartT = cumLen[i] / totalLen
                let segEndT = cumLen[i+1] / totalLen
                if segEndT <= startT + 1e-9 { continue }
                if segStartT >= endT - 1e-9 { continue }

                let startDiff = startT - segStartT
                let endDiff = endT - segStartT
                let segDiff = segEndT - segStartT
                let localStartFraction = max(0.0, startDiff / segDiff)
                let localEndFraction = min(1.0, endDiff / segDiff)

                let dx = s.1.x - s.0.x; let dy = s.1.y - s.0.y
                let pA = Vector3(x: s.0.x + localStartFraction * dx, y: s.0.y + localStartFraction * dy, z: s.0.z)
                let pB = Vector3(x: s.0.x + localEndFraction * dx, y: s.0.y + localEndFraction * dy, z: s.0.z)

                let diffX = pB.x - pA.x; let diffY = pB.y - pA.y
                if diffX * diffX + diffY * diffY > 1e-9 {
                    newPrims.append(.line(start: pA, end: pB, color: color))
                }
            }
        }

        if tBefore > 1e-9 { buildLines(fromT: 0.0, toT: tBefore) }
        if tAfter < 1.0 - 1e-9 { buildLines(fromT: tAfter, toT: 1.0) }

        if newPrims.isEmpty {
            return ([], true, nil)
        } else {
            return (newPrims, true, nil)
        }
    }
}
