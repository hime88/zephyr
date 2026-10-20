import Foundation
import ZephyrLisp

// =========================================================================
// MARK: - Scripted Command Dispatcher ((command ...) / (command-s ...))
// =========================================================================
//
// `(command ...)` NEVER routes through the interactive `executeCommand`
// (see LispInvocationContext.swift). Instead this dispatcher implements an
// audited subset of commands directly against the document, selection, and
// variable store. Every command here:
//
// * consumes only already-evaluated arguments (points, strings, numbers,
//   entity names, selection sets) and never requests input;
// * performs exactly ONE undo push per call (single-mutator rule), so one
//   scripted call is one undo entry, matching AutoCAD;
// * fails closed on anything outside its audited surface, naming the
//   offending command, keyword, or token.
//
// Token conventions (AutoCAD-compatible):
// * `_.NAME` / `_NAME` prefixes are stripped (global command/keyword form).
// * `""` terminates the current argument sequence (Enter).
// * Osnap overrides (`_non`, `_end`, ...) are skipped: scripted geometry
//   uses exact coordinates, so overrides are vacuous.
// * `PAUSE` (user input spliced into the sequence) is rejected: nothing in
//   the Lisp path may block for input outside the broker.
// * `'`-prefixed transparent commands are rejected (interactive-only).
// * `_L` = most recently created entity, `_P` = previous selection set.

// UNISOLATED by design (see LispCADHost): runs on the eval task, which
// cannot hop to MainActor under the unpumped SDL loop.
enum LispScriptedCommands {

    /// Audited scripted set. Everything else is `.interactiveReject`.
    /// This table is pinned by LispReentrancyTests' approved-list test:
    /// add a name here only with its implementation + test below.
    static let scripted: Set<String> = [
        "LINE", "CIRCLE", "PLINE", "ARC",
        "COPY", "ROTATE", "MOVE", "ERASE", "SELECT",
        "UNDO", "U", "REDRAW", "REGEN", "INSERT", "-INSERT", "-ATTACH",
    ]

    static func disposition(for name: String) -> LispCommandDisposition {
        scripted.contains(canonicalName(name)) ? .scripted : .interactiveReject
    }

    /// Strips `_.`/`_` prefixes and uppercases. Returns nil for transparent
    /// (`'...`) invocations, which are always interactive.
    static func canonicalName(_ raw: String) -> String {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if name.hasPrefix("'") { return name } // Transparent: never scripted.
        if name.hasPrefix("_.") { name = String(name.dropFirst(2)) }
        else if name.hasPrefix("_") { name = String(name.dropFirst(1)) }
        return name
    }

    /// Known osnap-override keywords (skipped as vacuous in scripted calls).
    static let snapOverrides: Set<String> = [
        "NON", "END", "MID", "CEN", "INT", "APP", "EXT", "INS", "PER",
        "TAN", "QUA", "PAR", "NOD", "NEA", "GCE",
    ]

    // MARK: - Entry

    static func run(args: [LispValue], host: LispCADHost) async throws -> LispValue {
        guard let first = args.first else { return .nilValue } // (command) alone: no-op.
        guard case let .string(rawName) = first else {
            throw LispError.typeMismatch(
                name: "command", expected: "command name string", got: first)
        }
        if rawName.trimmingCharacters(in: .whitespaces).hasPrefix("'") {
            throw LispError.hostError(
                "command: transparent invocation '\(rawName)' is not supported from Lisp")
        }
        let name = canonicalName(rawName)
        for token in args.dropFirst() {
            let isPause: Bool = switch token {
            case let .string(s): canonicalName(s) == "PAUSE"
            case let .symbol(s): s.uppercased() == "PAUSE"
            default: false
            }
            if isPause {
                throw LispError.hostError(
                    "command: PAUSE (interactive input) is not supported from Lisp")
            }
        }
        var operands = Array(args.dropFirst())
        switch name {
        case "LINE": try await runLine(&operands, host: host)
        case "CIRCLE": try await runCircle(&operands, host: host)
        case "PLINE": try await runPline(&operands, host: host)
        case "ARC": try await runArc(&operands, host: host)
        case "COPY": try await runCopy(&operands, host: host)
        case "ROTATE": try runRotate(&operands, host: host)
        case "MOVE": try runMove(&operands, host: host)
        case "ERASE": try runErase(&operands, host: host)
        case "SELECT": try runSelect(&operands, host: host)
        case "INSERT", "-INSERT": try await runInsert(&operands, host: host)
        case "-ATTACH": try runAttach(&operands, host: host)
        case "UNDO": try await runUndo(&operands, host: host)
        case "U": host.undoOnce()
        case "REDRAW": host.document.markEdited(regenerate: false)
        case "REGEN": host.document.markEdited(regenerate: true)
        default:
            throw LispError.hostError(
                "command: \"\(rawName)\" is not supported from Lisp " +
                    "(interactive-only or not yet audited)")
        }
        return .nilValue
    }

