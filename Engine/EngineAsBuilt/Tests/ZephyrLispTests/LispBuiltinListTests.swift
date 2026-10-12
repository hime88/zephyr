import XCTest
@testable import ZephyrLisp

final class LispBuiltinListTests: XCTestCase {
    func testConsCarCdr() async throws {
        try await assertEval("(cons 1 2)", .cons(head: .int(1), tail: .int(2)))
        try await assertEval("(car '(1 2))", .int(1))
        try await assertEval("(cdr '(1 2))", LispValue(list: [.int(2)]))
        try await assertEval("(car nil)", .nilValue)
        try await assertEval("(cdr nil)", .nilValue)
        try await assertEval("(car '(0 . \"LINE\"))", .int(0))
        try await assertEval("(cdr '(0 . \"LINE\"))", .string("LINE"))
        try await assertEval("(cadr '(1 2 3))", .int(2))
        try await assertEval("(caddr '(1 2 3))", .int(3))
        try await assertEval("(cadr nil)", .nilValue)
        try await assertEval("(list 1 2)", LispValue(list: [.int(1), .int(2)]))
        try await assertEval("(list)", .nilValue)
    }

    func testLastLengthNth() async throws {
        // AutoLISP last returns the element, not a list (step 4e oracle).
        try await assertEval("(last '(1 2))", .int(2))
        try await assertEval("(last nil)", .nilValue)
        try await assertEval("(length '(1 2 3))", .int(3))
        try await assertEval("(length nil)", .int(0))
        try await assertEval("(nth 0 '(a b))", .symbol("A"))
        try await assertEval("(nth 1 '(a b))", .symbol("B"))
        try await assertEval("(nth 5 '(a b))", .nilValue)
        try await assertEval("(nth -1 '(a b))", .nilValue)
    }

    func testAppendReverse() async throws {
        try await assertEval(
            "(append '(1) '(2 3) nil)",
            LispValue(list: [.int(1), .int(2), .int(3)]))
        try await assertEval("(append)", .nilValue)
        try await assertEval(
            "(append '(1) 2)", .cons(head: .int(1), tail: .int(2)))
        try await assertEval(
            "(reverse '(1 2 3))", LispValue(list: [.int(3), .int(2), .int(1)]))
    }

    func testMemberAssoc() async throws {
        try await assertEval(
            "(member 2 '(1 2 3))", LispValue(list: [.int(2), .int(3)]))
        try await assertEval("(member 9 '(1 2 3))", .nilValue)
        try await assertEval(
            "(assoc 0 '((0 . \"LINE\") (8 . \"0\")))",
            .cons(head: .int(0), tail: .string("LINE")))
        try await assertEval("(assoc 7 '((0 . \"LINE\")))", .nilValue)
    }

    func testSubstRecursive() async throws {
        try await assertEval(
            "(subst 'x 'a '(a b (a c)))",
            LispValue(list: [
                .symbol("X"), .symbol("B"),
                LispValue(list: [.symbol("X"), .symbol("C")]),
            ]))
        // No match: structurally identical copy.
        try await assertEval("(subst 'x 'z '(a))", LispValue(list: [.symbol("A")]))
    }

    func testVlListUtilities() async throws {
        try await assertEval(
            "(vl-list* 1 2 3)",
            .cons(head: .int(1), tail: .cons(head: .int(2), tail: .int(3))))
        try await assertEval("(vl-list-length '(1 2))", .int(2))
        try await assertEval("(vl-list-length '(1 . 2))", .nilValue)
        try await assertEval("(vl-list->string '(65 66))", .string("AB"))
        try await assertEval("(vl-consp '(1))", .symbol("T"))
        try await assertEval("(vl-consp nil)", .nilValue)
        try await assertEval("(vl-position 'c '(a b c))", .int(2))
        try await assertEval("(vl-position 'z '(a b c))", .nilValue)
        try await assertEval(
            "(vl-remove 2 '(1 2 3 2))", LispValue(list: [.int(1), .int(3)]))
    }

    func testVlPredicates() async throws {
        try await assertEval("(vl-every 'numberp '(1 2 3))", .symbol("T"))
        try await assertEval("(vl-every 'numberp '(1 a))", .nilValue)
        try await assertEval("(vl-some 'numberp '(a 2))", .symbol("T"))
        try await assertEval("(vl-some 'numberp '(a b))", .nilValue)
        try await assertEval(
            "(vl-member-if 'numberp '(a 2 b))", LispValue(list: [.int(2), .symbol("B")]))
        try await assertEval(
            "(vl-member-if-not 'numberp '(1 a b))",
            LispValue(list: [.symbol("A"), .symbol("B")]))
        try await assertEval(
            "(vl-remove-if 'numberp '(1 a 2 b))",
            LispValue(list: [.symbol("A"), .symbol("B")]))
        try await assertEval(
            "(vl-remove-if-not 'numberp '(1 a 2 b))",
            LispValue(list: [.int(1), .int(2)]))
    }

    func testVlSort() async throws {
        try await assertEval(
            "(vl-sort '(3 1 2) '<)", LispValue(list: [.int(1), .int(2), .int(3)]))
        try await assertEval(
            "(vl-sort-i '(30 10 20) '<)", LispValue(list: [.int(1), .int(2), .int(0)]))
    }
}
