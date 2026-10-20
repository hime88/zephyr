import Foundation

// =========================================================================
// MARK: - CADModelSpaceBaker
//
// Bakes a set of model-space entities into block-local geometry with
// per-primitive styles and xdata preserved. Shared by:
//   - INSERT of a file (drawing-file insertion as a new block)
//   - BLOCK (createBlockFromEntities — previously geometry-only)
//   - Xref shadow baking (referenced model space, read-only in host)
//
// Loose entities carry their draw properties on the entity itself
// (layerID + dxf.* xdata); baking synthesizes a CADPrimitiveStyle per
// primitive from those. Block-referenced entities carry their block's
// styles/xdata through the instance transform unchanged, so ByBlock
// resolution keeps working against the eventual inserting entity.
// =========================================================================

public enum CADModelSpaceBaker {

    public struct Baked: Sendable {
        public var geometry: [CADPrimitive]
        public var primitiveStyles: [Int: CADPrimitiveStyle]
        public var primitiveXData: [Int: [String: XDataValue]]

        public init(
            geometry: [CADPrimitive] = [],
            primitiveStyles: [Int: CADPrimitiveStyle] = [:],
            primitiveXData: [Int: [String: XDataValue]] = [:]
        ) {
            self.geometry = geometry
            self.primitiveStyles = primitiveStyles
            self.primitiveXData = primitiveXData
        }
    }

    /// Bake `entities` into block-local space whose origin is `basePoint`
    /// in source world space (the drawing's $INSBASE, or a block center).
    /// - Parameters:
    ///   - entities: Model-space entities (any order; preserved).
    ///   - layers: Layers of the source document (for layer names).
    ///   - blocks: Block definitions of the source document.
    ///   - basePoint: Subtracted from world geometry (insertion base).
    public static func bake(
        entities: [CADEntity],
        layers: [Layer],
        blocks: [CADBlock],
        basePoint: Vector3 = .zero
    ) -> Baked {
        let layerNameByID = Dictionary(uniqueKeysWithValues: layers.map { ($0.handle, $0.name) })
        let blockByID = Dictionary(uniqueKeysWithValues: blocks.map { ($0.handle, $0) })
        let unbase = Transform3D.translated(by: Vector3(x: -basePoint.x, y: -basePoint.y, z: -basePoint.z))

        var result = Baked()
        for entity in entities {
            let toLocal = unbase.multiplying(by: entity.transform)
            if let blockID = entity.blockID, let block = blockByID[blockID] {
                if let array = entity.arrayData {
                    // Expand associative/MINSERT arrays into their
                    // evaluated instances (path arrays use the cached
                    // path; the baker has no live document to resolve).
                    for instance in array.evaluatedInstances() {
                        append(
                            geometry: block.geometry,
                            styles: block.primitiveStyles,
                            xdata: block.primitiveXData,
                            transform: toLocal.multiplying(by: instance.transform),
                            into: &result)
                    }
                } else {
                    append(
                        geometry: block.geometry,
                        styles: block.primitiveStyles,
                        xdata: block.primitiveXData,
                        transform: toLocal,
                        into: &result)
                }
            } else if let geometry = entity.localGeometry, !geometry.isEmpty {
                let style = synthesizedStyle(for: entity, layerNameByID: layerNameByID)
                var styles: [Int: CADPrimitiveStyle] = [:]
                var xdata: [Int: [String: XDataValue]] = [:]
                for index in geometry.indices {
                    styles[index] = style
                    if !entity.xdata.isEmpty { xdata[index] = entity.xdata }
                }
                append(geometry: geometry, styles: styles, xdata: xdata,
                       transform: toLocal, into: &result)
            }
        }
        return result
    }

    /// Default INSERT scale converting source drawing units into host
    /// units (1:1 when either side is unspecified).
    public static func unitScale(from source: CADUnit?, to host: CADUnit) -> Double {
        guard let source else { return 1.0 }
        return source.scaleToMM * host.scaleFromMM
    }

    // MARK: - Internals

    private static func append(
        geometry: [CADPrimitive],
        styles: [Int: CADPrimitiveStyle],
        xdata: [Int: [String: XDataValue]],
        transform: Transform3D,
        into result: inout Baked
    ) {
        let offset = result.geometry.count
        result.geometry.append(
            contentsOf: CADGeometryMath.transformPrimitives(geometry, by: transform))
        for (index, style) in styles { result.primitiveStyles[offset + index] = style }
        for (index, xd) in xdata where !xd.isEmpty { result.primitiveXData[offset + index] = xd }
    }

    /// Entity-level draw properties (layer + dxf.* xdata, the same keys
    /// the renderer reads for loose entities) as a primitive style.
    private static func synthesizedStyle(
        for entity: CADEntity, layerNameByID: [UUID: String]
    ) -> CADPrimitiveStyle {
        var style = CADPrimitiveStyle(layerName: layerNameByID[entity.layerID] ?? "0")
        if case .string(let hex) = entity.xdata["dxf.color"] {
            style.color = ColorRGBA(hex: hex)
        }
        if case .string(let lineType) = entity.xdata["dxf.lineType"] {
            style.lineType = lineType
        }
        if case .double(let lineWeight) = entity.xdata["dxf.lineWeight"], lineWeight >= 0 {
            style.lineWeight = lineWeight
        }
        if case .double(let scale) = entity.xdata["dxf.lineTypeScale"] {
            style.lineTypeScale = scale
        }
        if case .double(let opacity) = entity.xdata["dxf.opacity"] {
            style.opacity = max(0.0, min(1.0, opacity))
        }
        return style
    }
}
