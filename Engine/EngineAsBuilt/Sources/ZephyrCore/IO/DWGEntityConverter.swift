import Foundation
import CDWG

// =========================================================================
// MARK: - DWGEntityConverter
//
// Converts parsed DWG entity data (from DWGImporter) into CADPrimitive arrays.
// Maps DWG-specific structures into the engine's unified CADPrimitive enum.
//
// This is the bridge between raw DWG parsing and the rendering pipeline.

@MainActor
public enum DWGEntityConverter {

    /// Converts a raw LibreDWG bridge entity into engine primitives.
    public static func convertEntityToPrimitives(_ e: DWG_EntityData) -> [CADPrimitive] {
        let primColor: ColorRGBA? = DWGImporter.dwgColorToRGBA(aci: e.color, rgb: e.colorRGB)

        switch e.type {
        case DWG_ET_POINT:
            return [.point(position: DWGImporter.toVector(e.basePoint), color: primColor)]

        case DWG_ET_LINE:
            return [.line(start: DWGImporter.toVector(e.basePoint),
                         end: DWGImporter.toVector(e.secPoint),
                         color: primColor)]

        case DWG_ET_CIRCLE:
            return [.circle(center: DWGImporter.toVector(e.basePoint),
                           radius: e.radius,
                           color: primColor)]

        case DWG_ET_ARC:
            // DWG angles are in radians. The engine's arc uses CCW sweep in
            // math space; DWG angles are already CCW in radians.
            return [.arc(
                center: DWGImporter.toVector(e.basePoint),
                radius: e.radius,
                startAngle: e.startAngle,
                endAngle: e.endAngle,
                color: primColor
            )]

        case DWG_ET_LWPOLYLINE:
            return convertLWPolyline(e, color: primColor)

        case DWG_ET_POLYLINE_2D, DWG_ET_POLYLINE_3D:
            // Simple fallback: no vertex extraction for old-style polylines
            return []

        case DWG_ET_ELLIPSE:
            return convertEllipse(e, color: primColor)

        case DWG_ET_SPLINE:
            return convertSpline(e, color: primColor)

        case DWG_ET_TEXT, DWG_ET_MTEXT, DWG_ET_ATTDEF, DWG_ET_ATTRIB:
            let textVal = e.textValue.map { String(cString: $0) } ?? ""
            let cleaned = DXFEntityConverter.cleanMTextFormatting(textVal)
            let height = e.textHeight > 0 ? e.textHeight : 2.5
            let style = e.textStyle.map { String(cString: $0) }

            let pos = DWGImporter.toVector(e.basePoint)
            // DWG angles are already in radians. The engine negates the angle
            // because it's Y-down. DWG is Y-up, so we negate the angle for the engine.
            let angle = -e.textRotation

            return [
                .text(
                    position: pos,
                    text: cleaned,
                    height: height,
                    rotation: angle,
                    style: style,
                    alignH: Int(e.textAlignH),
                    alignV: Int(e.textAlignV),
                    mtextWidth: e.type == DWG_ET_MTEXT && e.textWidthScale > 0 ? e.textWidthScale : nil,
                    color: primColor
                )
            ]

        case DWG_ET_INSERT:
            // INSERTS are handled at the entity level (block references)
            return []

        case DWG_ET_SOLID:
            return [
                .fillPolygon(points: [
                    DWGImporter.toVector(e.basePoint),
                    DWGImporter.toVector(e.secPoint),
                    DWGImporter.toVector(e.thirdPoint),
                    DWGImporter.toVector(e.fourPoint),
                ], color: primColor)
            ]

        case DWG_ET_3DFACE:
            return [
                .polygon(points: [
                    DWGImporter.toVector(e.basePoint),
                    DWGImporter.toVector(e.secPoint),
                    DWGImporter.toVector(e.thirdPoint),
                    DWGImporter.toVector(e.fourPoint),
                ], color: primColor)
            ]

        case DWG_ET_HATCH:
            if e.hatchSolid != 0 {
                return []  // Need boundary loop data for solid hatches (not in bridge yet)
            } else {
                let patternName = e.hatchPatternName.map { String(cString: $0).uppercased() } ?? ""
                let scale = e.hatchScale > 0 ? e.hatchScale : 1.0
                let angle = e.hatchAngle
                return [.hatch(
                    boundary: [],
                    pattern: patternName.isEmpty ? "SOLID" : patternName,
                    scale: scale,
                    angle: angle,
                    color: primColor,
                    backgroundColor: nil
                )]
            }

        case DWG_ET_IMAGE:
            return []  // Image path resolution requires IMAGEDEF lookup (not in bridge yet)

        default:
            return []
        }
    }

