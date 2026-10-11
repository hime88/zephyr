import Foundation
import Dispatch
import ZephyrCore

// =========================================================================
// MARK: - DXF numeric value parsing benchmark
// =========================================================================
//
// `DXFReader.d(_:)` / `i(_:)` are one-liners around `Double(String)` / `Int(String)`, and 484 call
// sites across 23 `parseX` functions go through them. This measures whether replacing them is worth
// it, on real values pulled out of a drawing rather than synthetic ones.
//
// Candidates, all available at a macOS 12 deployment target (no new stdlib API):
//   * `Double(s)`  — what ships today
//   * table-based ASCII parser over `String.UTF8View`, exact for |exp| <= 22 and <= 19 digits,
//     falling back to `Double(s)` outside that range
//
// Reports ns/op and, critically, whether the parser agrees with `Double(s)` bit-for-bit on the corpus.

extension Cases {

    /// Extracts numeric-looking value lines from a DXF (every other line is a value).
    static func dxfNumericCorpus(path: String, limit: Int = 400_000) -> [String] {
        guard let text = try? String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8) else {
            return []
        }
        var values: [String] = []
        values.reserveCapacity(limit)
        var isValueLine = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            isValueLine.toggle()
            guard isValueLine else { continue }
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let first = trimmed.first,
                  first.isNumber || first == "-" || first == "+" || first == ".",
                  trimmed.count <= 24 else { continue }
            values.append(trimmed)
            if values.count >= limit { break }
        }
        return values
    }

    /// Exact powers of ten, so `mantissa * 10^exp` is correctly rounded for |exp| <= 22.
    private static let pow10Table: [Double] = [
        1e0, 1e1, 1e2, 1e3, 1e4, 1e5, 1e6, 1e7, 1e8, 1e9, 1e10, 1e11,
        1e12, 1e13, 1e14, 1e15, 1e16, 1e17, 1e18, 1e19, 1e20, 1e21, 1e22,
    ]

    /// ASCII fast path. Returns nil when the value needs the general parser (huge exponent,
    /// too many digits, hex, "1.#INF", etc.) so the caller can fall back to `Double(s)`.
    @inline(__always)
    static func fastDouble(_ s: String) -> Double? {
        var mantissa: UInt64 = 0
        var digits = 0
        var exponent = 0
        var negative = false
        var seenDigit = false
        var i = s.utf8.startIndex

        if i < s.utf8.endIndex, s.utf8[i] == 0x2D { negative = true; i = s.utf8.index(after: i) }
        else if i < s.utf8.endIndex, s.utf8[i] == 0x2B { i = s.utf8.index(after: i) }

        while i < s.utf8.endIndex {
            let c = s.utf8[i]
            if c >= 0x30, c <= 0x39 {
                digits += 1
                if digits > 19 { return nil }
                mantissa = mantissa &* 10 &+ UInt64(c - 0x30)
                seenDigit = true
                i = s.utf8.index(after: i)
            } else {
                break
            }
        }

        if i < s.utf8.endIndex, s.utf8[i] == 0x2E {
            i = s.utf8.index(after: i)
            while i < s.utf8.endIndex {
                let c = s.utf8[i]
                guard c >= 0x30, c <= 0x39 else { break }
                digits += 1
                if digits > 19 { return nil }
                mantissa = mantissa &* 10 &+ UInt64(c - 0x30)
                exponent -= 1
                seenDigit = true
                i = s.utf8.index(after: i)
            }
        }

        guard seenDigit else { return nil }

        if i < s.utf8.endIndex, s.utf8[i] == 0x65 || s.utf8[i] == 0x45 {
            i = s.utf8.index(after: i)
            var expNegative = false
            if i < s.utf8.endIndex, s.utf8[i] == 0x2D { expNegative = true; i = s.utf8.index(after: i) }
            else if i < s.utf8.endIndex, s.utf8[i] == 0x2B { i = s.utf8.index(after: i) }
            var expDigits = 0
            var expValue = 0
            while i < s.utf8.endIndex {
                let c = s.utf8[i]
                guard c >= 0x30, c <= 0x39 else { return nil }
                expValue = expValue * 10 + Int(c - 0x30)
                expDigits += 1
                if expDigits > 3 { return nil }
                i = s.utf8.index(after: i)
            }
            guard expDigits > 0 else { return nil }
            exponent += expNegative ? -expValue : expValue
        }

        guard i == s.utf8.endIndex else { return nil }        // trailing junk
        guard exponent >= -22, exponent <= 22 else { return nil }

        var value = Double(mantissa)
        if exponent > 0 { value *= Self.pow10Table[exponent] } else if exponent < 0 { value /= Self.pow10Table[-exponent] }
        return negative ? -value : value
    }

    /// Runs the corpus through both parsers and reports timing plus equivalence.
    static func valueParseBenchmark(path: String) {
        let corpus = dxfNumericCorpus(path: path)
        guard corpus.count > 1000 else {
            print("no corpus (need a DXF with numeric values)")
            return
        }
        print("corpus: \(corpus.count) real DXF values")

        func time(_ label: String, _ body: ([String]) -> Double) {
            var best = Double.infinity
            var checksum = 0.0
            for _ in 0..<5 {
                let t0 = DispatchTime.now().uptimeNanoseconds
                checksum = body(corpus)
                let t1 = DispatchTime.now().uptimeNanoseconds
                best = min(best, Double(t1 - t0) / Double(corpus.count))
            }
            print(String(format: "%-34@ %8.2f ns/value   checksum %.6f",
                         label as NSString, best, checksum))
        }

        time("Double(String)  [ships today]") { values in
            var sum = 0.0
            for v in values { sum += Double(v) ?? 0 }
            return sum
        }

        time("fastDouble + fallback") { values in
            var sum = 0.0
            for v in values { sum += Self.fastDouble(v) ?? (Double(v) ?? 0) }
            return sum
        }

        time("fastDouble only (no fallback path)") { values in
            var sum = 0.0
            for v in values { sum += Self.fastDouble(v) ?? 0 }
            return sum
        }

        // Equivalence: every value must agree with Double(String) bit-for-bit.
        var mismatches = 0
        var fellBack = 0
        var worst = ""
        for v in corpus {
            guard let reference = Double(v) else { continue }
            guard let fast = Self.fastDouble(v) else { fellBack += 1; continue }
            if fast.bitPattern != reference.bitPattern {
                mismatches += 1
                if worst.isEmpty { worst = "\(v): fast=\(fast) ref=\(reference)" }
            }
        }
        print("equivalence: \(mismatches) bit mismatches, \(fellBack) fell back to Double(String)"
              + (worst.isEmpty ? "" : "  first: \(worst)"))
    }
}
