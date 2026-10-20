import Foundation

// =========================================================================
// MARK: - XrefRuntimeStore
//
// Per-tab runtime state for external references: load status, found-at
// path, file stamp, and loaded ("shadow") geometry. One store per
// DocumentTab, shared by every drawing-view document in the tab.
// Nothing here is snapshotted for undo or written to disk directly —
// the saved form of an xref is its CADXrefDescriptor on the block.
// =========================================================================

public enum XrefStatus: String, Sendable, Equatable {
    case loading
    case loaded
    case needsReload
    case unloaded
    case notFound
    case unresolved
    case orphaned
    case circular
    case overBudget

    public var displayName: String {
        switch self {
        case .loading: return "Loading…"
        case .loaded: return "Loaded"
        case .needsReload: return "Needs Reloading"
        case .unloaded: return "Unloaded"
        case .notFound: return "Not Found"
        case .unresolved: return "Unresolved"
        case .orphaned: return "Orphaned"
        case .circular: return "Circular"
        case .overBudget: return "Over Budget"
        }
    }

    public var hasShadowGeometry: Bool { self == .loaded || self == .needsReload }
}

/// A nested xref as seen from its parent xref (palette tree metadata;
/// nested content is baked into the parent's shadow geometry).
public struct XrefChildInfo: Sendable, Equatable {
    public var blockName: String
    public var savedPath: String
    public var isOverlay: Bool
    public var status: XrefStatus
    public var detail: String?
    public var children: [XrefChildInfo]

    public init(
        blockName: String, savedPath: String, isOverlay: Bool,
        status: XrefStatus, detail: String? = nil, children: [XrefChildInfo] = []
    ) {
        self.blockName = blockName
        self.savedPath = savedPath
        self.isOverlay = isOverlay
        self.status = status
        self.detail = detail
        self.children = children
    }
}

/// Tunable loading policy (the transferable half of XLOADCTL demand
/// loading: explicit caps instead of DWG index-based partial loads).
public struct XrefLoadLimits: Sendable, Equatable {
    public var maxLoadedXrefs: Int
    public var maxNestingDepth: Int
    public var maxTotalPrimitives: Int

    public init(
        maxLoadedXrefs: Int = 32,
        maxNestingDepth: Int = 16,
        maxTotalPrimitives: Int = 5_000_000
    ) {
        self.maxLoadedXrefs = maxLoadedXrefs
        self.maxNestingDepth = maxNestingDepth
        self.maxTotalPrimitives = maxTotalPrimitives
    }
}

/// Xref system variables backed by UserSettings (single source of
/// truth shared by the palette, commands, loader, and Lisp getvar/
/// setvar). Reads are file-backed but only happen on user actions and
/// the 5-minute poll — never per frame.
public enum XrefSysvars {
    // In-memory copy so set→get stays coherent even when the settings
    // file is not writable (sandboxed tests); disk save is best-effort.
    private static let lock = NSLock()
    // Guarded by `lock` on every access.
    private nonisolated(unsafe) static var cachedSettings: UserSettings?

    private static func settings() -> UserSettings {
        lock.lock()
        defer { lock.unlock() }
        if let cachedSettings { return cachedSettings }
        let loaded = UserSettings.load()
        cachedSettings = loaded
        return loaded
    }

    private static func updateSettings(_ mutate: (inout UserSettings) -> Void) {
        lock.lock()
        var s = cachedSettings ?? UserSettings.load()
        mutate(&s)
        cachedSettings = s
        lock.unlock()
        s.save()
    }

    public static var refPathType: Int {
        get { settings().xrefRefPathType }
        set { updateSettings { $0.xrefRefPathType = newValue } }
    }
    public static var bindType: Int {
        get { settings().xrefBindType }
        set { updateSettings { $0.xrefBindType = newValue } }
    }
    public static var fadePercent: Int {
        get { settings().xrefFadePercent }
        set { updateSettings { $0.xrefFadePercent = newValue } }
    }
    /// VISRETAIN (not a UserSettings field; UserDefaults like XCLIPFRAME).
    public static var visRetain: Int {
        get {
            UserDefaults.standard.object(forKey: "Zephyr.CAD.VISRETAIN") == nil
                ? 1 : UserDefaults.standard.integer(forKey: "Zephyr.CAD.VISRETAIN")
        }
        set { UserDefaults.standard.set(newValue, forKey: "Zephyr.CAD.VISRETAIN") }
    }
    public static var xrefNotify: Int {
        get {
            UserDefaults.standard.object(forKey: "Zephyr.CAD.XREFNOTIFY") == nil
                ? 1 : UserDefaults.standard.integer(forKey: "Zephyr.CAD.XREFNOTIFY")
        }
        set { UserDefaults.standard.set(newValue, forKey: "Zephyr.CAD.XREFNOTIFY") }
    }
    /// 0 = load everything ignoring caps; 1/2 = capped copy-loading.
    public static var xloadCtl: Int {
        get {
            UserDefaults.standard.object(forKey: "Zephyr.CAD.XLOADCTL") == nil
                ? 2 : UserDefaults.standard.integer(forKey: "Zephyr.CAD.XLOADCTL")
        }
        set { UserDefaults.standard.set(newValue, forKey: "Zephyr.CAD.XLOADCTL") }
    }
}

