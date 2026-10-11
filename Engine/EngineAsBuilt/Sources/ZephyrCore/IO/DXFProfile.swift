import Foundation

// =========================================================================
// MARK: - DXF import profiling (TEMPORARY)
// =========================================================================
//
// Kept deliberately: it is how the 1.3 s per-entity string format was found, and the
// remaining hotspot (parseSections) is next. Enable with `ZEPHYR_DXF_PROFILE=1`; when
// enabled it prints to stderr, when disabled the cost is one cached-Bool check per
// phase. Delete it and the `DXFProfile.` call sites once DXF import work is finished.
//
// Deliberately dumb: env-gated timestamps that print to stderr, so a normal build
// pays one cached-Bool check per phase and produces no output. Phase marks report
// time since the previous mark, so inserting/removing marks is a one-line edit.
enum DXFProfile {

    static let enabled = ProcessInfo.processInfo.environment["ZEPHYR_DXF_PROFILE"] == "1"

    /// Not thread-safe on purpose: the importers run on one thread and this is throwaway code.
    nonisolated(unsafe) private static var lastMark: UInt64 = DispatchTime.now().uptimeNanoseconds
    nonisolated(unsafe) private static var accumulators: [String: (ns: UInt64, calls: Int)] = [:]

    private static func milliseconds(_ ns: UInt64) -> String {
        String(format: "%9.1f ms", Double(ns) / 1_000_000)
    }

    static func reset(_ label: String) {
        guard enabled else { return }
        accumulators.removeAll(keepingCapacity: true)
        lastMark = DispatchTime.now().uptimeNanoseconds
        write("[dxf-profile] === " + label + " ===")
    }

    /// Prints the time elapsed since the previous `mark`/`reset`.
    static func mark(_ label: String) {
        guard enabled else { return }
        let now = DispatchTime.now().uptimeNanoseconds
        write("[dxf-profile] " + pad(label, 44) + milliseconds(now &- lastMark))
        lastMark = now
    }

    /// Prints accumulated `tic`/`toc` totals, call counts and the mark totals.
    static func dump(_ label: String) {
        guard enabled else { return }
        for key in accumulators.keys.sorted() {
            guard let entry = accumulators[key] else { continue }
            let perCall = entry.calls > 0 ? Double(entry.ns) / Double(entry.calls) / 1000 : 0
            write("[dxf-profile] " + pad(key, 44) + milliseconds(entry.ns)
                  + String(format: "  x%d  (%.2f us/call)", entry.calls, perCall))
        }
        write("[dxf-profile] --- " + label + " ---")
        accumulators.removeAll(keepingCapacity: true)
    }

    static func tic() -> UInt64 {
        enabled ? DispatchTime.now().uptimeNanoseconds : 0
    }

    static func toc(_ start: UInt64, _ label: String) {
        guard enabled, start != 0 else { return }
        let elapsed = DispatchTime.now().uptimeNanoseconds &- start
        var entry = accumulators[label] ?? (0, 0)
        entry.ns &+= elapsed
        entry.calls += 1
        accumulators[label] = entry
    }

    private static func pad(_ text: String, _ width: Int) -> String {
        text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
    }

    private static func write(_ line: String) {
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }
}
