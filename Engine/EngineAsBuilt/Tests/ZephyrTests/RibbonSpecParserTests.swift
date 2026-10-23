import XCTest
import ZephyrLisp
@testable import ZephyrCore

/// Parser tests: real DSL source strings are evaluated with the shipped
/// prelude (so the authoring surface itself is covered), then parsed.
/// No engine, no window: the grammar is pure data in, data out.
@MainActor
final class RibbonSpecParserTests: XCTestCase {

    // MARK: - Harness

    private static let catalogCommands: Set<String> = [
        "LINE", "POLYLINE", "CIRCLE", "ARC", "RECTANGLE", "ELLIPSE",
        "MOVE", "ERASE", "TRIM", "OFFSET", "ARRAY", "GRID",
        "HATCH", "SPLINE",
        "NEW", "OPEN", "SAVE", "SAVEAS", "PDFEXPORT", "UNDO", "REDO",
        "LA", "ZOOMEXTENTS",
    ]

    private var catalog: RibbonCommandCatalog {
        RibbonCommandCatalog(known: Self.catalogCommands)
    }

    private func evaluate(_ body: String) async throws -> LispValue {
        let source = RibbonPrelude.source + "\n" + body
        let forms = try LispReader().readAll(source)
        var env = LispEnvironment()
        let host = LispCADHost(
            document: CADDocument(),
            selection: CADSelectionManager())
        host.output = { _ in }
        return try await LispEvaluator().run(forms, env: &env, host: host)
    }

    private func parse(
        _ body: String, known: Set<String>? = nil
    ) async throws -> RibbonSpecParseResult {
        let value = try await evaluate(body)
        return try RibbonSpecParser.parse(
            value,
            catalog: known.map { RibbonCommandCatalog(known: $0) } ?? catalog)
    }

    // MARK: - Structure and ordering

    func testParsesTabsPanelsAndOrdering() async throws {
        let result = try await parse(
            """
            (defun zephyr-ribbon ()
              (setq draw
                (zr-panel "Draw"
                  (list (zr-big "LINE" "Line" "line" nil)
                        (zr-big "POLYLINE" "Polyline" "polyline" nil)
                        (zr-small "CIRCLE" "Circle" "circle" nil))))
              (setq modify
                (zr-panel "Modify"
                  (list (zr-big "MOVE" "Move" "move" nil))))
              (setq nav
                (zr-panel "Navigate"
                  (list (zr-small "ZOOMEXTENTS" "Extents" "zoom" nil))))
              (setq home (zr-tab "Home" (list draw modify)))
              (setq view (zr-tab "View" (list nav)))
              (zr-ribbon nil (zr-tabs (list home view))))
            (zephyr-ribbon)
            """)

        XCTAssertEqual(result.warnings, [])
        XCTAssertEqual(result.spec.tabs.map(\.title), ["Home", "View"])
        XCTAssertEqual(result.spec.tabs[0].panels.map(\.title), ["Draw", "Modify"])

        let draw = result.spec.tabs[0].panels[0]
        XCTAssertEqual(draw.items.count, 3)
        guard case let .command(line) = draw.items[0],
              case let .command(polyline) = draw.items[1],
              case let .command(circle) = draw.items[2]
        else { return XCTFail("expected three commands") }
        // Order is preserved exactly as authored.
        XCTAssertEqual(line.command, "LINE")
        XCTAssertEqual(line.size, .large)
        XCTAssertEqual(polyline.command, "POLYLINE")
        XCTAssertEqual(circle.command, "CIRCLE")
        XCTAssertEqual(circle.size, .small)
        XCTAssertEqual(line.label, "Line")
        XCTAssertEqual(line.icon, "line")
    }

