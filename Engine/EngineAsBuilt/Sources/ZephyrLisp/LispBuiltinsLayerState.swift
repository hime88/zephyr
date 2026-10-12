// LayerStateBuiltins: Wave-C layerstate-* family (14). Snapshots live
// in the environment; the host supplies layer enumeration and on/off
// control. Viewport arguments are accepted and ignored (single
// viewport); only the on/off property exists on Zephyr layers, so mask
// bit 0 is the only effective bit and importfromdb (which needs a
// second drawing database) returns nil.
import Foundation

/// Captured per-layer properties. Grows with the Layer model.
public struct LispLayerProps: Sendable, Codable, Equatable {
    public var on: Bool

    public init(on: Bool) {
        self.on = on
    }
}

/// One named snapshot: layer on/off values plus the save mask.
public struct LispLayerState: Sendable, Codable, Equatable {
    public var name: String
    public var mask: Int
    public var layers: [String: LispLayerProps]

    public init(name: String, mask: Int, layers: [String: LispLayerProps]) {
        self.name = name
        self.mask = mask
        self.layers = layers
    }
}

enum LayerStateBuiltins {
    static let table: [String: LispBuiltin] = [
        "LAYERSTATE-SAVE": layerstateSave,
        "LAYERSTATE-RESTORE": layerstateRestore,
        "LAYERSTATE-DELETE": layerstateDelete,
        "LAYERSTATE-RENAME": layerstateRename,
        "LAYERSTATE-HAS": layerstateHas,
        "LAYERSTATE-GETNAMES": layerstateGetnames,
        "LAYERSTATE-GETLAYERS": layerstateGetlayers,
        "LAYERSTATE-ADDLAYERS": layerstateAddlayers,
        "LAYERSTATE-REMOVELAYERS": layerstateRemovelayers,
        "LAYERSTATE-GETLASTRESTORED": layerstateGetlastrestored,
        "LAYERSTATE-COMPARE": layerstateCompare,
        "LAYERSTATE-EXPORT": layerstateExport,
        "LAYERSTATE-IMPORT": layerstateImport,
        "LAYERSTATE-IMPORTFROMDB": layerstateImportfromdb,
    ]

    /// Mask bit for on/off, the only captured property.
    private static let onOffBit = 1
    /// Restore flag bit: turn off host layers missing from the state.
    private static let offMissingBit = 1

    private static func key(_ name: String) -> String { name.uppercased() }

    private static func layerNameList(
        _ name: String, _ value: LispValue
    ) throws -> [String] {
        let items = try BuiltinArgs.properList(name, value)
        return try items.map { try BuiltinArgs.string(name, $0) }
    }

    private static func layerstateSave(
        _: LispEvaluator, args: [LispValue], env: inout LispEnvironment, host: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.range("layerstate-save", args, min: 1, max: 3)
        let name = try BuiltinArgs.string("layerstate-save", args[0])
        var mask = onOffBit
        if args.count >= 2, !args[1].isNil {
            mask = try BuiltinArgs.int("layerstate-save", args[1])
        }
        var layers: [String: LispLayerProps] = [:]
        for layer in await host.layerNames() {
            layers[layer] = LispLayerProps(on: await host.layerIsOn(layer) ?? true)
        }
        env.layerStates[key(name)] = LispLayerState(name: name, mask: mask, layers: layers)
        return .t
    }

    private static func layerstateRestore(
        _: LispEvaluator, args: [LispValue], env: inout LispEnvironment, host: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.range("layerstate-restore", args, min: 1, max: 3)
        let name = try BuiltinArgs.string("layerstate-restore", args[0])
        guard let state = env.layerStates[key(name)] else { return .nilValue }
        var flags = 0
        if args.count == 3, !args[2].isNil {
            flags = try BuiltinArgs.int("layerstate-restore", args[2])
        }
        if state.mask & onOffBit != 0 {
            for (layer, props) in state.layers {
                _ = await host.setLayerIsOn(layer, on: props.on)
            }
        }
        if flags & offMissingBit != 0 {
            for layer in await host.layerNames() where state.layers[layer] == nil {
                _ = await host.setLayerIsOn(layer, on: false)
            }
        }
        env.lastRestoredLayerState = state.name
        return .t
    }

    private static func layerstateDelete(
        _: LispEvaluator, args: [LispValue], env: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("layerstate-delete", args, 1)
        let name = try BuiltinArgs.string("layerstate-delete", args[0])
        guard env.layerStates.removeValue(forKey: key(name)) != nil else {
            return .nilValue
        }
        return .t
    }

