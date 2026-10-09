import Foundation

// =========================================================================
// MARK: - Swift 6.4 feature canary
// =========================================================================
//
// This branch adopts Swift 6.4 APIs that are either brand new or gated behind an unstable
// experimental feature. If a toolchain update renames, removes, or re-gates any of them, the
// failure must show up here — in CI, on the platform we ship — rather than halfway through a
// later refactor.
//
// Two levels of protection:
//
//   1. Compile-time: this file must build on every supported deployment target. The macOS job
//      builds with MACOSX_DEPLOYMENT_TARGET=12.0, which is what proves these APIs are actually
//      available on our floor. Anything here that turns out to need macOS 13+ has to be dropped
//      (Phase 1 only strictly needs `Span` + a `Data` slice).
//   2. Runtime: `Swift64FeatureCanary.run()` exercises each API and returns the names of the
//      checks that failed. `Swift64FeatureCanaryTests` asserts the list is empty.
//
// ── The rule that cost the most time to pin down ────────────────────────────────────────────────
//
// SE-0507 restricts what a `borrow` accessor may return: *stored properties, computed properties
// that themselves have `borrow` accessors, or global `let` declarations*. `Array.span` is neither,
// so this is **invalid** — even though `swiftc -typecheck` accepts it, because the diagnostic is
// emitted during SILGen and `-typecheck` never runs SILGen:
//
//     var bytes: Span<UInt8> { borrow { return storage.span } }   // ❌ invalid return value
//
// It only surfaces in a real compile, which is why `swift test`/`swift build` catch it and a
// type-check-only probe does not. The working shapes are:
//
//     @_lifetime(borrow self) func view() -> Span<UInt8> { storage.span }   // ✅ method
//     func withBytes<R>(_ body: (Span<UInt8>) throws -> R) rethrows -> R    // ✅ closure
//     let s = storage.span                                                  // ✅ local
//
// `borrow`/`mutate` accessors remain the right tool for the case SE-0507 actually targets: a
// passthrough to a *stored* property (see `StoredStorage` below).
//
// See plans/swift-6.4-adoption.md for the feature list and the macOS 12 go/no-go.
public enum Swift64FeatureCanary {

    /// Valid use of `borrow`/`mutate`: a passthrough to a stored property, so a large value is
    /// exposed in place instead of being copied out by `get` and written back by `set`.
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

    /// Byte storage that vends `Span` views — the shapes that survive a real compile.
    public struct BorrowedBytes {
        private var storage: [UInt8]

        public init(_ bytes: [UInt8]) {
            self.storage = bytes
        }

        public var count: Int { storage.count }

        /// Method form: the explicit `@_lifetime(borrow self)` is what the compiler asks for when
        /// the result is computed rather than a stored value. Enabled by the `Lifetimes` feature.
        @_lifetime(borrow self)
        public func view() -> Span<UInt8> {
            storage.span
        }

        /// Closure form: no lifetime annotations and no `~Escapable` result crossing a boundary.
        public func withBytes<R>(_ body: (Span<UInt8>) throws -> R) rethrows -> R {
            try body(storage.span)
        }

        /// The Phase 1 shape: a local span cursor over stored bytes.
        public func sumOfFirst(_ count: Int) -> Int {
            let bytes = storage.span
            var total = 0
            for index in 0..<Swift.min(count, bytes.count) { total += Int(bytes[index]) }
            return total
        }
    }

    /// Compile-time check for `Iterable` (SE-0516). Never called: the generic constraint is what
    /// has to resolve, since `Iterable` only constrains the declaration.
    @inline(never)
    public static func requiresIterable<T: Iterable>(_ value: borrowing T) -> Bool {
        true
    }

    /// Exercised by the test target. Returns the names of failed checks (empty == everything works).
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

        // --- Span views: method, closure, and local cursor -------------------------------------
        let borrowed = BorrowedBytes([1, 2, 3, 4, 5])
        check("Span from method", borrowed.view().count == 5 && borrowed.view()[2] == 3)
        check("Span via closure", borrowed.withBytes { $0.count } == 5)
        check("Span local cursor", borrowed.sumOfFirst(3) == 6)

        // --- Slice extraction + decoding (the Phase 1 value-view shape) ------------------------
        let source = Data([0x31, 0x32, 0x33, 0x34])   // "1234"
        let valueBytes = source.span
        check("Data.span", valueBytes.count == 4)
        check("Span.extracting", valueBytes.extracting(1..<3).count == 2)
        check("Data slice decode", String(decoding: source[1..<3], as: UTF8.self) == "23")

        // --- Array.span / Array.mutableSpan (the property, not a with-style function) ----------
        var array = [10, 20, 30]
        check("Array.span", array.span.count == 3)
        do {
            var mutable = array.mutableSpan
            mutable[0] = 99
        }
        check("Array.mutableSpan write-through", array[0] == 99)

        // --- RawSpan + the safe loading API (SE-0525) ------------------------------------------
        let data = Data([0x01, 0x00, 0x00, 0x00, 0xFF])
        let loaded: UInt32 = data.withUnsafeBytes { raw in
            RawSpan(_unsafeBytes: raw).load(fromByteOffset: 0, as: UInt32.self)
        }
        check("RawSpan.load", loaded == 1)
        check("RawSpan.byteCount", data.withUnsafeBytes { RawSpan(_unsafeBytes: $0).byteCount } == 5)

        // --- InlineArray: fixed-size inline storage -------------------------------------------
        var inline = InlineArray<4, Int>(repeating: 0)
        inline[1] = 7
        check("InlineArray", inline.count == 4 && inline[1] == 7 && inline.span.count == 4)

        // --- UniqueArray / UniqueBox: ownership without reference counting or CoW --------------
        var unique = UniqueArray<Int>()
        unique.append(3)
        unique.append(4)
        check("UniqueArray", unique.count == 2 && unique.span[1] == 4)

        let boxed = UniqueBox(41)
        check("UniqueBox", boxed.value == 41)
        var boxedMutable = UniqueBox(1)
        boxedMutable.value = 2
        check("UniqueBox mutation", boxedMutable.value == 2)

        // --- Ref / MutableRef: scoped borrows (SE-0519) ---------------------------------------
        var counter = 5
        let readOnly = Ref(counter)
        check("Ref", readOnly.value == 5)
        var mutable = MutableRef(&counter)
        mutable.value = 6
        check("MutableRef write-through", counter == 6)

        // --- withTemporaryAllocation: scratch buffer that is initialized and cleaned up -------
        // Note: the closure receives an `OutputSpan`, whose `count` starts at 0 — you fill it with
        // `append` (up to `capacity`), and `span` exposes what was appended. It is not a
        // pre-initialized indexed buffer.
        let scratchSum = withTemporaryAllocation(of: Int.self, capacity: 8) { buffer -> Int in
            for index in 0..<8 { buffer.append(index * 2) }
            var sum = 0
            for index in 0..<buffer.span.count { sum += buffer.span[index] }
            return sum
        }
        check("withTemporaryAllocation", scratchSum == 56)
        check("withTemporaryAllocation capacity", withTemporaryAllocation(of: Int.self, capacity: 3) { $0.capacity } == 3)

        return failures
    }
}