    func testNilIconAndLabelDeriveFromCommand() async throws {
        let result = try await parse(
            """
            (defun zephyr-ribbon ()
              (zr-ribbon nil
                (zr-tabs
                  (list (zr-tab "Home"
                    (list (zr-panel "Draw"
                      (list (zr-big "LINE" nil nil nil)))))))))
            (zephyr-ribbon)
            """)

        let panel = try XCTUnwrap(result.spec.tabs.first?.panels.first)
        guard case let .command(command) = try XCTUnwrap(panel.items.first) else {
            return XCTFail("expected a command item")
        }
        XCTAssertEqual(command.label, "LINE")
        XCTAssertNil(command.icon)
        XCTAssertEqual(command.resolvedIconName, "line")
    }

    func testRawListFormMatchesPreludeHelpers() async throws {
        // The prelude is convenience, not contract: hand-written lists parse
        // to the same model.
        let result = try await parse(
            """
            (defun zephyr-ribbon ()
              (list "ribbon" nil
                (list "tabs"
                  (list (list "tab" "Home"
                    (list (list "panel" "Draw"
                      (list (list "big" "LINE" "Line")
                            (list "sep")
                            (list "small" "CIRCLE" "Circle")))))))))
            (zephyr-ribbon)
            """)

        let panel = try XCTUnwrap(result.spec.tabs.first?.panels.first)
        XCTAssertEqual(panel.items.count, 3)
        XCTAssertEqual(panel.items[1], .separator)
    }

    // MARK: - Menubar

    func testParsesMenubarSeparatorsAndSubmenus() async throws {
        let result = try await parse(
            """
            (defun zephyr-ribbon ()
              (zr-ribbon
                (zr-menubar
                  (list
                    (zr-menu "File"
                      (list (zr-item "NEW" "New" nil)
                            (zr-sep)
                            (zr-sub "Export"
                              (list (zr-item "PDFEXPORT" "PDF..." nil)))))
                    (zr-menu "Edit"
                      (list (zr-item "UNDO" "Undo"
                              (list (zr-enable (zr-undoable))))))))
                nil))
            (zephyr-ribbon)
            """)

        XCTAssertEqual(result.warnings, [])
        XCTAssertEqual(result.spec.menus.map(\.title), ["File", "Edit"])
        XCTAssertTrue(result.spec.tabs.isEmpty)

        let file = result.spec.menus[0]
        XCTAssertEqual(file.items.count, 3)
        XCTAssertEqual(file.items[1], .separator)
        guard case let .dropdown(export) = file.items[2] else {
            return XCTFail("expected a submenu")
        }
        XCTAssertEqual(export.label, "Export")
        XCTAssertEqual(export.items.count, 1)

        let edit = result.spec.menus[1]
        guard case let .command(undo) = edit.items[0] else {
            return XCTFail("expected a command")
        }
        XCTAssertEqual(undo.enabled, [.undoAvailable])
    }

    // MARK: - Options and predicates

    func testParsesEnableCheckAndTooltipOptions() async throws {
        let result = try await parse(
            """
            (defun zephyr-ribbon ()
              (zr-ribbon nil
                (zr-tabs
                  (list (zr-tab "Home"
                    (list (zr-panel "Status"
                      (list
                        (zr-small "MOVE" "Move" "move"
                          (list (zr-enable (zr-sel 1))
                                (zr-tip "Move the selection")))
                        (zr-small "GRID" "Grid: %GRIDMODE%" "grid"
                          (list (zr-check (zr-var "GRIDMODE" 1))
                                (zr-enable (zr-nocmd))))))))))))
            (zephyr-ribbon)
            """)

        let panel = try XCTUnwrap(result.spec.tabs.first?.panels.first)
        guard case let .command(move) = panel.items[0],
              case let .command(grid) = panel.items[1]
        else { return XCTFail("expected two commands") }

        XCTAssertEqual(move.enabled, [.selectionAtLeast(1)])
        XCTAssertEqual(move.tooltip, "Move the selection")
        XCTAssertEqual(move.checked, [])
        XCTAssertEqual(grid.checked,
                       [.variableEquals(name: "GRIDMODE", value: .int(1))])
        XCTAssertEqual(grid.enabled, [.noActiveCommand])
        // Labels keep their tokens; interpolation is a render-time concern.
        XCTAssertEqual(grid.label, "Grid: %GRIDMODE%")
    }

