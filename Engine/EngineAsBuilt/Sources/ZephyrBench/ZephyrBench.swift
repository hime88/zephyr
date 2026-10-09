import Foundation
import Dispatch
import ZephyrCore

#if canImport(WinSDK)
import WinSDK
#elseif canImport(Darwin)
import Darwin
#endif

// =========================================================================
// MARK: - Zephyr perf harness
// =========================================================================
//
// Cold-start timings for the paths the Swift 6.4 work touches. Not a test: it is a plain executable
// so it can be run by hand (and by CI) without touching the test target.
//
// Usage:  swift run -c release ZephyrBench [dxf <file>] [shx <file>] [nurbs] [all <dxf> <shx>]
//
// Reports wall time and **peak RSS** per case. The DXF parser currently holds whole-file `String` +
// `[String]` lines + every pair at once, so peak RSS matters as much as the clock.
//
// Reference numbers: plans/swift-6.4-baseline.md.

// MARK: - Process metrics

enum ProcessMetrics {
    /// Peak resident set size in bytes for the current process, or nil when unavailable.
    static func peakResidentBytes() -> UInt64? {
        #if canImport(WinSDK)
        var counters = PROCESS_MEMORY_COUNTERS()
        counters.cb = DWORD(MemoryLayout<PROCESS_MEMORY_COUNTERS>.size)
        // `GetProcessMemoryInfo` is exported as `K32GetProcessMemoryInfo` on modern Windows.
        guard K32GetProcessMemoryInfo(GetCurrentProcess(), &counters, counters.cb) else { return nil }
        return UInt64(counters.PeakWorkingSetSize)
        #elseif canImport(Darwin)
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return UInt64(info.resident_size_max)
        #else
        return nil
        #endif
    }

    static func formatBytes(_ bytes: UInt64) -> String {
        String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }
}

// MARK: - Timing

struct Measurement {
    let label: String
    let milliseconds: Double
    let peakResidentBytes: UInt64?

    func report() {
        let rss = peakResidentBytes.map { "  peak RSS \(ProcessMetrics.formatBytes($0))" } ?? ""
        print(String(format: "%-46@ %10.1f ms%@", label as NSString, milliseconds, rss))
    }
}

/// Runs `body` `repeats` times and keeps the best wall time, mirroring the ad-hoc benchmarks the
/// plan was built on (best-of-N is far more stable than a mean on a noisy desktop).
@discardableResult
func measure(_ label: String, repeats: Int = 3, _ body: () throws -> Void) rethrows -> Measurement {
    var best = Double.infinity
    for _ in 0..<repeats {
        let start = DispatchTime.now().uptimeNanoseconds
        try body()
        let end = DispatchTime.now().uptimeNanoseconds
        best = min(best, Double(end - start) / 1_000_000)
    }
    let measurement = Measurement(label: label, milliseconds: best, peakResidentBytes: ProcessMetrics.peakResidentBytes())
    measurement.report()
    return measurement
}

// MARK: - Cases

enum Cases {

    /// Canonical, order-independent digest of everything an importer produces from a DXF file.
    ///
    /// Used as the Phase 1 safety net: capture it before the tokenizer rewrite, diff it after. It is a
    /// deliberately blunt instrument (structural description of every primitive), because the point is
    /// to notice *any* change in the parsed result — not to be pretty.
    ///
    /// The existing `DXFImportTests` suite cannot run under `swift test` on Windows: SwiftPM's
    /// XCTest discovery shim cannot cast `@MainActor` test methods, and several test classes are
    /// `@MainActor` (that predates this branch). Hence this gate lives in a plain executable.
    static func dxfDigestBody(path: String, mode: DXFPairParsingMode = .automatic) throws -> String {
        guard FileManager.default.fileExists(atPath: path) else {
            print("skipped: no such file \(path)")
            return ""
        }

        let reader = try DXFReader().readFile(at: path, mode: mode)
        // Uses the non-isolated importer entry point (not `CADDocument.importDXF`, which is
        // `@MainActor`) so the harness stays callable from anywhere.
        let imported = try DXFImporter.importDXFViews(filePath: path)

        var lines: [String] = []
        func add(_ text: String) { lines.append(text) }

        add("file: \((path as NSString).lastPathComponent)")
        add("pairCount: \(reader.pairCount)")

        // Layers / blocks / entities — shared with the EAB gate so both describe a document the same way.
        lines.append(contentsOf: canonicalDocumentLines(
            layers: imported.layers,
            blocks: imported.blocks,
            entities: imported.entities))

        return lines.joined(separator: "\n")
    }

