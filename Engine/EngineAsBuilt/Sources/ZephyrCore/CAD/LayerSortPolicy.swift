import Foundation

// =========================================================================
// MARK: - LayerSortPolicy
//
// AutoCAD-style layer sorting for the Layers panel: click a property
// to sort by it, click again to flip direction. Sort state is UI
// state (persisted in UserDefaults, never in the drawing), and the
// comparator always falls back to name so ordering is deterministic.
// Pure value logic — unit-testable without ImGui.
// =========================================================================

public enum LayerSortKey: String, CaseIterable, Sendable {
    case name
    case onOff
    case color
    case linetype
    case lineweight
    case opacity
    case plot
    case used

    public var displayName: String {
        switch self {
        case .name: return "Name"
        case .onOff: return "On/Off"
        case .color: return "Color"
        case .linetype: return "Linetype"
        case .lineweight: return "Lineweight"
        case .opacity: return "Opacity"
        case .plot: return "Plot"
        case .used: return "Used"
        }
    }
}

public struct LayerSortSettings: Equatable, Sendable {
    public var key: LayerSortKey
    public var ascending: Bool

    public init(key: LayerSortKey = .name, ascending: Bool = true) {
        self.key = key
        self.ascending = ascending
    }

    /// AutoCAD header-click behavior: same key flips direction,
    /// a new key starts ascending.
    public func selecting(_ newKey: LayerSortKey) -> LayerSortSettings {
        if newKey == key {
            return LayerSortSettings(key: key, ascending: !ascending)
        }
        return LayerSortSettings(key: newKey, ascending: true)
    }

    private static let keyDefaultsKey = "Zephyr.CAD.LayerSortKey"
    private static let dirDefaultsKey = "Zephyr.CAD.LayerSortAscending"

    public static func load() -> LayerSortSettings {
        let defaults = UserDefaults.standard
        let key = defaults.string(forKey: keyDefaultsKey)
            .flatMap(LayerSortKey.init(rawValue:)) ?? .name
        let ascending = defaults.object(forKey: dirDefaultsKey) == nil
            ? true : defaults.bool(forKey: dirDefaultsKey)
        return LayerSortSettings(key: key, ascending: ascending)
    }

    public func save() {
        UserDefaults.standard.set(key.rawValue, forKey: Self.keyDefaultsKey)
        UserDefaults.standard.set(ascending, forKey: Self.dirDefaultsKey)
    }

    /// Maps a LAYERSORT command token to a sort key.
    public static func key(forCommandToken token: String) -> LayerSortKey? {
        switch token.uppercased() {
        case "NAME":
            return .name
        case "ON", "ONOFF", "ON/OFF", "STATE", "STATUS", "VISIBLE", "VISIBILITY":
            return .onOff
        case "COLOR", "COLOUR", "ACI":
            return .color
        case "LINETYPE", "LTYPE", "LT":
            return .linetype
        case "LINEWEIGHT", "LWEIGHT", "WEIGHT", "LW":
            return .lineweight
        case "OPACITY", "TRANSPARENCY", "ALPHA":
            return .opacity
        case "PLOT", "PLOTTABLE":
            return .plot
        case "USED", "COUNT", "ENTITIES", "ENTITYCOUNT":
            return .used
        default:
            return nil
        }
    }

    /// Applies LAYERSORT command tokens, e.g. ["COLOR"], ["COLOR", "DESC"],
    /// ["DESC"], or ["REVERSE"]. A key token uses header-click behavior:
    /// selecting the current key toggles direction unless an explicit
    /// direction token follows. Returns nil if any token is unknown.
    public func applyingCommandTokens(_ tokens: [String]) -> LayerSortSettings? {
        var result = self
        for rawToken in tokens {
            let token = rawToken.uppercased()
            if let newKey = Self.key(forCommandToken: token) {
                result = result.selecting(newKey)
            } else if token == "ASC" || token == "ASCENDING" || token == "UP" {
                result.ascending = true
            } else if token == "DESC" || token == "DESCENDING" || token == "DOWN" {
                result.ascending = false
            } else if token == "REVERSE" || token == "TOGGLE" || token == "FLIP" {
                result.ascending.toggle()
            } else {
                return nil
            }
        }
        return result
    }
}

public enum LayerSortPolicy {

    /// Sort layers by the settings. `entityCounts` (by layer handle)
    /// only feeds the Used key. Boolean-ish keys sort "active first"
    /// when ascending (On before Off, Plot before No-Plot, Used
    /// before Unused) — the order you scan a palette for.
    public static func sorted(
        _ layers: [Layer],
        entityCounts: [UUID: Int] = [:],
        settings: LayerSortSettings
    ) -> [Layer] {
        layers.sorted { a, b in
            let order = compare(a, b, key: settings.key, entityCounts: entityCounts)
            if order != 0 {
                return settings.ascending ? order < 0 : order > 0
            }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    private static func compare(
        _ a: Layer, _ b: Layer, key: LayerSortKey, entityCounts: [UUID: Int]
    ) -> Int {
        func byDouble(_ x: Double, _ y: Double) -> Int {
            x == y ? 0 : (x < y ? -1 : 1)
        }
        func byBoolActiveFirst(_ x: Bool, _ y: Bool) -> Int {
            x == y ? 0 : (x ? -1 : 1)
        }
        switch key {
        case .name:
            let order = a.name.localizedCaseInsensitiveCompare(b.name)
            return order == .orderedSame ? 0 : (order == .orderedAscending ? -1 : 1)
        case .onOff:
            return byBoolActiveFirst(a.isVisible, b.isVisible)
        case .color:
            let x = DXFColorTable.rgbaToACI(a.color)
            let y = DXFColorTable.rgbaToACI(b.color)
            return x == y ? 0 : (x < y ? -1 : 1)
        case .linetype:
            let order = a.lineType.localizedCaseInsensitiveCompare(b.lineType)
            return order == .orderedSame ? 0 : (order == .orderedAscending ? -1 : 1)
        case .lineweight:
            return byDouble(a.lineWeight, b.lineWeight)
        case .opacity:
            return byDouble(a.opacity, b.opacity)
        case .plot:
            return byBoolActiveFirst(a.isPlottable, b.isPlottable)
        case .used:
            let x = (entityCounts[a.handle] ?? 0) > 0
            let y = (entityCounts[b.handle] ?? 0) > 0
            return byBoolActiveFirst(x, y)
        }
    }

    /// Per-layer entity counts in one pass (Used key + future filters).
    public static func entityCounts(in document: CADDocument) -> [UUID: Int] {
        var counts: [UUID: Int] = [:]
        for entity in document.allEntities {
            if entity.xdata["dxf.viewport.projected"] != nil { continue }
            counts[entity.layerID, default: 0] += 1
        }
        return counts
    }
}