    // MARK: - Polyline Conversion

    private static func convertLWPolyline(_ e: DWG_EntityData, color: ColorRGBA?) -> [CADPrimitive] {
        let count = Int(e.vertexCount2D)
        guard count > 0, let vertices = e.vertices2D else { return [] }

        if count == 1 {
            return [.point(position: Vector3(x: vertices[0].x, y: vertices[0].y, z: 0), color: color)]
        }

        let isClosed = (e.polyFlags & 0x01) != 0 ? true : false  // DWG closed flag is bit 0

        let path = CADPolyline(
            vertices: (0..<count).map { i in
                let v = vertices[i]
                return CADPolylineVertex(
                    position: Vector3(x: v.x, y: v.y, z: 0),
                    bulge: v.bulge,
                    startWidth: 0,
                    endWidth: 0)
            },
            isClosed: isClosed,
            lineTypeGenerationEnabled: false)

        return [.polyline(path: path, color: color)]
    }

    // MARK: - Ellipse Conversion

    private static func convertEllipse(_ e: DWG_EntityData, color: ColorRGBA?) -> [CADPrimitive] {
        let center = DWGImporter.toVector(e.basePoint)
        let majorVec = DWGImporter.toVector(e.secPoint)
        let majorLen = majorVec.magnitude
        let minorLen = majorLen * e.axisRatio

        guard majorLen > 1e-12, minorLen > 1e-12 else {
            return [.point(position: center, color: color)]
        }

        let startParam = e.startAngle
        let endParam = e.endAngle

        let segments = 64
        let isFull = abs(abs(endParam - startParam) - .pi * 2) < 1e-5

        var sweep = endParam - startParam
        if sweep < 0 && !isFull { sweep += .pi * 2.0 }

        let ellipseRotation = atan2(majorVec.y, majorVec.x)
        let cosRot = cos(ellipseRotation)
        let sinRot = sin(ellipseRotation)

        var points: [Vector3] = []
        for i in 0...segments {
            let t = Double(i) / Double(segments)
            let param = startParam + sweep * t
            let px = majorLen * cos(param)
            let py = minorLen * sin(param)
            let rx = px * cosRot - py * sinRot
            let ry = px * sinRot + py * cosRot
            points.append(Vector3(x: center.x + rx, y: center.y + ry, z: center.z))
        }

        if isFull {
            return [.polygon(points: points, color: color)]
        } else {
            return (0..<(points.count - 1)).map { i in
                .line(start: points[i], end: points[i + 1], color: color)
            }
        }
    }

    // MARK: - Spline Conversion

    private static func convertSpline(_ e: DWG_EntityData, color: ColorRGBA?) -> [CADPrimitive] {
        let degree = e.splineDegree > 0 ? Int(e.splineDegree) : 3

        if e.splineNControl > 0 && e.splineNKnots > 0,
           let ctrlPts = e.splineCtrlPts,
           let knotsPtr = e.splineKnots {

            let ctrlCount = Int(e.splineNControl)
            let knotCount = Int(e.splineNKnots)

            let vecs: [Vector3] = (0..<ctrlCount).map { i in
                DWGImporter.toVector(ctrlPts[i])
            }

            let weights: [Double] = Array(repeating: 1.0, count: ctrlCount)
            let knots = (0..<knotCount).map { knotsPtr[$0] }

            return [.spline(
                controlPoints: vecs,
                knots: knots,
                degree: degree,
                weights: weights.contains(where: { abs($0 - 1.0) > 1e-9 }) ? weights : nil,
                color: color
            )]
        }

        // Fallback to fit points
        if e.splineNFit > 0, let pts = e.splineFitPts {
            let count = Int(e.splineNFit)
            let vecs: [Vector3] = (0..<count).map { i in DWGImporter.toVector(pts[i]) }

            if vecs.count > 1 {
                return (0..<(vecs.count - 1)).map { i in
                    .line(start: vecs[i], end: vecs[i + 1], color: color)
                }
            }
        }

        return []
    }
}
