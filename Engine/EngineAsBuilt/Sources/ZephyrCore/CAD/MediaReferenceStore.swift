import Foundation

// =========================================================================
// MARK: - MediaReferenceStore
//
// Per-tab runtime state for referenced images and PDF underlays
// (ATTACH): load status, found-at path, file stamp, and decoded
// pixels. Sibling to XrefRuntimeStore, sharing its status vocabulary
// and path resolver. Nothing here is snapshotted for undo or saved —
// the saved form is the CADImageDefinition/CADPdfDefinition.
// =========================================================================

public enum MediaReferenceKind: String, Sendable, Equatable {
    case image
    case pdf

    public var displayName: String {
        switch self {
        case .image: return "Image"
        case .pdf: return "PDF Underlay"
        }
    }
}

public final class MediaReferenceStore: @unchecked Sendable {

    public struct Entry: Sendable {
        public var kind: MediaReferenceKind
        public var name: String
        public var savedPath: String
        public var pageNumber: Int
        public var status: XrefStatus = .unloaded
        public var statusDetail: String?
        public var foundAtPath: String?
        public var fileModifiedAt: Date?
        public var fileSize: Int?
        /// Decoded pixels, keyed by definition name. Nil unless loaded.
        public var asset: CADImageAsset?
        /// Real PDF page size in points once rendered.
        public var pageWidthPoints: Double?
        public var pageHeightPoints: Double?
        public var userUnloaded: Bool = false

        public init(kind: MediaReferenceKind, name: String, savedPath: String, pageNumber: Int = 1) {
            self.kind = kind
            self.name = name
            self.savedPath = savedPath
            self.pageNumber = pageNumber
        }
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    public var searchPaths: [String] = []

    public init() {
        apply(settings: UserSettings.load())
    }

    public func apply(settings: UserSettings) {
        searchPaths = settings.xrefSearchPaths
    }

    public func entry(forName name: String) -> Entry? {
        lock.lock(); defer { lock.unlock() }
        return entries[name]
    }

    public func allEntries() -> [Entry] {
        lock.lock(); defer { lock.unlock() }
        return entries.values.sorted { $0.name < $1.name }
    }

    @discardableResult
    public func ensureEntry(
        kind: MediaReferenceKind, name: String, savedPath: String, pageNumber: Int = 1
    ) -> Entry {
        lock.lock(); defer { lock.unlock() }
        if var existing = entries[name] {
            existing.kind = kind
            existing.savedPath = savedPath
            existing.pageNumber = pageNumber
            entries[name] = existing
            return existing
        }
        let entry = Entry(kind: kind, name: name, savedPath: savedPath, pageNumber: pageNumber)
        entries[name] = entry
        return entry
    }

    public func updateEntry(forName name: String, _ mutate: (inout Entry) -> Void) {
        lock.lock(); defer { lock.unlock() }
        guard var entry = entries[name] else { return }
        mutate(&entry)
        entries[name] = entry
    }

    public func removeEntry(forName name: String) {
        lock.lock(); defer { lock.unlock() }
        entries.removeValue(forKey: name)
    }

    public func status(forName name: String) -> XrefStatus {
        entry(forName: name)?.status ?? .unloaded
    }

    /// Loaded runtime assets by definition name (render merge).
    public func loadedAssets() -> [String: CADImageAsset] {
        lock.lock(); defer { lock.unlock() }
        var result: [String: CADImageAsset] = [:]
        for entry in entries.values {
            if entry.status.hasShadowGeometry, let asset = entry.asset {
                result[entry.name] = asset
            }
        }
        return result
    }

    /// Total decoded pixels currently held (memory budget checks).
    public func totalDecodedPixels() -> Int {
        lock.lock(); defer { lock.unlock() }
        return entries.values.reduce(0) { sum, entry in
            guard let asset = entry.asset else { return sum }
            return sum + asset.pixelWidth * asset.pixelHeight
        }
    }
}