    // MARK: - Operand cursor

    /// Consumes and returns the next string keyword (uppercased,
    /// prefix-stripped), or nil when the next operand is not a string.
    /// `""` (Enter) is consumed and reported as `.enter`.
    ///
    /// When `skippingSnaps`, osnap overrides (`_non`, `_end`, ...) are
    /// consumed and skipped as vacuous — valid only in point/selection
    /// positions. Pass false where a real keyword collides with a snap
    /// name: UNDO's END would otherwise be eaten as the ENDpoint override.
    enum Keyword { case enter, word(String) }

    static func takeKeyword(
        _ operands: inout [LispValue], skippingSnaps: Bool = true
    ) -> Keyword? {
        while let first = operands.first {
            guard case let .string(raw) = first else { return nil }
            operands.removeFirst()
            if raw == "" { return .enter }
            let word = canonicalName(raw)
            if skippingSnaps, snapOverrides.contains(word) { continue }
            return .word(word)
        }
        return nil
    }

    /// Skips vacuous osnap overrides (`_non`, ...) preceding a value.
    static func skipSnaps(_ operands: inout [LispValue]) {
        while let first = operands.first,
              case let .string(raw) = first,
              snapOverrides.contains(canonicalName(raw))
        {
            operands.removeFirst()
        }
    }

    /// Consumes the next point operand (2-3 numbers). Throws on mismatch.
    /// Throws on a keyword where a point is required, naming it.
    static func takePoint(
        _ operands: inout [LispValue], command: String, what: String
    ) throws -> Vector3 {
        skipSnaps(&operands)
        guard let first = operands.first else {
            throw LispError.hostError("command: \(command) needs \(what)")
        }
        if case let .string(raw) = first {
            if raw == "" {
                throw LispError.hostError("command: \(command) needs \(what) (got Enter)")
            }
            throw LispError.hostError(
                "command: \(command) needs \(what) (got keyword \"\(raw)\")")
        }
        guard let coords = first.asPoint, coords.count >= 2 else {
            throw LispError.typeMismatch(
                name: "command", expected: "\(command) \(what) (point)", got: first)
        }
        operands.removeFirst()
        return Vector3(
            x: coords[0], y: coords[1],
            z: coords.count > 2 ? coords[2] : 0)
    }

    static func takeNumber(
        _ operands: inout [LispValue], command: String, what: String
    ) throws -> Double {
        skipSnaps(&operands)
        guard let first = operands.first, let value = first.asDouble else {
            throw LispError.hostError("command: \(command) needs \(what)")
        }
        operands.removeFirst()
        return value
    }

    /// Consumes a selection sequence: entity names, selection sets, _L, _P,
    /// W/C windows (each followed by two corner points), ALL — terminated
    /// by `""` (Enter) or end of operands. Records the result as the
    /// previous selection when non-empty.
    static func takeSelection(
        _ operands: inout [LispValue], command: String, host: LispCADHost
    ) throws -> Set<UUID> {
        var out = Set<UUID>()
        var explicitEnd = false
        while let first = operands.first {
            switch first {
            case let .entityName(handle):
                operands.removeFirst()
                if let uuid = UUID(uuidString: handle),
                   host.document.entity(for: uuid) != nil
                {
                    out.insert(uuid)
                }
            case let .selectionSet(id):
                operands.removeFirst()
                out.formUnion(host.selectionHandles(id: id))
            case let .string(raw):
                operands.removeFirst()
                if raw == "" { explicitEnd = true; break }
                switch canonicalName(raw) {
                case "L":
                    if let last = host.lastCreated { out.insert(last) }
                case "P":
                    out.formUnion(host.previousSelection)
                case "ALL":
                    out.formUnion(host.document.allEntities.map(\.handle))
                case "W", "C":
                    let style: CADSelectionManager.RectSelectStyle =
                        canonicalName(raw) == "W" ? .window : .crossing
                    let a = try takePoint(&operands, command: command, what: "first corner")
                    let b = try takePoint(&operands, command: command, what: "other corner")
                    out.formUnion(host.handlesInRect(a, b, style: style))
                case let word where snapOverrides.contains(word):
                    continue // Vacuous inside selection sequences too.
                default:
                    throw LispError.hostError(
                        "command: \(command) got unexpected selection keyword \"\(raw)\"")
                }
            default:
                throw LispError.typeMismatch(
                    name: "command",
                    expected: "\(command) selection (entity, set, _L, _P, window, or Enter)",
                    got: first)
            }
            if explicitEnd { break }
        }
        if !out.isEmpty { host.previousSelection = out }
        return out
    }