    func testMultiplePredicatesInOneOption() async throws {
        // Built as LispValue data instead of source text: this pins the
        // "one option, several predicates" arm of the grammar without a
        // paren-counting exercise.
        func pred(_ name: String, _ extra: LispValue? = nil) -> LispValue {
            var items: [LispValue] = [.string(name)]
            if let extra { items.append(extra) }
            return LispValue(list: items)
        }
        let value = LispValue(list: [
            .string("ribbon"), .nilValue,
            LispValue(list: [
                .string("tabs"),
                LispValue(list: [
                    LispValue(list: [
                        .string("tab"), .string("Home"),
                        LispValue(list: [
                            LispValue(list: [
                                .string("panel"), .string("Edit"),
                                LispValue(list: [
                                    LispValue(list: [
                                        .string("small"),
                                        .string("ERASE"),
                                        .string("Erase"),
                                        .nilValue,
                                        LispValue(list: [
                                            LispValue(list: [
                                                .string("enable"),
                                                pred("sel", .int(1)),
                                                pred("nocmd"),
                                            ]),
                                        ]),
                                    ]),
                                ]),
                            ]),
                        ]),
                    ]),
                ]),
            ]),
        ])

        let result = try RibbonSpecParser.parse(value, catalog: catalog)
        let panel = try XCTUnwrap(result.spec.tabs.first?.panels.first)
        guard case let .command(erase) = panel.items.first else {
            return XCTFail("expected a command")
        }
        XCTAssertEqual(erase.enabled, [.selectionAtLeast(1), .noActiveCommand])
    }

    func testPredicatesAccumulateAcrossOptions() async throws {
        let result = try await parse(
            """
            (defun zephyr-ribbon ()
              (zr-ribbon nil
                (zr-tabs
                  (list (zr-tab "Home"
                    (list (zr-panel "Edit"
                      (list (zr-small "ERASE" "Erase" "erase"
                              (list (zr-enable (zr-sel 1))
                                    (zr-enable (zr-nocmd))))))))))))
            (zephyr-ribbon)
            """)

        let panel = try XCTUnwrap(result.spec.tabs.first?.panels.first)
        guard case let .command(erase) = panel.items.first else {
            return XCTFail("expected a command")
        }
        XCTAssertEqual(erase.enabled, [.selectionAtLeast(1), .noActiveCommand])
    }

    func testAllPredicateKinds() async throws {
        let result = try await parse(
            """
            (defun zephyr-ribbon ()
              (zr-ribbon nil
                (zr-tabs
                  (list (zr-tab "Home"
                    (list (zr-panel "P"
                      (list (zr-small "LINE" "a" nil (list (zr-enable (zr-cmd "TRIM"))))
                            (zr-small "LINE" "b" nil (list (zr-enable (zr-redoable))))
                            (zr-small "LINE" "c" nil (list (zr-enable (zr-dirty))))
                            (zr-small "LINE" "d" nil (list (zr-enable (zr-tabcount 2))))))))))))
            (zephyr-ribbon)
            """)

        let items = try XCTUnwrap(result.spec.tabs.first?.panels.first?.items)
        func enabled(_ index: Int) -> [RibbonPredicate]? {
            guard case let .command(command) = items[index] else { return nil }
            return command.enabled
        }
        XCTAssertEqual(enabled(0), [.activeCommand("TRIM")])
        XCTAssertEqual(enabled(1), [.redoAvailable])
        XCTAssertEqual(enabled(2), [.documentDirty])
        XCTAssertEqual(enabled(3), [.tabCountAtLeast(2)])
    }

    // MARK: - Dropdowns