    /// Hash of the digest body — what the golden files compare and what `dxf-compare` prints.
    static func dxfDigest(path: String, mode: DXFPairParsingMode = .automatic, printDigest: Bool = true) throws -> String {
        let body = try dxfDigestBody(path: path, mode: mode)
        let hash = Self.fnv(body)
        if printDigest {
            print(body)
            print("DIGEST: \(hash)")
        }
        return hash
    }

    /// Case name of a `CADPrimitive` ("line", "polyline", …) without its payload.
    static func primitiveCaseName(_ primitive: CADPrimitive) -> String {
        let description = String(describing: primitive)
        return String(description.prefix { $0 != "(" })
    }



    /// Non-DXF gates: a fixed golden name and the digest the current build computes for it.
    /// `shx-render` uses the shape font checked into `Tools/bench/golden/`, so it is self-contained.
    static func builtinGateBodies(directory: String) throws -> [(name: String, body: String)] {
        let font = URL(fileURLWithPath: directory).appendingPathComponent("simplex8.SHX").path
        return [
            ("eab-scalars", eabScalarsDigest()),
            ("eab-roundtrip", try eabRoundtripDigest()),
            ("shx-render", try shxRenderDigest(path: font)),
            ("vertex-build", vertexBuildDigest()),
            ("nurbs", nurbsDigest()),
            ("dxf-roundtrip", try dxfRoundtripDigest(directory: directory)),
        ]
    }

    /// Compares every `*.dxf` in a directory against the `*.digest.txt` captured next to it, plus the
    /// built-in EAB/SHX gates. Returns true when all match. This is the Phase 1/2 regression gate; it
    /// runs anywhere the bench binary runs, which matters because the XCTest suite cannot execute on
    /// Windows (see `dxfDigest`).
    static func checkGoldens(directory: String, write: Bool = false) throws -> Bool {
        let url = URL(fileURLWithPath: directory)
        let contents = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
        let fixtures = contents.filter { $0.pathExtension.lowercased() == "dxf" }.sorted { $0.path < $1.path }
        guard !fixtures.isEmpty else {
            print("no .dxf fixtures found in \(directory)")
            return false
        }

        var failures = 0
        var checked = 0

        func compare(name: String, goldenURL: URL, body: () throws -> String) throws {
            checked += 1
            let bodyText = try body()
            let digest = Self.fnv(bodyText)
            if write {
                try (bodyText + "\nDIGEST: " + digest + "\n").write(to: goldenURL, atomically: true, encoding: .utf8)
                print("WROTE  \(name)  \(digest)")
                return
            }
            guard let expectedText = checkGoldensReadText(goldenURL),
                  let expectedDigest = checkGoldensDigestLine(expectedText) else {
                print("MISSING GOLDEN  \(name)  (expected \(goldenURL.path))")
                failures += 1
                return
            }
            if digest == expectedDigest {
                print("PASS  \(name)  \(digest)")
            } else {
                print("FAIL  \(name)  got \(digest), expected \(expectedDigest)")
                failures += 1
            }
        }

        for fixture in fixtures {
            try compare(
                name: fixture.lastPathComponent,
                goldenURL: fixture.deletingPathExtension().appendingPathExtension("digest.txt")
            ) { try dxfDigestBody(path: fixture.path) }
        }
        for gate in try builtinGateBodies(directory: directory) {
            let goldenURL = url.appendingPathComponent("\(gate.name).digest.txt")
            try compare(name: gate.name, goldenURL: goldenURL) { gate.body }
        }

        if !write {
            print(failures == 0 ? "goldens: all \(checked) matched" : "goldens: \(failures) of \(checked) FAILED")
        }
        return failures == 0
    }

    /// Extracts the hex digest from a golden file without depending on the file's line endings.
    static func checkGoldensDigestLine(_ text: String) -> String? {
        guard let range = text.range(of: "DIGEST: ") else { return nil }
        let rest = text[range.upperBound...]
        let digest = rest.prefix { !$0.isNewline && !$0.isWhitespace }
        return digest.isEmpty ? nil : String(digest)
    }

