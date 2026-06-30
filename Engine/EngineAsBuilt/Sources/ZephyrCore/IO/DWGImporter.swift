import Foundation
import CDWG

// =========================================================================
// MARK: - DWGImporter
//
// Parses AutoCAD DWG (Drawing) files via the LibreDWG C bridge and produces
// Zephyr CAD document entities. Supports DWG versions R13 through latest.
//
// The importer produces layers, blocks, and entities arrays that are
// consumed by CADDocument.importLayersBlocksEntities().

// =========================================================================
// MARK: - DWGImportError
// =========================================================================

public enum DWGImportError: Error, LocalizedError {
    case parseFailed(String)

    public var errorDescription: String? {
        switch self {
        case .parseFailed(let msg): return "DWG parse failed: \(msg)"
        }
    }
}

// =========================================================================
// MARK: - DWGImporter
// =========================================================================

/// Converts DWG data (via the LibreDWG C bridge) into the engine's
/// native CAD types: `Layer`, `CADBlock`, `CADPrimitive`, and `CADEntity`.
public enum DWGImporter {

    // MARK: - Public API

    /// Parse a DWG file at `filePath` and return native CAD types.
    /// - Returns: Tuple of layers, blocks, entities, text style fonts, and linetype patterns.
    @MainActor
    public static func importDWG(filePath: String) throws -> (layers: [Layer], blocks: [CADBlock], entities: [CADEntity], textStyleFonts: [String: String], linetypePatterns: [String: [Double]]) {

        var result = DWG_Result()
        let ok = filePath.withCString { pathPtr in
            dwg_bridge_read(pathPtr, &result)
        }

        guard ok != 0, result.success != 0 else {
            let msg = result.errorMessage.map { String(cString: $0) } ?? "Unknown DWG parse error"
            defer { dwg_bridge_result_free(&result) }
            throw DWGImportError.parseFailed(msg)
        }

        defer { dwg_bridge_result_free(&result) }

        // Convert layers
        let layerCount = Int(result.layerCount)
        var layers: [Layer] = []
        var layerLookup: [String: UUID] = [:]  // name → handle for later lookup
        if let layerPtr = result.layers {
            for i in 0..<layerCount {
                let l = layerPtr[i]
                let name = l.name.map { String(cString: $0) } ?? "Layer \(i)"
                let color = DWGImporter.dwgColorToRGBA(aci: l.color, rgb: l.colorRGB)
                let lineWeight = l.lineWeight > 0 ? l.lineWeight : 0.25
                var layer = Layer(name: name, lineWeight: lineWeight, color: color)
                layer.isVisible = l.on != 0 && l.frozen == 0
                if let ltName = l.lineTypeName {
                    layer.lineType = String(cString: ltName)
                }
                layers.append(layer)
                layerLookup[name] = layer.handle
            }
        }

        // Collect block definitions
        let blockCount = Int(result.blockCount)
        var blocks: [CADBlock] = []
        var blockLookup: [String: UUID] = [:]  // name → handle
        if let blockPtr = result.blocks {
            for i in 0..<blockCount {
                let b = blockPtr[i]
                let name = b.name.map { String(cString: $0) } ?? "Block \(i)"
                let block = CADBlock(name: name, geometry: [])
                blocks.append(block)
                blockLookup[name] = block.handle
            }
        }

        // Convert entities
        let entityCount = Int(result.entityCount)
        var entities: [CADEntity] = []
        if let entityPtr = result.entities {
            for i in 0..<entityCount {
                let e = entityPtr[i]
                let layerName = e.layerName.map { String(cString: $0) } ?? "0"
                let layerID = layerLookup[layerName] ?? layers.first?.handle ?? UUID()

                var xdata: [String: XDataValue] = [:]
                if e.color != 256 && e.color > 0 {
                    xdata["dxf.color"] = .int(Int(e.color))
                }
                if e.lineWeight > 0 {
                    xdata["dxf.lineWeight"] = .double(e.lineWeight)
                }

                // Find block reference
                let blockID: UUID? = e.blockName.map { String(cString: $0) }.flatMap { blockLookup[$0] }

                let primitives = DWGEntityConverter.convertEntityToPrimitives(e)

                var entity = CADEntity(
                    layerID: layerID,
                    blockID: blockID,
                    localGeometry: blockID == nil ? primitives : nil,
                    transform: .identity,
                    xdata: xdata
                )

                // INSERT transforms
                if e.type == DWG_ET_INSERT {
                    var t = Transform3D.identity
                    t.position = DWGImporter.toVector(e.basePoint)
                    t.scale = Vector3(x: e.xscale, y: e.yscale, z: e.zscale)
                    t.rotation = e.insertAngle
                    entity.transform = t
                }

                entities.append(entity)
            }
        }

        let textStyleFonts: [String: String] = [:]
        let linetypePatterns: [String: [Double]] = [:]

        return (layers, blocks, entities, textStyleFonts, linetypePatterns)
    }

    // MARK: - Helpers

    /// Convert a DWG_Coord to a Vector3
    internal static func toVector(_ c: DWG_Coord) -> Vector3 {
        return Vector3(x: c.x, y: c.y, z: c.z)
    }

    /// Convert ACI color + optional true-color RGB to engine ColorRGBA.
    internal static func dwgColorToRGBA(aci: Int32, rgb: Int32) -> ColorRGBA {
        if rgb >= 0 {
            let r = UInt8((rgb >> 16) & 0xFF)
            let g = UInt8((rgb >> 8) & 0xFF)
            let b = UInt8(rgb & 0xFF)
            return ColorRGBA(r: r, g: g, b: b)
        }
        // Use DXF color table for ACI
        return DXFColorTable.aciToRGBA(aci, color24: -1)
    }
}
