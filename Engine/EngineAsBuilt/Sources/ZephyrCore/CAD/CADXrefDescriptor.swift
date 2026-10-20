import Foundation

// =========================================================================
// MARK: - CADXrefDescriptor
//
// Marks a CADBlock as an external reference (xref): its saved path and
// whether it is an overlay. Runtime state (loaded/unloaded, found-at
// path, shadow geometry) lives in the per-tab XrefRuntimeStore, never
// here, so undo snapshots stay cheap and saves never embed geometry.
// =========================================================================

public struct CADXrefDescriptor: Hashable, Sendable, Codable {
    /// Path exactly as saved in the host file (DXF BLOCK group 1).
    public var savedPath: String
    /// Overlay (DXF flag bit 8) vs attachment (bit 4 only).
    public var isOverlay: Bool

    public init(savedPath: String, isOverlay: Bool = false) {
        self.savedPath = savedPath
        self.isOverlay = isOverlay
    }

    /// DXF BLOCK / BLOCK_RECORD group-70 flag bits.
    public enum Flags {
        public static let anonymous = 1
        public static let hasNonConstantAttributeDefinitions = 2
        public static let xref = 4
        public static let xrefOverlay = 8
        public static let externallyDependent = 16
        public static let resolvedExternal = 32
        public static let referencedExternal = 64
    }

    /// Build from raw DXF BLOCK data; nil when the xref bit is clear.
    public init?(dxfFlags: Int, xrefPath: String) {
        guard dxfFlags & Flags.xref != 0 else { return nil }
        self.savedPath = xrefPath
        self.isOverlay = dxfFlags & Flags.xrefOverlay != 0
    }

    /// How `savedPath` was written (AutoCAD full / relative / no path).
    public enum PathKind: String, Sendable {
        case absolute, relative, none
    }

    public var pathKind: PathKind {
        Self.pathKind(of: savedPath)
    }

    public static func pathKind(of path: String) -> PathKind {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .none }
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("\\\\") { return .absolute }
        // Windows drive-rooted: "C:\..." or "C:/...".
        let scalars = Array(trimmed.unicodeScalars)
        if scalars.count >= 3,
           CharacterSet.letters.contains(scalars[0]),
           scalars[1] == ":",
           scalars[2] == "\\" || scalars[2] == "/" {
            return .absolute
        }
        if trimmed.contains("/") || trimmed.contains("\\") { return .relative }
        return .none
    }
}

extension CADBlock {
    /// True when this block definition is an external reference.
    public var isXref: Bool { xrefDescriptor != nil }

    /// Group-70 flags to write for this block: stored `dxfFlags` with the
    /// xref/overlay bits driven by the descriptor when present.
    public var effectiveDXFFlags: Int {
        var flags = dxfFlags
        if let descriptor = xrefDescriptor {
            flags |= CADXrefDescriptor.Flags.xref
            if descriptor.isOverlay {
                flags |= CADXrefDescriptor.Flags.xrefOverlay
            } else {
                flags &= ~CADXrefDescriptor.Flags.xrefOverlay
            }
        }
        return flags
    }
}
