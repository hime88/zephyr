import Foundation

// =========================================================================
// MARK: - Swift 6.4 feature canary
// =========================================================================
//
// Why this file exists: every "new Swift API" the 6.4 release notes advertise is *not* usable on a
// macOS 12 deployment target, and a Windows toolchain cannot tell you that — Windows does not do Apple
// availability checking, so code compiles locally and only breaks in the macOS CI job. That happened
// once (the first macOS build of this branch failed with ~90 availability errors), so the rule is
// written down here and the subset we *can* use is compile-checked and run.
//
// ── Availability on Apple platforms (Swift 6.4 / Xcode 26-era toolchain) ────────────────────────
//
// Usable with deployment target macOS 12:
//   * `borrow` / `mutate` accessors          — language feature (SE-0507), no OS availability
//   * `Span`, `RawSpan`, `MutableSpan` types — back-deployed to macOS 10.14.4 via the
//                                              SwiftCompatibilitySpan library; obtain them from
//                                              `Data.withUnsafeBytes` + `Span(_unsafeStart:count:)`
//   * `RawSpan.load(fromByteOffset:as:)`     — the safe loading API, same back-deployment
//   * `withUnsafeTemporaryAllocation`        — Swift 5.6+
//
// NOT usable (compile error: "only available in macOS N.0 or newer"):
//   * `Array.span`, `Array.mutableSpan`, `Data.span`, `String.utf8.span`  → macOS 26.0
//     (the vending properties need stdlib/Foundation bridging that cannot be back-deployed)
//   * `InlineArray`                                                        → macOS 26.0
//   * `UniqueArray`, `UniqueBox`, `Ref`, `MutableRef`, `Iterable`          → macOS 27.0
//   * `withTemporaryAllocation` (the `OutputSpan`-based one)               → treat as unavailable;
//                                                                            use the Unsafe variant
//
// So: `Span` is reachable, the ergonomic ways to *get* one are not. See plans/swift-6.4-adoption.md.
//
// Two levels of protection:
//   1. Compile-time: this file must build for the macOS 12 deployment target. Anything added here that
//      silently requires a newer OS fails the macOS job, which is the whole point.
//   2. Runtime: `Swift64FeatureCanary.run()` exercises each API and returns failed check names.
public enum Swift64FeatureCanary {

    /// Valid use of `borrow`/`mutate`: a passthrough to a stored property, so a large value is exposed
    /// in place instead of being copied out by `get` and written back by `set`.
    ///
    /// Note what this does *not* do: a `borrow` accessor may only return a stored property, a property
    /// with its own `borrow` accessor, or a global `let` — so it cannot vend a computed `Span`, and
    /// `borrow { return storage.span }` is rejected by SILGen (`Array.span` is macOS 26 anyway).
    public struct StoredStorage {
        private var value: [UInt8]

        public init(_ bytes: [UInt8]) {
            self.value = bytes
        }

        public var bytes: [UInt8] {
            borrow { return value }
            mutate { return &value }
        }
    }

    /// Byte storage that vends a `Span` the way that works on macOS 12: the type is back-deployed, the
    /// `Array.span` property is not.
    public struct BorrowedBytes {
        private var storage: [UInt8]

        public init(_ bytes: [UInt8]) {
            self.storage = bytes
        }

        public var count: Int { storage.count }

        /// Borrows the array's buffer for the duration of `body`. The `Span` never escapes the closure,
        /// which is what keeps this sound without an escaping-pointer pattern.
        public func withBytes<R>(_ body: (Span<UInt8>) throws -> R) rethrows -> R {
            try storage.withUnsafeBufferPointer { buffer in
                try body(Span(_unsafeStart: buffer.baseAddress!, count: buffer.count))
            }
        }

        /// The Phase 1 shape: a `Span` cursor over a mapped byte buffer.
        public func sumOfFirst(_ count: Int) -> Int {
            withBytes { bytes in
                var total = 0
                for index in 0..<Swift.min(count, bytes.count) { total += Int(bytes[index]) }
                return total
            }
        }
    }

    /// Exercised by the test target and by `ZephyrBench canary`. Returns failed check names.
    public static func run() -> [String] {
        var failures: [String] = []

        func check(_ name: String, _ condition: @autoclosure () -> Bool) {
            if !condition() { failures.append(name) }
        }

        // --- borrow / mutate on a stored property (SE-0507) ------------------------------------
        var stored = StoredStorage([1, 2, 3])
        check("borrow accessor read", stored.bytes == [1, 2, 3])
        stored.bytes = [7, 8]
        check("mutate accessor write", stored.bytes == [7, 8])

        // --- Span, obtained the only way that works at macOS 12 --------------------------------
        let borrowed = BorrowedBytes([1, 2, 3, 4, 5])
        check("Span via Data/Array buffer", borrowed.withBytes { $0.count } == 5)
        check("Span cursor", borrowed.sumOfFirst(3) == 6)

        // --- RawSpan + the safe loading API (SE-0525) ------------------------------------------
        let data = Data([0x01, 0x00, 0x00, 0x00, 0xFF])
        let loaded: UInt32 = data.withUnsafeBytes { raw in
            RawSpan(_unsafeBytes: raw).load(fromByteOffset: 0, as: UInt32.self)
        }
        check("RawSpan.load", loaded == 1)
        check("RawSpan.byteCount", data.withUnsafeBytes { RawSpan(_unsafeBytes: $0).byteCount } == 5)

        // --- withUnsafeTemporaryAllocation: scratch buffer that is cleaned up for us -----------
        let scratchSum = withUnsafeTemporaryAllocation(of: Int.self, capacity: 8) { buffer -> Int in
            for index in 0..<buffer.count { buffer[index] = index * 2 }
            var sum = 0
            for index in 0..<buffer.count { sum += buffer[index] }
            return sum
        }
        check("withUnsafeTemporaryAllocation", scratchSum == 56)

        return failures
    }
}