    func testParsesDropdownWithChildren() async throws {
        let result = try await parse(
            """
            (defun zephyr-ribbon ()
              (zr-ribbon nil
                (zr-tabs
                  (list (zr-tab "Home"
                    (list (zr-panel "Draw"
                      (list (zr-big "LINE" "Line" "line" nil)
                            (zr-drop "More"
                              (list (zr-item "HATCH" "Hatch" nil)
                                    (zr-item "SPLINE" "Spline" nil)))))))))))
            (zephyr-ribbon)
            """)

        let panel = try XCTUnwrap(result.spec.tabs.first?.panels.first)
        guard case let .dropdown(drop) = panel.items[1] else {
            return XCTFail("expected a dropdown")
        }
        XCTAssertEqual(drop.label, "More")
        XCTAssertEqual(drop.items.count, 2)
        XCTAssertEqual(drop.icon, "hatch")  // derived from the first child
    }

    // MARK: - Validation

    func testUnknownCommandIsDroppedWithWarning() async throws {
        let result = try await parse(
            """
            (defun zephyr-ribbon ()
              (zr-ribbon nil
                (zr-tabs
                  (list (zr-tab "Home"
                    (list (zr-panel "Draw"
                      (list (zr-big "LINE" "Line" "line" nil)
                            (zr-big "MIRROR" "Mirror" "copy" nil)))))))))
            (zephyr-ribbon)
            """)

        let panel = try XCTUnwrap(result.spec.tabs.first?.panels.first)
        XCTAssertEqual(panel.items.count, 1, "unknown command must be dropped")
        XCTAssertEqual(result.warnings.count, 1)
        let warning = try XCTUnwrap(result.warnings.first)
        XCTAssertTrue(warning.contains("MIRROR"), warning)
        XCTAssertTrue(warning.contains("not available"), warning)
    }

    func testUnknownIconWarnsOnce() async throws {
        let result = try await parse(
            """
            (defun zephyr-ribbon ()
              (zr-ribbon nil
                (zr-tabs
                  (list (zr-tab "Home"
                    (list (zr-panel "Draw"
                      (list (zr-big "LINE" "Line" "zigzag" nil)
                            (zr-big "CIRCLE" "Circle" "zigzag" nil)))))))))
            (zephyr-ribbon)
            """)

        // Both items survive; the painter falls back to a letter placeholder.
        let panel = try XCTUnwrap(result.spec.tabs.first?.panels.first)
        XCTAssertEqual(panel.items.count, 2)
        let iconWarnings = result.warnings.filter { $0.contains("zigzag") }
        XCTAssertEqual(iconWarnings.count, 1, "warn once per unknown icon name")
    }

    func testEmptyPanelAndTabAreDropped() async throws {
        let result = try await parse(
            """
            (defun zephyr-ribbon ()
              (zr-ribbon nil
                (zr-tabs
                  (list (zr-tab "Empty" (list (zr-panel "Nothing"
                          (list (zr-big "MIRROR" "Mirror" "copy" nil)))))
                        (zr-tab "Home" (list (zr-panel "Draw"
                          (list (zr-big "LINE" "Line" "line" nil)))))))))
            (zephyr-ribbon)
            """)

        XCTAssertEqual(result.spec.tabs.map(\.title), ["Home"])
        XCTAssertTrue(result.warnings.contains { $0.contains("Empty") })
    }

    func testBadItemTagThrows() async throws {
        await assertParseError(
            """
            (defun zephyr-ribbon ()
              (zr-ribbon nil
                (zr-tabs (list (zr-tab "Home"
                  (list (zr-panel "Draw"
                    (list (list "widgit" "LINE" "Line")))))))))
            (zephyr-ribbon)
            """,
            contains: "unknown item tag")
    }

    func testBadPredicateThrows() async throws {
        await assertParseError(
            """
            (defun zephyr-ribbon ()
              (zr-ribbon nil
                (zr-tabs (list (zr-tab "Home"
                  (list (zr-panel "Draw"
                    (list (zr-small "LINE" "Line" nil
                      (list (list "enable" (list "whenever"))))))))))))
            (zephyr-ribbon)
            """,
            contains: "unknown predicate")
    }