    // MARK: - Draw commands (one addEntities batch = one undo entry)

    private static func activeLayerID(_ host: LispCADHost) throws -> UUID {
        if let id = host.document.activeLayerID { return id }
        if let first = host.document.allLayers.first { return first.handle }
        throw LispError.hostError("command: drawing has no layers")
    }

    private static func currentColor(_ host: LispCADHost) async -> ColorRGBA? {
        guard let value = await host.getSystemVar("CECOLOR") else { return nil }
        if case let .int(aci) = value, (1...255).contains(aci) {
            return DXFColorTable.aciToRGBA(Int32(aci), color24: -1)
        }
        return nil // BYLAYER / BYBLOCK.
    }

    private static func addPrimitives(
        _ prims: [CADPrimitive], host: LispCADHost
    ) async throws {
        guard !prims.isEmpty else { return }
        let layerID = try activeLayerID(host)
        let entities = prims.map {
            CADEntity(layerID: layerID, localGeometry: [$0])
        }
        host.document.addEntities(entities)
        host.lastCreated = entities.last?.handle
    }

    private static func runLine(_ operands: inout [LispValue], host: LispCADHost) async throws {
        var points: [Vector3] = []
        var closed = false
        var done = false
        while !operands.isEmpty, !done {
            if let keyword = takeKeyword(&operands) {
                switch keyword {
                case .enter: done = true
                case .word("C"):
                    closed = points.count > 2
                    // "C" closes AND ends the sequence in AutoCAD.
                    done = true
                case .word(let word):
                    throw LispError.hostError(
                        "command: LINE does not support keyword \"\(word)\"")
                }
                continue
            }
            points.append(try takePoint(&operands, command: "LINE", what: "a point"))
        }
        guard points.count >= 2 else {
            throw LispError.hostError("command: LINE needs at least two points")
        }
        let color = await currentColor(host)
        var prims: [CADPrimitive] = []
        for index in 0..<(points.count - 1) {
            prims.append(.line(start: points[index], end: points[index + 1], color: color))
        }
        if closed, let first = points.first, let last = points.last {
            prims.append(.line(start: last, end: first, color: color))
        }
        try await addPrimitives(prims, host: host)
    }

    private static func runCircle(_ operands: inout [LispValue], host: LispCADHost) async throws {
        var center: Vector3?
        var radius: Double?
        if let keyword = takeKeyword(&operands) {
            switch keyword {
            case .word("2P"):
                let a = try takePoint(&operands, command: "CIRCLE", what: "first diameter point")
                let b = try takePoint(&operands, command: "CIRCLE", what: "second diameter point")
                center = Vector3(
                    x: (a.x + b.x) / 2, y: (a.y + b.y) / 2, z: (a.z + b.z) / 2)
                radius = distance3(a, b) / 2
            case .word("3P"):
                let a = try takePoint(&operands, command: "CIRCLE", what: "first point")
                let b = try takePoint(&operands, command: "CIRCLE", what: "second point")
                let c = try takePoint(&operands, command: "CIRCLE", what: "third point")
                guard let solved = circumcenter(a, b, c) else {
                    throw LispError.hostError("command: CIRCLE 3P points are collinear")
                }
                center = solved.center
                radius = solved.radius
            case .word(let word):
                throw LispError.hostError(
                    "command: CIRCLE does not support keyword \"\(word)\"")
            case .enter:
                throw LispError.hostError("command: CIRCLE needs a center point")
            }
        } else {
            center = try takePoint(&operands, command: "CIRCLE", what: "a center point")
            if let keyword = takeKeyword(&operands) {
                switch keyword {
                case .word("D"):
                    let diameter = try takeNumber(&operands, command: "CIRCLE", what: "a diameter")
                    radius = diameter / 2
                case .word(let word):
                    throw LispError.hostError(
                        "command: CIRCLE does not support keyword \"\(word)\"")
                case .enter:
                    throw LispError.hostError("command: CIRCLE needs a radius")
                }
            } else {
                radius = try takeNumber(&operands, command: "CIRCLE", what: "a radius")
            }
        }
        guard let center, let radius, radius > 0 else {
            throw LispError.hostError("command: CIRCLE needs a positive radius")
        }
        try await addPrimitives(
            [.circle(center: center, radius: radius, color: await currentColor(host))],
            host: host)
    }