    /// Reads a golden file, reporting why it failed instead of collapsing to `nil`.
    static func checkGoldensReadText(_ url: URL) -> String? {
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            print("   cannot read \(url.path): \(error)")
            return nil
        }
    }

    /// Runs both pair parsers over the same file and reports whether they agree.
    /// This is the equivalence proof for the Phase 1 tokenizer swap; it works on any drawing.
    static func dxfCompareTokenizers(path: String) throws {
        guard FileManager.default.fileExists(atPath: path) else {
            print("skipped: no such file \(path)")
            return
        }
        let name = (path as NSString).lastPathComponent

        // Warm both paths first: the second run in a process otherwise looks faster purely because the
        // file is in the OS cache, which made 1–3 MB drawings look like a 1.0× speedup.
        _ = try DXFReader().readFile(at: path, mode: .byteScanner)
        _ = try DXFReader().readFile(at: path, mode: .legacyStrings)

        let startBytes = DispatchTime.now().uptimeNanoseconds
        let bytesReader = try DXFReader().readFile(at: path, mode: .byteScanner)
        let bytesTime = Double(DispatchTime.now().uptimeNanoseconds - startBytes) / 1e6

        let startLegacy = DispatchTime.now().uptimeNanoseconds
        let legacyReader = try DXFReader().readFile(at: path, mode: .legacyStrings)
        let legacyTime = Double(DispatchTime.now().uptimeNanoseconds - startLegacy) / 1e6

        let bytesFingerprint = bytesReader.pairsFingerprint()
        let legacyFingerprint = legacyReader.pairsFingerprint()
        let verdict = bytesFingerprint == legacyFingerprint ? "MATCH" : "MISMATCH"

        print(String(format: "%-36@ %@  pairs %d  byte-scanner %8.1f ms  legacy %8.1f ms  %5.1fx",
                     name as NSString, verdict as NSString, bytesReader.pairCount,
                     bytesTime, legacyTime, legacyTime / max(bytesTime, 0.0001)))
        if bytesFingerprint != legacyFingerprint {
            print("   byte-scanner fingerprint: \(bytesFingerprint)")
            print("   legacy fingerprint:       \(legacyFingerprint)")
        }
    }

    /// FNV-1a, 64-bit. Small, stable, and independent of Swift's `hashValue` (which is seeded per run).
    static func fnv(_ text: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x1000_0000_01b3
        }
        return String(hash, radix: 16)
    }

    /// Compile + runtime check of the Swift 6.4 features this branch depends on. Lives here (not only
    /// in the test target) because the test target needs the libdxfrw C module, and because CI can run
    /// this binary on macOS to prove the features work at our macOS 12 deployment floor.
    static func canary() -> Bool {
        let failures = Swift64FeatureCanary.run()
        if failures.isEmpty {
            print("Swift 6.4 feature canary: OK")
            return true
        }
        print("Swift 6.4 feature canary FAILED: \(failures.joined(separator: ", "))")
        return false
    }

    static func dxf(path: String) throws {
        guard FileManager.default.fileExists(atPath: path) else {
            print("skipped: no such file \(path)")
            return
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? nil
        print("DXF: \((path as NSString).lastPathComponent)  (\((size ?? 0) / 1024 / 1024) MB)")
        try measure("DXF tokenize+parse (DXFReader)") {
            _ = try DXFReader().readFile(at: path)
        }
        try measure("DXF full import (DXFImporter)") {
            _ = try DXFImporter.importDXF(filePath: path)
        }
    }

    static func shx(path: String) throws {
        guard FileManager.default.fileExists(atPath: path) else {
            print("skipped: no such file \(path)")
            return
        }
        print("SHX: \((path as NSString).lastPathComponent)")
        var font: SHXShapeFont?
        try measure("SHX parse") {
            font = try SHXShapeFont(url: URL(fileURLWithPath: path))
        }
        guard let font else { return }
        let sample = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
        measure("SHX render 62 glyphs x50") {
            var total = 0
            for _ in 0..<50 {
                total += font.renderText(sample, origin: Vector3(), height: 12.0).count
            }
            if total == 0 { fatalError("no primitives produced") }
        }
    }

    static func nurbs() {
        // Degree-3 spline, 12 control points — the shape the DXF importer produces for SPLINE entities.
        // Clamped uniform knot vector: a degree-p NURBS over n+1 control points needs n+p+2 knots
        // (here 11 + 3 + 2 = 16 -> four 0s, eight interior values, four 1s).
        let degree = 3
        let controlPoints = (0..<12).map { index in
            Vector3(x: Double(index), y: sin(Double(index) * 0.7) * 3.0, z: 0)
        }
        let interiorCount = controlPoints.count - degree - 1
        let knots: [Double] =
            [Double](repeating: 0, count: degree + 1)
            + (1...interiorCount).map { Double($0) / Double(interiorCount + 1) }
            + [Double](repeating: 1, count: degree + 1)
        let weights = [Double](repeating: 1.0, count: controlPoints.count)
        precondition(
            knots.count == controlPoints.count + degree + 1,
            "knot vector length \(knots.count) does not match the evaluator's requirement"
        )

        print("NURBS: degree 3, 12 control points")
        measure("NURBS evaluate 64 segments x2000", repeats: 3) {
            var points = 0
            for _ in 0..<2000 {
                points += NURBSEvaluator.evaluate(
                    degree: 3, knots: knots, controlPoints: controlPoints,
                    weights: weights, segments: 64
                ).count
            }
            if points == 0 { fatalError("no points produced") }
        }
        measure("NURBS evaluateAt 10k samples", repeats: 3) {
            var hits = 0
            for step in 0..<10_000 {
                let t = Double(step % 1000) / 1000.0
                if NURBSEvaluator.evaluateAt(
                    degree: 3, knots: knots, controlPoints: controlPoints,
                    weights: weights, at: t
                ) != nil { hits += 1 }
            }
            if hits == 0 { fatalError("no samples produced") }
        }
    }
}