    private static func layerstateRename(
        _: LispEvaluator, args: [LispValue], env: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("layerstate-rename", args, 2)
        let old = try BuiltinArgs.string("layerstate-rename", args[0])
        let new = try BuiltinArgs.string("layerstate-rename", args[1])
        guard var state = env.layerStates[key(old)],
              env.layerStates[key(new)] == nil else {
            return .nilValue
        }
        env.layerStates.removeValue(forKey: key(old))
        state.name = new
        env.layerStates[key(new)] = state
        return .t
    }

    private static func layerstateHas(
        _: LispEvaluator, args: [LispValue], env: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("layerstate-has", args, 1)
        let name = try BuiltinArgs.string("layerstate-has", args[0])
        return env.layerStates[key(name)] != nil ? .t : .nilValue
    }

    private static func layerstateGetnames(
        _: LispEvaluator, args: [LispValue], env: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("layerstate-getnames", args, 0)
        let names = env.layerStates.values.map(\.name).sorted()
        guard !names.isEmpty else { return .nilValue }
        return LispValue(stringList: names)
    }

    private static func layerstateGetlayers(
        _: LispEvaluator, args: [LispValue], env: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("layerstate-getlayers", args, 1)
        let name = try BuiltinArgs.string("layerstate-getlayers", args[0])
        guard let state = env.layerStates[key(name)] else { return .nilValue }
        let layers = state.layers.keys.sorted()
        guard !layers.isEmpty else { return .nilValue }
        return LispValue(stringList: layers)
    }

    private static func layerstateAddlayers(
        _: LispEvaluator, args: [LispValue], env: inout LispEnvironment, host: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("layerstate-addlayers", args, 2)
        let name = try BuiltinArgs.string("layerstate-addlayers", args[0])
        guard var state = env.layerStates[key(name)] else { return .nilValue }
        for layer in try layerNameList("layerstate-addlayers", args[1]) {
            state.layers[layer] = LispLayerProps(on: await host.layerIsOn(layer) ?? true)
        }
        env.layerStates[key(name)] = state
        return .t
    }

    private static func layerstateRemovelayers(
        _: LispEvaluator, args: [LispValue], env: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("layerstate-removelayers", args, 2)
        let name = try BuiltinArgs.string("layerstate-removelayers", args[0])
        guard var state = env.layerStates[key(name)] else { return .nilValue }
        for layer in try layerNameList("layerstate-removelayers", args[1]) {
            state.layers.removeValue(forKey: layer)
        }
        env.layerStates[key(name)] = state
        return .t
    }

    private static func layerstateGetlastrestored(
        _: LispEvaluator, args: [LispValue], env: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("layerstate-getlastrestored", args, 0)
        guard let name = env.lastRestoredLayerState else { return .nilValue }
        return .string(name)
    }

    /// (layerstate-compare name drawing) tests whether every layer in
    /// the snapshot matches the current host on/off. The drawing
    /// argument is accepted and ignored (single-document host).
    private static func layerstateCompare(
        _: LispEvaluator, args: [LispValue], env: inout LispEnvironment, host: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("layerstate-compare", args, 2)
        let name = try BuiltinArgs.string("layerstate-compare", args[0])
        guard let state = env.layerStates[key(name)] else { return .nilValue }
        for (layer, props) in state.layers {
            guard let current = await host.layerIsOn(layer),
                  current == props.on else {
                return .nilValue
            }
        }
        return .t
    }

    /// (layerstate-export name file) writes the snapshot as JSON
    /// regardless of the file extension.
    private static func layerstateExport(
        _: LispEvaluator, args: [LispValue], env: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("layerstate-export", args, 2)
        let name = try BuiltinArgs.string("layerstate-export", args[0])
        let path = (try BuiltinArgs.string("layerstate-export", args[1]) as NSString)
            .expandingTildeInPath
        guard let state = env.layerStates[key(name)] else { return .nilValue }
        do {
            let data = try JSONEncoder().encode(state)
            try data.write(to: URL(fileURLWithPath: path))
            return .t
        } catch {
            return .nilValue
        }
    }

    /// (layerstate-import file) reads a snapshot written by export and
    /// registers it under its stored name.
    private static func layerstateImport(
        _: LispEvaluator, args: [LispValue], env: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("layerstate-import", args, 1)
        let path = (try BuiltinArgs.string("layerstate-import", args[0]) as NSString)
            .expandingTildeInPath
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let state = try JSONDecoder().decode(LispLayerState.self, from: data)
            env.layerStates[key(state.name)] = state
            return .t
        } catch {
            return .nilValue
        }
    }

    /// Needs a second drawing database; the single-document host has
    /// none, so this always returns nil.
    private static func layerstateImportfromdb(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("layerstate-importfromdb", args, 2)
        _ = try BuiltinArgs.string("layerstate-importfromdb", args[0])
        return .nilValue
    }
}