    private static func runPline(_ operands: inout [LispValue], host: LispCADHost) async throws {
        var vertices: [CADPolylineVertex] = []
        var closed = false
        var done = false
        while !operands.isEmpty, !done {
            if let keyword = takeKeyword(&operands) {
                switch keyword {
                case .enter: done = true
                case .word("C"):
                    closed = true
                    done = true
                case .word("A"):
                    throw LispError.hostError(
                        "command: PLINE arc segments are not supported from Lisp")
                case .word("W"), .word("H"):
                    throw LispError.hostError(
                        "command: PLINE width is not supported from Lisp (use entmake LWPOLYLINE 40/41 groups)")
                case .word(let word):
                    throw LispError.hostError(
                        "command: PLINE does not support keyword \"\(word)\"")
                }
                if operands.isEmpty { break }
                continue
            }
            let point = try takePoint(&operands, command: "PLINE", what: "a vertex")
            vertices.append(CADPolylineVertex(
                position: point, bulge: 0, startWidth: 0, endWidth: 0))
        }
        guard vertices.count >= 2 else {
            throw LispError.hostError("command: PLINE needs at least two vertices")
        }
        try await addPrimitives(
            [.polyline(
                path: CADPolyline(vertices: vertices, isClosed: closed),
                color: await currentColor(host))],
            host: host)
    }

    private static func runArc(_ operands: inout [LispValue], host: LispCADHost) async throws {
        // Forms: 3-point (p1 p2 p3), or C center start end.
        if let keyword = takeKeyword(&operands) {
            switch keyword {
            case .word("C"):
                let center = try takePoint(&operands, command: "ARC", what: "a center point")
                let start = try takePoint(&operands, command: "ARC", what: "a start point")
                let end = try takePoint(&operands, command: "ARC", what: "an end point")
                let radius = distance3(center, start)
                guard radius > 0 else {
                    throw LispError.hostError("command: ARC center and start coincide")
                }
                try await addPrimitives(
                    [.arc(
                        center: center, radius: radius,
                        startAngle: atan2(start.y - center.y, start.x - center.x),
                        endAngle: atan2(end.y - center.y, end.x - center.x),
                        color: await currentColor(host))],
                    host: host)
                return
            case .word(let word):
                throw LispError.hostError(
                    "command: ARC does not support keyword \"\(word)\" " +
                        "(supported: 3-point, or C center/start/end)")
            case .enter:
                throw LispError.hostError("command: ARC needs points")
            }
        }
        let a = try takePoint(&operands, command: "ARC", what: "a start point")
        let b = try takePoint(&operands, command: "ARC", what: "a second point")
        let c = try takePoint(&operands, command: "ARC", what: "an end point")
        guard let solved = circumcenter(a, b, c) else {
            throw LispError.hostError("command: ARC points are collinear")
        }
        try await addPrimitives(
            [.arc(
                center: solved.center, radius: solved.radius,
                startAngle: atan2(a.y - solved.center.y, a.x - solved.center.x),
                endAngle: atan2(c.y - solved.center.y, c.x - solved.center.x),
                color: await currentColor(host))],
            host: host)
    }

    // MARK: - Modify commands (single-mutator rule: one call, one undo entry)