// MARK: - Entry point

@main
struct ZephyrBench {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let toolchain = "\(ProcessInfo.processInfo.environment["SWIFT_VERSION"] ?? "swift")"
        _ = toolchain

        print("=== Zephyr perf harness ===")
        print("host: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        print("build: \(isOptimized ? "optimized" : "DEBUG (-Onone) — run with -c release for meaningful numbers")")
        print("")

        guard !arguments.isEmpty else {
            print("usage: ZephyrBench [canary] [dxf <file>] [shx <file>] [nurbs] [dxf-digest <file>] [dxf-compare <file>] [dxf-goldens <dir>] [dxf-goldens-write <dir>] [eab-scalars] [eab-roundtrip] [all <dxf> <shx>]")
            return
        }

        func run(_ name: String, _ body: () throws -> Void) {
            do { try body() } catch { print("\(name) failed: \(error)") }
            print("")
        }

        var index = 0
        var canaryFailed = false
        var goldensFailed = false
        while index < arguments.count {
            switch arguments[index] {
            case "canary":
                run("canary") { if !Cases.canary() { canaryFailed = true } }
            case "dxf":
                index += 1
                let path = index < arguments.count ? arguments[index] : ""
                run("dxf") { try Cases.dxf(path: path) }
            case "shx":
                index += 1
                let path = index < arguments.count ? arguments[index] : ""
                run("shx") { try Cases.shx(path: path) }
            case "nurbs":
                run("nurbs") { Cases.nurbs() }
            case "dxf-digest":
                index += 1
                let path = index < arguments.count ? arguments[index] : ""
                run("dxf-digest") { _ = try Cases.dxfDigest(path: path) }
            case "dxf-profile":
                index += 1
                let path = index < arguments.count ? arguments[index] : ""
                run("dxf-profile") {
                    let result = try DXFImporter.importDXFViews(filePath: path)
                    print("entities: \(result.entities.count)")
                }
            case "dxf-compare":
                index += 1
                let path = index < arguments.count ? arguments[index] : ""
                run("dxf-compare") { try Cases.dxfCompareTokenizers(path: path) }
            case "dxf-goldens":
                index += 1
                let directory = index < arguments.count ? arguments[index] : "Tools/bench/golden"
                run("dxf-goldens") { if try !Cases.checkGoldens(directory: directory) { goldensFailed = true } }
            case "dxf-goldens-write":
                index += 1
                let directory = index < arguments.count ? arguments[index] : "Tools/bench/golden"
                run("dxf-goldens-write") { _ = try Cases.checkGoldens(directory: directory, write: true) }
            case "eab-scalars":
                run("eab-scalars") { print(Cases.eabScalarsDigest()) }
            case "eab-roundtrip":
                run("eab-roundtrip") { try print(Cases.eabRoundtripDigest()) }
            case "shx-render":
                index += 1
                let path = index < arguments.count ? arguments[index] : ""
                run("shx-render") { try print(Cases.shxRenderDigest(path: path)) }
            case "all":
                let dxf = index + 1 < arguments.count ? arguments[index + 1] : ""
                let shx = index + 2 < arguments.count ? arguments[index + 2] : ""
                index += 2
                run("dxf") { try Cases.dxf(path: dxf) }
                run("shx") { try Cases.shx(path: shx) }
                run("nurbs") { Cases.nurbs() }
            default:
                print("unknown case '\(arguments[index])'")
            }
            index += 1
        }

        if canaryFailed || goldensFailed { exit(1) }
    }

    /// `swift build -c release` defines NDEBUG via `-O`; Swift exposes no direct test for `-O`.
    static var isOptimized: Bool {
        #if DEBUG
        return false
        #else
        return true
        #endif
    }
}
