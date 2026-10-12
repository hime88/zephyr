import XCTest
@testable import ZephyrLisp

final class LispReaderTests: XCTestCase {
    private let reader = LispReader()

    func testAtoms() throws {
        XCTAssertEqual(try reader.readAll("nil"), [.nilValue])
        XCTAssertEqual(try reader.readAll("42"), [.int(42)])
        XCTAssertEqual(try reader.readAll("-7"), [.int(-7)])
        XCTAssertEqual(try reader.readAll("3.5"), [.real(3.5)])
        XCTAssertEqual(try reader.readAll("1e3"), [.real(1000)])
        XCTAssertEqual(try reader.readAll("\"hi\""), [.string("hi")])
        XCTAssertEqual(try reader.readAll("foo"), [.symbol("FOO")])
        XCTAssertEqual(try reader.readAll("T"), [.symbol("T")])
    }

    func testSymbolCaseNormalization() throws {
        XCTAssertEqual(try reader.readAll("FooBar"), [.symbol("FOOBAR")])
        // Strings keep their case.
        XCTAssertEqual(try reader.readAll("\"FooBar\""), [.string("FooBar")])
    }

    func testIntegersWrapAt32Bits() throws {
        XCTAssertEqual(try reader.readAll("2147483648"), [.int(Int(Int32.min))])
    }

    func testNonNumbersStaySymbols() throws {
        XCTAssertEqual(try reader.readAll("1a"), [.symbol("1A")])
        XCTAssertEqual(try reader.readAll("--"), [.symbol("--")])
        XCTAssertEqual(try reader.readAll("1e"), [.symbol("1E")])
        XCTAssertEqual(try reader.readAll("e10"), [.symbol("E10")])
    }

    func testStringEscapes() throws {
        XCTAssertEqual(try reader.readAll("\"a\\\"b\""), [.string("a\"b")])
        XCTAssertEqual(try reader.readAll("\"a\\\\b\""), [.string("a\\b")])
        XCTAssertEqual(try reader.readAll("\"a\\nb\""), [.string("a\nb")])
    }

    func testQuoteSugar() throws {
        XCTAssertEqual(
            try reader.readAll("'x"),
            [LispValue(list: [.symbol("QUOTE"), .symbol("X")])])
        XCTAssertEqual(
            try reader.readAll("'(1 2)"),
            [LispValue(list: [.symbol("QUOTE"), LispValue(list: [.int(1), .int(2)])])])
    }

    func testCommentsAndWhitespace() throws {
        XCTAssertEqual(
            try reader.readAll("  ; leading comment\n 42 ; trailing"),
            [.int(42)])
        XCTAssertEqual(try reader.readAll(""), [])
        XCTAssertEqual(try reader.readAll("  ; only a comment\n"), [])
    }

    func testNestedLists() throws {
        XCTAssertEqual(
            try reader.readAll("(defun f (x) (+ x 1))"),
            [LispValue(list: [
                .symbol("DEFUN"), .symbol("F"),
                LispValue(list: [.symbol("X")]),
                LispValue(list: [.symbol("+"), .symbol("X"), .int(1)]),
            ])])
    }

    func testDottedPairs() throws {
        XCTAssertEqual(
            try reader.readAll("(0 . \"LINE\")"),
            [.cons(head: .int(0), tail: .string("LINE"))])
        XCTAssertEqual(
            try reader.readAll("(1 2 . 3)"),
            [.cons(head: .int(1), tail: .cons(head: .int(2), tail: .int(3)))])
        // A dot inside a symbol is not dotted syntax.
        XCTAssertEqual(try reader.readAll("a.b"), [.symbol("A.B")])
    }

    func testEntgetStyleAssocList() throws {
        let forms = try reader.readAll("((0 . \"LINE\") (10 1.0 2.0 0.0))")
        XCTAssertEqual(forms.count, 1)
        XCTAssertTrue(forms[0].isProperList)
        XCTAssertEqual(forms[0].prin1String, "((0 . \"LINE\") (10 1.0 2.0 0.0))")
    }

    func testMultipleTopLevelForms() throws {
        XCTAssertEqual(try reader.readAll("1 2 (3)").count, 3)
    }

    func testUnbalancedCloseParenErrors() {
        XCTAssertThrowsError(try reader.readAll("(1 2")) { error in
            guard let lispError = error as? LispError,
                case let .reader(message, line, column) = lispError
            else {
                return XCTFail("wrong error: \(error)")
            }
            XCTAssertTrue(message.contains("missing )"), message)
            XCTAssertEqual(line, 1)
            XCTAssertEqual(column, 5)
        }
    }

    func testStrayCloseParenErrorsWithPosition() {
        XCTAssertThrowsError(try reader.readAll("1\n)")) { error in
            guard let lispError = error as? LispError,
                case let .reader(_, line, column) = lispError
            else {
                return XCTFail("wrong error: \(error)")
            }
            XCTAssertEqual(line, 2)
            XCTAssertEqual(column, 1)
        }
    }

    func testUnterminatedStringErrors() {
        XCTAssertThrowsError(try reader.readAll("\"abc")) { error in
            guard let lispError = error as? LispError,
                case let .reader(message, _, _) = lispError
            else {
                return XCTFail("wrong error: \(error)")
            }
            XCTAssertTrue(message.contains("unterminated"), message)
        }
    }

    func testReadOneEmptyYieldsNil() throws {
        XCTAssertEqual(try reader.readOne(""), .nilValue)
        XCTAssertEqual(try reader.readOne("  ; nothing"), .nilValue)
    }
}