    /// `(command "INSERT" name-or-path point [xscale [yscale [rotation]]])`
    /// — classic file-insert semantics: a name that resolves to an
    /// existing .dxf/.dwg file imports it as a new block definition.
    /// Scales/rotation accept numbers or numeric strings ("1"), "" or a
    /// missing operand takes the default (unit scale / X / 0 degrees).
    private static func runInsert(_ operands: inout [LispValue], host: LispCADHost) async throws {
        guard let first = operands.first, case let .string(rawName) = first, !rawName.isEmpty else {
            throw LispError.hostError("command: INSERT needs a block name or drawing file path")
        }
        operands.removeFirst()
        let document = host.document
        let blockID: UUID
        var defaultScale = 1.0
        if let existing = document.allBlocks.first(where: {
            $0.name.caseInsensitiveCompare(rawName) == .orderedSame && !$0.name.hasPrefix("*")
        }) {
            blockID = existing.handle
        } else {
            // Drawing-file insert: try the name as a path, then with
            // drawing extensions appended (AutoCAD's library lookup).
            let candidates = [rawName, rawName + ".dwg", rawName + ".dxf"]
            guard let path = candidates.first(where: {
                FileManager.default.fileExists(atPath: $0)
            }) else {
                throw LispError.hostError(
                    "command: INSERT block \"\(rawName)\" not found (and no such drawing file)")
            }
            do {
                let (block, scale) = try DrawingFileInsert.insertFile(at: path, into: document)
                blockID = block.handle
                defaultScale = scale
            } catch let error as DrawingFileInsert.InsertError {
                throw LispError.hostError("command: INSERT \(error)")
            }
        }
        let point = try takePoint(&operands, command: "INSERT", what: "insertion point")
        func takeScale(_ fallback: Double) -> Double {
            skipSnaps(&operands)
            guard let next = operands.first else { return fallback }
            if let value = next.asDouble { operands.removeFirst(); return value }
            if case let .string(raw) = next {
                operands.removeFirst()
                return Double(raw) ?? fallback
            }
            return fallback
        }
        let scaleX = takeScale(defaultScale)
        let scaleY = takeScale(scaleX)
        let rotation = takeScale(0)
        let entity = CADEntity(
            layerID: try activeLayerID(host),
            blockID: blockID,
            transform: DrawingFileInsert.insertionTransform(
                point: point, scaleX: scaleX, scaleY: scaleY,
                rotationDegrees: rotation))
        document.addEntities([entity])
        host.lastCreated = entity.handle
    }