    func testBadOptionThrows() async throws {
        await assertParseError(
            """
            (defun zephyr-ribbon ()
              (zr-ribbon nil
                (zr-tabs (list (zr-tab "Home"
                  (list (zr-panel "Draw"
                    (list (zr-small "LINE" "Line" nil
                      (list (list "sparkle" 1)))))))))))
            (zephyr-ribbon)
            """,
            contains: "unknown option")
    }

    func testMissingRibbonTagThrows() async throws {
        await assertParseError(
            """
            (defun zephyr-ribbon ()
              (list "tabs" (list)))
            (zephyr-ribbon)
            """,
            contains: "must return (zr-ribbon menubar tabs)")
    }

    func testNilResultThrows() async throws {
        await assertParseError(
            """
            (defun zephyr-ribbon () nil)
            (zephyr-ribbon)
            """,
            contains: "empty list")
    }

    func testEmptyDefinitionThrows() async throws {
        await assertParseError(
            """
            (defun zephyr-ribbon () (zr-ribbon nil nil))
            (zephyr-ribbon)
            """,
            contains: "no menus and no tabs")
    }

    func testMissingFunctionIsAnEvaluationError() async {
        // The loader reports this as "zephyr-ribbon is not defined"; here we
        // pin the evaluator's behaviour that makes that message possible.
        let source = RibbonPrelude.source + "\n(zephyr-ribbon)"
        do {
            let forms = try LispReader().readAll(source)
            var env = LispEnvironment()
            let host = LispCADHost(
                document: CADDocument(),
                selection: CADSelectionManager())
            host.output = { _ in }
            _ = try await LispEvaluator().run(forms, env: &env, host: host)
            XCTFail("expected an undefined-function error")
        } catch {
            XCTAssertTrue(
                "\(error)".uppercased().contains("ZEPHYR-RIBBON"),
                "error should name the missing function, got \(error)")
        }
    }

    // MARK: - Catalog

    func testCatalogResolvesAliasesAndLispRoutines() {
        let catalog = RibbonCommandCatalog(
            known: ["LINE", "LA", "MYTOOL"])
        XCTAssertTrue(catalog.contains("LINE"))
        XCTAssertTrue(catalog.contains("la"))
        XCTAssertTrue(catalog.contains("MYTOOL"))
        // Global-command prefixes are stripped like the scripted dispatcher.
        XCTAssertTrue(catalog.contains("_.LINE"))
        XCTAssertFalse(catalog.contains("MIRROR"))
    }

    func testCatalogFromDescriptorsIncludesAliases() {
        let catalog = RibbonCommandCatalog.fromCurrentApp(
            lispFunctions: ["C:HELLOWORLD"])
        XCTAssertTrue(catalog.contains("LINE"))
        XCTAssertTrue(catalog.contains("HELLOWORLD"))
        XCTAssertFalse(catalog.contains("C:HELLOWORLD"))
    }

    func testDuplicateTabIsIgnored() async throws {
        let result = try await parse(
            """
            (defun zephyr-ribbon ()
              (zr-ribbon nil
                (zr-tabs
                  (list (zr-tab "Home" (list (zr-panel "Draw"
                          (list (zr-big "LINE" "Line" "line" nil)))))
                        (zr-tab "Home" (list (zr-panel "Draw"
                          (list (zr-big "CIRCLE" "Circle" "circle" nil)))))))))
            (zephyr-ribbon)
            """)

        XCTAssertEqual(result.spec.tabs.count, 1)
        XCTAssertTrue(result.warnings.contains { $0.contains("duplicate tab") })
    }

    // MARK: - Helpers

    private func assertParseError(
        _ body: String, contains fragment: String,
        file: StaticString = #filePath, line: UInt = #line
    ) async {
        do {
            _ = try await parse(body)
            XCTFail(
                "expected a parse error containing \"\(fragment)\"",
                file: file, line: line)
        } catch let error as RibbonSpecError {
            XCTAssertTrue(
                error.message.contains(fragment),
                "expected \"\(fragment)\", got \"\(error.message)\"",
                file: file, line: line)
        } catch {
            XCTFail("unexpected error: \(error)", file: file, line: line)
        }
    }
}
