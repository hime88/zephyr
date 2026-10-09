// Swift 6.4 `get` vs `borrow` vs `mutate` benchmark.
//
// Build and run (Windows, no package build needed):
//   swiftc -O -parse-as-library -swift-version 6 borrow-accessors.swift -o borrow-accessors.exe && ./borrow-accessors.exe
// macOS:
//   swiftc -O -parse-as-library -swift-version 6 borrow-accessors.swift -o borrow-accessors && ./borrow-accessors
//
// Why the harness looks like this (the first two attempts were invalid):
//   * every result is sunk through `@inline(never) func sink(_:)` so nothing is eliminated;
//   * the accessor is `@inline(never)` and the index varies per iteration, so the call cannot be
//     hoisted out of the loop — an earlier version measured a 32 KB copy at 0.9 ns, which is how the
//     hoisting bug was caught;
//   * `main` prints a sentinel after the write cases to prove the writes actually landed.
//
// Reference numbers (Windows 11 ARM64, Swift 6.4, -O, best of 7) live in plans/swift-6.4-baseline.md.
// The headline result is the write case: `get`+`set` on an 8 KB value costs two 8 KB copies per single
// element write (≈181 ns), while `mutate` compiles to one `str` (≈0.92 ns) — ~197×.

import Foundation
import Dispatch

@inline(never) func sink(_ x: Double) -> Double { x * 1.0000001 }

// MARK: - 8 KB inline storage

struct BigGet {
    private var storage = InlineArray<1024, Double>(repeating: 1.5)
    @inline(never) var view: InlineArray<1024, Double> { get { return storage } }
}

struct BigBorrow {
    private var storage = InlineArray<1024, Double>(repeating: 1.5)
    @inline(never) var view: InlineArray<1024, Double> { borrow { return storage } }
}

@inline(never) func elementViaGet(_ s: BigGet, _ index: Int) -> Double { sink(s.view[index]) }
@inline(never) func elementViaBorrow(_ s: BigBorrow, _ index: Int) -> Double { sink(s.view[index]) }

@inline(never) func sweepViaGet(_ s: BigGet) -> Double {
    var acc = 0.0
    for i in 0..<1024 { acc += sink(s.view[i]) }
    return acc
}

@inline(never) func sweepViaBorrow(_ s: BigBorrow) -> Double {
    var acc = 0.0
    for i in 0..<1024 { acc += sink(s.view[i]) }
    return acc
}

// MARK: - `Array`-backed storage (retain/release rather than a deep copy)

struct ArrayGet {
    private var storage = [Double](repeating: 1.5, count: 1024)
    @inline(never) var view: [Double] { get { return storage } }
}

struct ArrayBorrow {
    private var storage = [Double](repeating: 1.5, count: 1024)
    @inline(never) var view: [Double] { borrow { return storage } }
}

@inline(never) func elementViaArrayGet(_ s: ArrayGet, _ index: Int) -> Double { sink(s.view[index]) }
@inline(never) func elementViaArrayBorrow(_ s: ArrayBorrow, _ index: Int) -> Double { sink(s.view[index]) }

// MARK: - 128-byte struct (the shape of Zephyr's Transform3D)

struct Matrix16 {
    var m: (Double, Double, Double, Double, Double, Double, Double, Double,
            Double, Double, Double, Double, Double, Double, Double, Double)
    init() { m = (1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1) }
}

struct MatrixGet {
    private var storage = Matrix16()
    @inline(never) var value: Matrix16 { get { return storage } }
}

struct MatrixBorrow {
    private var storage = Matrix16()
    @inline(never) var value: Matrix16 { borrow { return storage } }
}

@inline(never) func elementViaMatrixGet(_ s: MatrixGet, _ index: Int) -> Double { sink(s.value.m.3) }
@inline(never) func elementViaMatrixBorrow(_ s: MatrixBorrow, _ index: Int) -> Double { sink(s.value.m.3) }

// MARK: - Nested write: get + set round trip vs mutate

struct WriteGet {
    private var storage = InlineArray<1024, Double>(repeating: 1.5)
    @inline(never) var view: InlineArray<1024, Double> {
        get { return storage }
        set { storage = newValue }
    }
}

struct WriteMutate {
    private var storage = InlineArray<1024, Double>(repeating: 1.5)
    @inline(never) var view: InlineArray<1024, Double> {
        borrow { return storage }
        mutate { return &storage }
    }
}

@inline(never) func writeViaGetSet(_ s: inout WriteGet, _ index: Int, _ value: Double) {
    var v = s.view
    v[index] = value
    s.view = v
}

@inline(never) func writeViaMutate(_ s: inout WriteMutate, _ index: Int, _ value: Double) {
    s.view[index] = value
}

// MARK: - Runner

@main
struct BorrowAccessorBench {
    static func time(_ label: String, iterations: Int, _ body: (Int) -> Double) {
        var warmup = 0.0
        for i in 0..<1000 { warmup += body(i) }          // also proves the call is not eliminated
        var best = Double.infinity
        for _ in 0..<7 {
            let t0 = DispatchTime.now().uptimeNanoseconds
            var inner = 0.0
            for i in 0..<iterations { inner += body(i) }
            let t1 = DispatchTime.now().uptimeNanoseconds
            if inner.isNaN { fatalError("optimized away") }
            best = min(best, Double(t1 - t0) / Double(iterations))
        }
        print(String(format: "%-42@ %9.2f ns/op", label as NSString, best))
        _ = warmup
    }

    static func main() {
        let bigGet = BigGet(), bigBorrow = BigBorrow()
        let arrayGet = ArrayGet(), arrayBorrow = ArrayBorrow()
        let matrixGet = MatrixGet(), matrixBorrow = MatrixBorrow()
        var writeGet = WriteGet(), writeMutate = WriteMutate()

        print("=== read: copy-through-get vs borrow ===")
        time("InlineArray<1024> 8KB get   s.view[i]", iterations: 500_000) { elementViaGet(bigGet, $0 & 1023) }
        time("InlineArray<1024> 8KB borrow s.view[i]", iterations: 500_000) { elementViaBorrow(bigBorrow, $0 & 1023) }
        time("InlineArray<1024> sweep get", iterations: 20_000) { _ in sweepViaGet(bigGet) }
        time("InlineArray<1024> sweep borrow", iterations: 20_000) { _ in sweepViaBorrow(bigBorrow) }
        time("Array<Double> 8KB get   s.view[i]", iterations: 2_000_000) { elementViaArrayGet(arrayGet, $0 & 1023) }
        time("Array<Double> 8KB borrow s.view[i]", iterations: 2_000_000) { elementViaArrayBorrow(arrayBorrow, $0 & 1023) }
        time("Matrix16 128B get", iterations: 2_000_000) { elementViaMatrixGet(matrixGet, $0) }
        time("Matrix16 128B borrow", iterations: 2_000_000) { elementViaMatrixBorrow(matrixBorrow, $0) }

        print("=== write: get+set round trip vs mutate ===")
        time("InlineArray write get+set", iterations: 200_000) { writeViaGetSet(&writeGet, $0 & 1023, Double($0)); return 0 }
        time("InlineArray write mutate", iterations: 200_000) { writeViaMutate(&writeMutate, $0 & 1023, Double($0)); return 0 }
        print("sentinel (both must differ from 1.5):", writeGet.view[3], writeMutate.view[3])
    }
}
