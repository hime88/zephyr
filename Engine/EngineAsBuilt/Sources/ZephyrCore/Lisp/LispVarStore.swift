import Foundation
import ZephyrLisp

// =========================================================================
// MARK: - Lisp System Variable Store (getvar/setvar)
// =========================================================================
//
// Three variable kinds:
//
// * LIVE reads reflect the drawing/command state on every getvar (CLAYER,
//   UNDOCTL, CMDNAMES). CLAYER is also live on write (switches the active
//   layer, erroring on unknown names like AutoCAD).
// * READONLY variables reject setvar (ACADVER, DATE, UNDOCTL, ...).
// * MEMORY variables persist per host instance with AutoCAD-compatible
//   defaults and light validation (ranges, known names).
//
// The store is a reference type owned by the CAD host; concurrent access
// serializes on the host's actor. Values cross isolation as LispValue.

@MainActor
final class LispVarStore: Sendable {
    private var memory: [String: LispValue] = LispVarStore.defaults

    // MARK: - Defaults

    private static let defaults: [String: LispValue] = [
        "ACADVER": .string("24.0 (Zephyr)"),
        "ANGBASE": .real(0),
        "ANGDIR": .int(0),
        "APERTURE": .int(10),
        "AUNITS": .int(0),
        "AUPREC": .int(0),
        "BLIPMODE": .int(0),
        "CECOLOR": .string("BYLAYER"),
        "CELTSCALE": .real(1),
        "CELTYPE": .string("BYLAYER"),
        "CHAMFERA": .real(0),
        "CHAMFERB": .real(0),
        "CMDECHO": .int(1),
        "CURSORSIZE": .int(5),
        "DATE": .real(2460600.5),
        "DIMSCALE": .real(1),
        "DWGNAME": .string("Drawing1.dxf"),
        "DWGPREFIX": .string(""),
        "DWGTITLED": .int(0),
        "ERRNO": .int(0),
        "EXPERT": .int(0),
        "EXTMAX": LispEntityAdapter.lispList([.real(1e12), .real(1e12), .real(0)]),
        "EXTMIN": LispEntityAdapter.lispList([.real(-1e12), .real(-1e12), .real(0)]),
        "FILEDIA": .int(1),
        "FILLETRAD": .real(0),
        "FILLMODE": .int(1),
        "GRIDMODE": .int(0),
        "HIGHLIGHT": .int(1),
        "INSUNITS": .int(0),
        "LASTANGLE": .real(0),
        "LOGINNAME": .string("zephyr"),
        "LTSCALE": .real(1),
        "LUNITS": .int(2),
        "LUPREC": .int(4),
        "LWDISPLAY": .int(0),
        "MEASUREMENT": .int(1),
        "MENUECHO": .int(0),
        "MIRRTEXT": .int(1),
        "NOMUTT": .int(0),
        "OFFSETDIST": .real(1),
        "ORTHOMODE": .int(0),
        "OSMODE": .int(0),
        "PDMODE": .int(0),
        "PDSIZE": .real(0),
        "PICKADD": .int(1),
        "PICKAUTO": .int(1),
        "PICKBOX": .int(3),
        "PICKDRAG": .int(0),
        "PICKFIRST": .int(1),
        "PLATFORM": .string("Zephyr"),
        "QTEXTMODE": .int(0),
        "REGENMODE": .int(1),
        "SKETCHINC": .real(0.1),
        "SNAPMODE": .int(0),
        "SPLINESEGS": .int(8),
        "TEXTSTYLE": .string("Standard"),
    ]

    private static let readOnly: Set<String> = [
        "ACADVER", "CMDNAMES", "DATE", "DWGNAME", "DWGPREFIX", "DWGTITLED",
        "ERRNO", "EXTMAX", "EXTMIN", "LASTANGLE", "LOGINNAME", "MILLISECS",
        "PLATFORM", "UNDOCTL", "VERSION",
    ]

    // MARK: - Access

    /// Reads a variable. Live variables consult the document/processor;
    /// everything else comes from memory. Returns nil for unknown names.
    func get(
        _ name: String, document: CADDocument, processor: CADCommandProcessor?
    ) -> LispValue? {
        switch name {
        case "CLAYER":
            guard let id = document.activeLayerID,
                  let layer = document.layer(for: id)
            else { return .string("0") }
            return .string(layer.name)
        case "UNDOCTL":
            return .int(document.undoManager.undoControlFlags)
        case "CMDNAMES":
            // Feature commands carry no registry name; legacy commands do.
            return .string(processor?.activeCommand ?? "")
        case "MILLISECS":
            return .int(Int(Date().timeIntervalSince1970 * 1000))
        case "LASTPOINT":
            return memory["LASTPOINT"] ?? .nilValue
        default:
            return memory[name]
        }
    }

    /// Writes a variable. Returns an error message for rejected writes
    /// (unknown name, read-only, validation failure), nil on success.
    /// Unknown names are rejected by the caller (setvar checks get first).
    func set(_ name: String, _ value: LispValue, document: CADDocument) -> String? {
        if Self.readOnly.contains(name) {
            return "cannot modify read-only system variable: \(name)"
        }
        switch name {
        case "CLAYER":
            guard case let .string(layerName) = value else {
                return "CLAYER requires a layer name string"
            }
            guard let layer = document.findLayer(named: layerName) else {
                return "unknown layer \"\(layerName)\""
            }
            document.activeLayerID = layer.handle
            return nil
        case "CECOLOR":
            switch value {
            case .string(let s) where ["BYLAYER", "BYBLOCK"].contains(s.uppercased()):
                store(name, .string(s.uppercased()))
                return nil
            case .int(let i) where (1...256).contains(i):
                store(name, value)
                return nil
            default:
                return "CECOLOR requires BYLAYER, BYBLOCK, or ACI 1..256"
            }
        case "LUNITS":
            guard case let .int(i) = value, (1...5).contains(i) else {
                return "LUNITS requires an integer 1..5"
            }
            store(name, value)
            return nil
        case "AUNITS":
            guard case let .int(i) = value, (0...4).contains(i) else {
                return "AUNITS requires an integer 0..4"
            }
            store(name, value)
            return nil
        case "TEXTSTYLE":
            guard case let .string(style) = value else {
                return "TEXTSTYLE requires a style name string"
            }
            guard document.textStyles[style] != nil else {
                return "unknown text style \"\(style)\""
            }
            store(name, value)
            return nil
        default:
            let known = memory[name] != nil || name == "LASTPOINT"
            guard known else { return nil } // Caller rejects unknown names.
            store(name, value)
            return nil
        }
    }

    private func store(_ name: String, _ value: LispValue) {
        memory[name] = value
    }
}