public final class XrefRuntimeStore: @unchecked Sendable {

    public struct Entry: Sendable {
        public var descriptor: CADXrefDescriptor
        public var blockName: String
        public var status: XrefStatus = .unloaded
        public var statusDetail: String?
        public var foundAtPath: String?
        public var canonicalPath: String?
        public var fileModifiedAt: Date?
        public var fileSize: Int?
        /// Baked shadow block (same handle/name as the descriptor block,
        /// dependent-symbol names already rewritten). Nil unless loaded.
        public var shadow: CADBlock?
        /// Local spatial grid over the shadow geometry (large blocks).
        public var grid: CADBlockSpatialGrid?
        public var children: [XrefChildInfo] = []
        /// Set when the user explicitly unloads; cleared on load.
        public var userUnloaded: Bool = false

        public init(descriptor: CADXrefDescriptor, blockName: String) {
            self.descriptor = descriptor
            self.blockName = blockName
        }
    }

    private let lock = NSLock()
    private var entries: [UUID: Entry] = [:]
    /// Parsed-file cache keyed by canonical path (validated by stamp).
    private var importCache: [String: (modifiedAt: Date?, fileSize: Int?, result: DXFImportResult)] = [:]

    public var limits = XrefLoadLimits()
    public var searchPaths: [String] = []

    public init() {
        apply(settings: UserSettings.load())
    }

    public func apply(settings: UserSettings) {
        limits = XrefLoadLimits(
            maxLoadedXrefs: max(1, settings.xrefMaxLoaded),
            maxNestingDepth: max(1, settings.xrefMaxDepth),
            maxTotalPrimitives: max(1, settings.xrefMaxPrimitives))
        searchPaths = settings.xrefSearchPaths
    }

    // MARK: - Entry access (lock-guarded)

    public func entry(for blockHandle: UUID) -> Entry? {
        lock.lock(); defer { lock.unlock() }
        return entries[blockHandle]
    }

    public func allEntries() -> [(handle: UUID, entry: Entry)] {
        lock.lock(); defer { lock.unlock() }
        return entries.map { ($0.key, $0.value) }
            .sorted { $0.entry.blockName < $1.entry.blockName }
    }

    @discardableResult
    public func ensureEntry(
        for blockHandle: UUID, descriptor: CADXrefDescriptor, blockName: String
    ) -> Entry {
        lock.lock(); defer { lock.unlock() }
        if var existing = entries[blockHandle] {
            existing.descriptor = descriptor
            existing.blockName = blockName
            entries[blockHandle] = existing
            return existing
        }
        let entry = Entry(descriptor: descriptor, blockName: blockName)
        entries[blockHandle] = entry
        return entry
    }

    public func updateEntry(for blockHandle: UUID, _ mutate: (inout Entry) -> Void) {
        lock.lock(); defer { lock.unlock() }
        guard var entry = entries[blockHandle] else { return }
        mutate(&entry)
        entries[blockHandle] = entry
    }

    public func removeEntry(for blockHandle: UUID) {
        lock.lock(); defer { lock.unlock() }
        entries.removeValue(forKey: blockHandle)
    }

    /// Loaded shadow block for display-side geometry resolution.
    public func shadowBlock(for blockHandle: UUID) -> CADBlock? {
        lock.lock(); defer { lock.unlock() }
        guard let entry = entries[blockHandle], entry.status.hasShadowGeometry else { return nil }
        return entry.shadow
    }

    public func spatialGrid(for blockHandle: UUID) -> CADBlockSpatialGrid? {
        lock.lock(); defer { lock.unlock() }
        guard let entry = entries[blockHandle], entry.status.hasShadowGeometry else { return nil }
        return entry.grid
    }

    public func status(for blockHandle: UUID) -> XrefStatus? {
        entry(for: blockHandle)?.status
    }

    /// (loaded xref count, total loaded primitives) across root entries.
    public func loadTotals() -> (count: Int, primitives: Int) {
        lock.lock(); defer { lock.unlock() }
        var count = 0
        var primitives = 0
        for entry in entries.values where entry.status.hasShadowGeometry {
            count += 1
            primitives += entry.shadow?.geometry.count ?? 0
        }
        return (count, primitives)
    }

    public var unloadedHandles: Set<UUID> {
        lock.lock(); defer { lock.unlock() }
        return Set(entries.filter { $0.value.userUnloaded }.map(\.key))
    }

    // MARK: - Import cache

    func cachedImport(
        canonicalPath: String, modifiedAt: Date?, fileSize: Int?
    ) -> DXFImportResult? {
        lock.lock(); defer { lock.unlock() }
        guard let cached = importCache[canonicalPath],
              cached.modifiedAt == modifiedAt, cached.fileSize == fileSize
        else { return nil }
        return cached.result
    }

    func storeImport(
        canonicalPath: String, modifiedAt: Date?, fileSize: Int?, result: DXFImportResult
    ) {
        lock.lock(); defer { lock.unlock() }
        importCache[canonicalPath] = (modifiedAt, fileSize, result)
    }
}