    /// `(command "-ATTACH" path [page] point [scale [rotation]])`
    /// for images and PDFs: creates (or reuses) a referenced-media
    /// definition, loads it synchronously, and places one instance.
    /// Drawings reject here — use INSERT (embed) or interactive XATTACH.
    private static func runAttach(_ operands: inout [LispValue], host: LispCADHost) throws {
        guard let first = operands.first, case let .string(rawPath) = first, !rawPath.isEmpty else {
            throw LispError.hostError("command: -ATTACH needs a file path")
        }
        operands.removeFirst()
        let document = host.document
        guard FileManager.default.fileExists(atPath: rawPath) else {
            throw LispError.hostError("command: -ATTACH file \"\(rawPath)\" not found")
        }
        let ext = (rawPath as NSString).pathExtension.lowercased()
        if ext == "dwg" || ext == "dxf" {
            throw LispError.hostError(
                "command: -ATTACH of drawings is interactive-only (XATTACH); use INSERT to embed")
        }
        let store: MediaReferenceStore
        if let existing = document.mediaRuntimeStore {
            store = existing
        } else {
            store = MediaReferenceStore()
            document.mediaRuntimeStore = store
        }
        let pathType = XrefSysvars.refPathType
        let saved = XrefManager.savedPath(
            forFileAt: rawPath, pathType: pathType, hostFolder: nil)

        let name: String
        let kind: MediaReferenceKind
        var pageNumber = 1
        var naturalWidth: Double
        var naturalHeight: Double
        if ext == "pdf" {
            kind = .pdf
            if let next = operands.first, let page = next.asDouble {
                operands.removeFirst()
                pageNumber = max(1, Int(page))
            }
            if let existing = document.pdfDefinitions.values.first(where: {
                $0.savedPath == saved && $0.pageNumber == pageNumber
            }) {
                name = existing.name
            } else {
                name = MediaManager.definitionName(forFileAt: rawPath, in: document)
                document.pdfDefinitions[name] = CADPdfDefinition(
                    name: name, savedPath: saved, pageNumber: pageNumber)
            }
            naturalWidth = CADPdfUnderlayParams.placeholderPageWidth
            naturalHeight = CADPdfUnderlayParams.placeholderPageHeight
        } else if CADImageAsset.supportedExtensions.contains(ext) {
            kind = .image
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: rawPath)),
                  let dims = MediaLoader.imageDimensions(of: data) else {
                throw LispError.hostError("command: -ATTACH could not decode image \"\(rawPath)\"")
            }
            if let existing = document.imageDefinitions.values.first(where: { $0.savedPath == saved }) {
                name = existing.name
            } else {
                name = MediaManager.definitionName(forFileAt: rawPath, in: document)
                document.imageDefinitions[name] = CADImageDefinition(
                    name: name, savedPath: saved,
                    pixelWidth: dims.width, pixelHeight: dims.height)
            }
            naturalWidth = Double(dims.width)
            naturalHeight = Double(dims.height)
        } else {
            throw LispError.hostError(
                "command: -ATTACH unsupported file type .\(ext) (images and PDFs only)")
        }
        store.ensureEntry(kind: kind, name: name, savedPath: saved, pageNumber: pageNumber)
        let outcome = MediaLoader.performLoad(
            kind: kind, name: name, savedPath: saved, pageNumber: pageNumber,
            hostFolder: nil, fallbackFolder: nil, searchPaths: store.searchPaths)
        MediaLoader.apply(outcome, name: name, store: store, documents: [document])
        if kind == .pdf, let w = outcome.pageWidthPoints, let h = outcome.pageHeightPoints {
            naturalWidth = w
            naturalHeight = h
        }

        let point = try takePoint(&operands, command: "-ATTACH", what: "insertion point")
        func takeScale(_ fallback: Double) -> Double {
            skipSnaps(&operands)
            guard let next = operands.first else { return fallback }
            if let value = next.asDouble { operands.removeFirst(); return value }
            if case let .string(raw) = next {
                operands.removeFirst()
                return Double(raw) ?? fallback
            }
            return fallback
        }
        let scale = takeScale(1)
        let rotation = takeScale(0)
        let entity = MediaManager.makeInstance(
            name: name, kind: kind,
            naturalWidth: naturalWidth, naturalHeight: naturalHeight,
            center: point, scale: scale <= 0 ? 1 : scale,
            rotationDegrees: rotation,
            layerID: try activeLayerID(host))
        document.addEntities([entity])
        host.lastCreated = entity.handle
    }

    private static func runCopy(_ operands: inout [LispValue], host: LispCADHost) async throws {
        let targets = try takeSelection(&operands, command: "COPY", host: host)
        guard !targets.isEmpty else {
            throw LispError.hostError("command: COPY requires a selection")
        }
        var multiple = false
        if let keyword = takeKeyword(&operands) {
            switch keyword {
            case .word("M"): multiple = true
            case .word(let word):
                throw LispError.hostError(
                    "command: COPY does not support keyword \"\(word)\"")
            case .enter:
                throw LispError.hostError("command: COPY needs a base point")
            }
        }
        let base = try takePoint(&operands, command: "COPY", what: "a base point")
        var displacements: [Vector3] = []
        while !operands.isEmpty {
            if let keyword = takeKeyword(&operands) {
                if case .word(let word) = keyword {
                    throw LispError.hostError(
                        "command: COPY does not support keyword \"\(word)\"")
                }
                break // Enter ends the displacement list.
            }
            let second = try takePoint(&operands, command: "COPY", what: "a displacement")
            displacements.append(Vector3(
                x: second.x - base.x, y: second.y - base.y, z: second.z - base.z))
            if !multiple { break }
        }
        guard !displacements.isEmpty else {
            throw LispError.hostError("command: COPY needs a displacement")
        }
        var copies: [CADEntity] = []
        for handle in targets.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard let entity = host.document.entity(for: handle) else { continue }
            for displacement in displacements {
                var transform = entity.transform
                transform.position = Vector3(
                    x: transform.position.x + displacement.x,
                    y: transform.position.y + displacement.y,
                    z: transform.position.z + displacement.z)
                copies.append(CADEntity(
                    layerID: entity.layerID,
                    blockID: entity.blockID,
                    localGeometry: entity.localGeometry,
                    dimensionMetadata: entity.dimensionMetadata,
                    leaderData: entity.leaderData,
                    arrayData: entity.arrayData,
                    transform: transform,
                    xdata: entity.xdata))
            }
        }
        host.document.addEntities(copies)
        host.lastCreated = copies.last?.handle
    }

    private static func runRotate(_ operands: inout [LispValue], host: LispCADHost) throws {
        let targets = try takeSelection(&operands, command: "ROTATE", host: host)
        guard !targets.isEmpty else {
            throw LispError.hostError("command: ROTATE requires a selection")
        }
        if let keyword = takeKeyword(&operands), case .word(let word) = keyword {
            throw LispError.hostError(
                "command: ROTATE does not support keyword \"\(word)\" (reference angles are interactive-only)")
        }
        let base = try takePoint(&operands, command: "ROTATE", what: "a base point")
        let degrees = try takeNumber(&operands, command: "ROTATE", what: "a rotation angle in degrees")
        host.document.rotateEntities(
            handles: targets, around: base,
            angleDeltaRadians: degrees * Double.pi / 180)
    }

    private static func runMove(_ operands: inout [LispValue], host: LispCADHost) throws {
        let targets = try takeSelection(&operands, command: "MOVE", host: host)
        guard !targets.isEmpty else {
            throw LispError.hostError("command: MOVE requires a selection")
        }
        let base = try takePoint(&operands, command: "MOVE", what: "a base point")
        let second = try takePoint(&operands, command: "MOVE", what: "a displacement")
        host.document.moveEntities(
            handles: targets,
            by: Vector3(
                x: second.x - base.x, y: second.y - base.y, z: second.z - base.z))
    }

    private static func runErase(_ operands: inout [LispValue], host: LispCADHost) throws {
        let targets = try takeSelection(&operands, command: "ERASE", host: host)
        guard !targets.isEmpty else { return } // ERASE of nothing: silent no-op.
        host.document.removeEntities(handles: targets)
    }

    /// SELECT makes a selection current (pickfirst + previous): the
    /// scripted (vl-cmdf "_.SELECT" ss "") idiom. Pushes no undo.
    private static func runSelect(_ operands: inout [LispValue], host: LispCADHost) throws {
        let targets = try takeSelection(&operands, command: "SELECT", host: host)
        host.previousSelection = targets
        host.setPickfirst(targets)
    }

    // MARK: - UNDO / U

    private static func runUndo(_ operands: inout [LispValue], host: LispCADHost) async throws {
        // Numeric form first: (command "_.UNDO" 3) undoes N commands.
        if let first = operands.first, first.asDouble != nil {
            operands.removeFirst()
            host.undoTimes(Int(first.asDouble!))
            return
        }
        // No snap-skipping: UNDO END collides with the ENDpoint override.
        guard let keyword = takeKeyword(&operands, skippingSnaps: false) else {
            // Bare (command "_.UNDO") with no option: single undo, like U.
            host.undoOnce()
            return
        }
        switch keyword {
        case .word("BEGIN"), .word("BE"), .word("G"):
            host.document.undoManager.beginUndoGroup()
        case .word("END"):
            if !host.document.undoManager.endUndoGroup() {
                await host.write("No group to end.\n")
            }
        case .word("MARK"):
            host.undoMark = host.document.undoManager.markUndo()
        case .word("BACK"):
            host.undoBack()
        case .word("AUTO"):
            throw LispError.hostError("command: UNDO Auto is not supported from Lisp")
        case .word("CONTROL"):
            throw LispError.hostError("command: UNDO Control is not supported from Lisp")
        case .word(let word):
            throw LispError.hostError(
                "command: UNDO does not support option \"\(word)\"")
        case .enter:
            host.undoOnce()
        }
    }

    // MARK: - Geometry helpers

    private static func distance3(_ a: Vector3, _ b: Vector3) -> Double {
        let dx = a.x - b.x, dy = a.y - b.y, dz = a.z - b.z
        return (dx * dx + dy * dy + dz * dz).squareRoot()
    }

    /// Circumcenter of three 2D points (z carried from a), or nil when
    /// collinear. Standard perpendicular-bisector solve.
    private static func circumcenter(
        _ a: Vector3, _ b: Vector3, _ c: Vector3
    ) -> (center: Vector3, radius: Double)? {
        let d = 2 * (a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y))
        guard abs(d) > 1e-12 else { return nil }
        let a2 = a.x * a.x + a.y * a.y
        let b2 = b.x * b.x + b.y * b.y
        let c2 = c.x * c.x + c.y * c.y
        let cx = (a2 * (b.y - c.y) + b2 * (c.y - a.y) + c2 * (a.y - b.y)) / d
        let cy = (a2 * (c.x - b.x) + b2 * (a.x - c.x) + c2 * (b.x - a.x)) / d
        let center = Vector3(x: cx, y: cy, z: a.z)
        return (center, distance3(center, a))
    }
}
