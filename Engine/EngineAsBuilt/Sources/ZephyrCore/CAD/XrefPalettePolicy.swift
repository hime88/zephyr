import Foundation

// =========================================================================
// MARK: - XrefPalettePolicy
//
// View-model derivation for the External References palette: rows,
// tree children, derived statuses (incl. Unreferenced), and per-row
// action enablement. Pure and unit-testable — the ImGui palette only
// renders what this returns.
// =========================================================================

public enum XrefPalettePolicy {

    public struct ChildRow: Equatable, Sendable {
        public var name: String
        public var statusText: String
        public var detail: String?
        public var children: [ChildRow]
    }

    public struct Row: Equatable, Sendable {
        public var blockHandle: UUID
        public var name: String
        public var status: XrefStatus
        public var statusDetail: String?
        public var isUnreferenced: Bool
        public var isOverlay: Bool
        public var savedPath: String
        public var foundAtPath: String?
        public var fileSize: Int?
        public var fileModifiedAt: Date?
        public var instanceCount: Int
        public var children: [ChildRow]

        public var statusText: String {
            if instanceCount == 0, status.hasShadowGeometry || status == .unloaded {
                return "Unreferenced"
            }
            return status.displayName
        }
        public var typeText: String { isOverlay ? "Overlay" : "Attachment" }
        public var canLoad: Bool { status == .unloaded || status == .notFound || status == .unresolved || status == .overBudget }
        public var canUnload: Bool { status.hasShadowGeometry }
        public var canReload: Bool { status != .loading }
        public var canOpen: Bool { foundAtPath != nil }
    }

    /// One O(entities) pass for instance counts across all view docs
    /// (paper projections share block handles; count each view's
    /// instances once per handle set to avoid double-counting sheets).
    public static func instanceCounts(documents: [CADDocument]) -> [UUID: Int] {
        var counts: [UUID: Int] = [:]
        var projectedSeen: Set<UUID> = []
        for doc in documents {
            for entity in doc.allEntities {
                guard let bid = entity.blockID else { continue }
                // Projected paper copies duplicate model INSERTs; they
                // carry fresh handles, so count model documents fully
                // and skip entities flagged as projections.
                if entity.xdata["dxf.viewport.projected"] != nil { continue }
                if !projectedSeen.insert(entity.handle).inserted { continue }
                counts[bid, default: 0] += entity.arrayData != nil
                    ? max(1, entity.arrayData?.evaluatedInstances().count ?? 1) : 1
            }
        }
        return counts
    }

    public static func rows(
        store: XrefRuntimeStore, documents: [CADDocument]
    ) -> [Row] {
        let counts = instanceCounts(documents: documents)
        var rows: [Row] = []
        var seen = Set<UUID>()
        for doc in documents {
            for block in doc.allBlocks where block.isXref {
                guard seen.insert(block.handle).inserted,
                      let descriptor = block.xrefDescriptor else { continue }
                let entry = store.entry(for: block.handle)
                rows.append(Row(
                    blockHandle: block.handle,
                    name: block.name,
                    status: entry?.status ?? .unloaded,
                    statusDetail: entry?.statusDetail,
                    isUnreferenced: (counts[block.handle] ?? 0) == 0,
                    isOverlay: descriptor.isOverlay,
                    savedPath: descriptor.savedPath,
                    foundAtPath: entry?.foundAtPath,
                    fileSize: entry?.fileSize,
                    fileModifiedAt: entry?.fileModifiedAt,
                    instanceCount: counts[block.handle] ?? 0,
                    children: (entry?.children ?? []).map(childRow)))
            }
        }
        return rows.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func childRow(_ info: XrefChildInfo) -> ChildRow {
        ChildRow(
            name: info.blockName,
            statusText: info.status.displayName,
            detail: info.detail,
            children: info.children.map(childRow))
    }

    // MARK: - Media rows (ATTACH)

    public struct MediaRow: Equatable, Sendable {
        public var name: String
        public var kind: MediaReferenceKind
        public var status: XrefStatus
        public var statusDetail: String?
        public var savedPath: String
        public var foundAtPath: String?
        public var fileSize: Int?
        public var fileModifiedAt: Date?
        public var instanceCount: Int
        public var pageNumber: Int

        public var statusText: String {
            if instanceCount == 0, status.hasShadowGeometry || status == .unloaded {
                return "Unreferenced"
            }
            return status.displayName
        }
        public var typeText: String {
            kind == .pdf ? "PDF p\(pageNumber)" : kind.displayName
        }
        public var canLoad: Bool { status == .unloaded || status == .notFound || status == .unresolved || status == .overBudget }
        public var canUnload: Bool { status.hasShadowGeometry }
        public var canReload: Bool { status != .loading }
        public var canEmbed: Bool { status.hasShadowGeometry }
    }

    public static func mediaRows(
        store: MediaReferenceStore, documents: [CADDocument]
    ) -> [MediaRow] {
        // One pass over entities for instance counts by definition name.
        var counts: [String: Int] = [:]
        var seenEntities: Set<UUID> = []
        for doc in documents {
            for entity in doc.allEntities {
                if entity.xdata["dxf.viewport.projected"] != nil { continue }
                if !seenEntities.insert(entity.handle).inserted { continue }
                for prim in entity.localGeometry ?? [] {
                    if let name = prim.imageReferenceName {
                        counts[name, default: 0] += 1
                    }
                }
            }
        }
        var rows: [MediaRow] = []
        var seenNames = Set<String>()
        for doc in documents {
            for def in doc.imageDefinitions.values
            where seenNames.insert(def.name.uppercased()).inserted {
                let entry = store.entry(forName: def.name)
                rows.append(MediaRow(
                    name: def.name, kind: .image,
                    status: entry?.status ?? .unloaded,
                    statusDetail: entry?.statusDetail,
                    savedPath: def.savedPath,
                    foundAtPath: entry?.foundAtPath,
                    fileSize: entry?.fileSize,
                    fileModifiedAt: entry?.fileModifiedAt,
                    instanceCount: counts[def.name] ?? 0,
                    pageNumber: 1))
            }
            for def in doc.pdfDefinitions.values
            where seenNames.insert(def.name.uppercased()).inserted {
                let entry = store.entry(forName: def.name)
                rows.append(MediaRow(
                    name: def.name, kind: .pdf,
                    status: entry?.status ?? .unloaded,
                    statusDetail: entry?.statusDetail,
                    savedPath: def.savedPath,
                    foundAtPath: entry?.foundAtPath,
                    fileSize: entry?.fileSize,
                    fileModifiedAt: entry?.fileModifiedAt,
                    instanceCount: counts[def.name] ?? 0,
                    pageNumber: def.pageNumber))
            }
        }
        return rows.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Any media reference needing attention (status-bar indicator).
    public static func hasMediaWarning(store: MediaReferenceStore) -> Bool {
        store.allEntries().contains {
            switch $0.status {
            case .notFound, .unresolved, .needsReload, .overBudget:
                return true
            default:
                return false
            }
        }
    }

    /// Any xref needing attention (status-bar indicator).
    public static func hasWarning(store: XrefRuntimeStore) -> Bool {
        store.allEntries().contains {
            switch $0.entry.status {
            case .notFound, .unresolved, .needsReload, .circular, .overBudget, .orphaned:
                return true
            default:
                return false
            }
        }
    }
}
