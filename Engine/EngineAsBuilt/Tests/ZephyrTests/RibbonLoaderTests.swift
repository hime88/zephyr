import XCTest
import ZephyrLisp
@testable import ZephyrCore

/// Loader tests: the AutoLISP definition is evaluated off-actor and its
/// outcome crosses back through the frame pump. These cover the failure
/// policy (last good model stays live), validation warnings, the
/// single-flight guard, undo hygiene, and the prompting-definition timeout.
@MainActor
final class RibbonLoaderTests: XCTestCase {

    private var engineDocument: CADDocument!
    private var selection: CADSelectionManager!
    private var processor: CADCommandProcessor!
    private var loader: RibbonSpecLoader!
    private var output: String = ""

    /// Builds the fixture. Called at the top of every test: XCTest's
    /// nonisolated `setUp()` cannot touch MainActor state under Swift 6.
    private func makeFixture() {
        engineDocument = CADDocument()
        engineDocument.addLayer(Layer(name: "0"))
        engineDocument.activeLayerID =
            engineDocument.findLayer(named: "0")?.handle
        selection = CADSelectionManager()
        processor = CADCommandProcessor()
        loader = makeLoader()
    }

    private func makeLoader() -> RibbonSpecLoader {
        let loader = RibbonSpecLoader(
            processor: processor,
            documentProvider: { [unowned self] in self.engineDocument },
            selectionProvider: { [unowned self] in self.selection })
        loader.autoReloadEnabled = false
        loader.output = { [weak self] text in self?.output += text }
        return loader
    }

    private static let goodSource = """
    (defun zephyr-ribbon ()
      (zr-ribbon nil
        (zr-tabs
          (list (zr-tab "TestTab"
            (list (zr-panel "Draw"
              (list (zr-big "LINE" "Line" "line" nil)
                    (zr-small "CIRCLE" "Circle" "circle" nil)))))))))
    (zephyr-ribbon)
    """

    // MARK: - Happy path

    func testSuccessfulLoadReplacesSpec() async {
        makeFixture()
        XCTAssertEqual(loader.spec.tabs.first?.title, "Home",
                       "the fallback model is live before any load")

        loader.beginLoad(source: Self.goodSource, path: "test://ribbon.lsp")
        await loader.waitForLoad()

        XCTAssertEqual(loader.status, .loaded)
        XCTAssertNil(loader.errorMessage)
        XCTAssertEqual(loader.spec.tabs.map(\.title), ["TestTab"])
        let panel = loader.spec.tabs.first?.panels.first
        XCTAssertEqual(panel?.items.count, 2)
        XCTAssertEqual(loader.warnings, [])
        XCTAssertTrue(output.contains("loaded 1 tab"), output)
    }

    func testPreludeHelpersAreAvailableToTheDefinition() async {
        makeFixture()
        // The source uses zr-* helpers without defining them: the prelude must
        // be prepended on every load.
        loader.beginLoad(source: Self.goodSource, path: "test://ribbon.lsp")
        await loader.waitForLoad()
        XCTAssertEqual(loader.status, .loaded)
    }

    func testDefinitionCanCallUserSessionHelpers() async {
        makeFixture()
        // A definition may reuse helpers the user already loaded.
        processor.lispSession.functions["MY-TITLE"] = LispFunction(
            params: [], locals: [],
            body: [try! LispReader().readAll("(list \"Custom\")")[0]],
            quotedForm: nil)
        loader.beginLoad(
            source: """
            (defun zephyr-ribbon ()
              (zr-ribbon nil
                (zr-tabs
                  (list (zr-tab (car (my-title))
                    (list (zr-panel "P"
                      (list (zr-big "LINE" "Line" "line" nil)))))))))
            (zephyr-ribbon)
            """,
            path: "test://ribbon.lsp")
        await loader.waitForLoad()

        XCTAssertEqual(loader.status, .loaded)
        XCTAssertEqual(loader.spec.tabs.first?.title, "Custom")
    }

    // MARK: - Failure policy

    func testParseFailureKeepsPreviousModel() async {
        makeFixture()
        loader.beginLoad(source: Self.goodSource, path: "test://good.lsp")
        await loader.waitForLoad()
        let good = loader.spec
        XCTAssertEqual(loader.status, .loaded)

        loader.beginLoad(
            source: """
            (defun zephyr-ribbon () (zr-ribbon nil nil))
            (zephyr-ribbon)
            """,
            path: "test://bad.lsp")
        await loader.waitForLoad()

        XCTAssertEqual(loader.status, .failed)
        XCTAssertEqual(loader.spec, good, "the last good model must stay live")
        let message = try? XCTUnwrap(loader.errorMessage)
        XCTAssertTrue(
            (message ?? "").contains("no menus and no tabs"), message ?? "nil")
        XCTAssertTrue(output.contains("keeping the previous definition"), output)
    }

    func testSyntaxErrorKeepsPreviousModel() async {
        makeFixture()
        loader.beginLoad(source: Self.goodSource, path: "test://good.lsp")
        await loader.waitForLoad()
        let good = loader.spec

        loader.beginLoad(
            source: "(defun zephyr-ribbon () (zr-ribbon nil ",  // unbalanced
            path: "test://broken.lsp")
        await loader.waitForLoad()

        XCTAssertEqual(loader.status, .failed)
        XCTAssertEqual(loader.spec, good)
    }

    func testEvaluationErrorKeepsPreviousModel() async {
        makeFixture()
        loader.beginLoad(source: Self.goodSource, path: "test://good.lsp")
        await loader.waitForLoad()
        let good = loader.spec

        loader.beginLoad(
            source: "(car 1 2 3)",  // arity error inside the definition file
            path: "test://error.lsp")
        await loader.waitForLoad()

        XCTAssertEqual(loader.status, .failed)
        XCTAssertEqual(loader.spec, good)
        XCTAssertNotNil(loader.errorMessage)
    }

    func testUnknownCommandIsReportedButLoadSucceeds() async {
        makeFixture()
        loader.beginLoad(
            source: """
            (defun zephyr-ribbon ()
              (zr-ribbon nil
                (zr-tabs
                  (list (zr-tab "Home"
                    (list (zr-panel "Draw"
                      (list (zr-big "LINE" "Line" "line" nil)
                            (zr-big "NOSUCHCOMMAND" "Nope" "line" nil)))))))))
            (zephyr-ribbon)
            """,
            path: "test://ribbon.lsp")
        await loader.waitForLoad()

        XCTAssertEqual(loader.status, .loaded)
        XCTAssertEqual(loader.spec.tabs.first?.panels.first?.items.count, 1)
        XCTAssertEqual(loader.warnings.count, 1)
        XCTAssertTrue(loader.warnings[0].contains("NOSUCHCOMMAND"))
        XCTAssertTrue(output.contains("NOSUCHCOMMAND"), output)
    }

    // MARK: - Hygiene

    func testLoadPushesNoUndoEntriesAndClosesGroups() async {
        makeFixture()
        let before = engineDocument.undoManager.undoDepth
        loader.beginLoad(
            source: """
            (vla-startundomark) ; a definition must not leave an undo group open
            (defun zephyr-ribbon ()
              (zr-ribbon nil
                (zr-tabs
                  (list (zr-tab "Home"
                    (list (zr-panel "Draw"
                      (list (zr-big "LINE" "Line" "line" nil)))))))))
            (zephyr-ribbon)
            """,
            path: "test://ribbon.lsp")
        await loader.waitForLoad()

        XCTAssertEqual(loader.status, .loaded)
        XCTAssertEqual(engineDocument.undoManager.undoGroupDepth, 0,
                       "the load must not leave an undo group open")
        XCTAssertEqual(engineDocument.undoManager.undoDepth, before,
                       "a definition load must not push undo history")
    }

    func testInvocationDepthIsReleasedAfterLoad() async {
        makeFixture()
        loader.beginLoad(source: Self.goodSource, path: "test://ribbon.lsp")
        XCTAssertEqual(processor.lispInvocationDepth, 1,
                       "the load claims the single-flight slot")
        await loader.waitForLoad()
        XCTAssertEqual(processor.lispInvocationDepth, 0)
        XCTAssertFalse(loader.isLoading)
    }

    func testInvocationDepthIsReleasedAfterFailure() async {
        makeFixture()
        loader.beginLoad(source: "(car 1 2 3)", path: "test://error.lsp")
        await loader.waitForLoad()
        XCTAssertEqual(processor.lispInvocationDepth, 0)
        XCTAssertFalse(loader.isLoading)
    }

    // MARK: - Single-flight

    func testReloadIsDeferredWhileLispIsRunning() async {
        makeFixture()
        processor.lispInvocationDepth = 1  // pretend a routine is running
        loader.beginLoad(source: Self.goodSource, path: "test://ribbon.lsp")

        XCTAssertFalse(loader.isLoading, "must not start while LISP is running")
        XCTAssertEqual(processor.lispInvocationDepth, 1, "slot is untouched")
        XCTAssertEqual(loader.status, .idle)

        // Releasing the slot lets the queued request through.
        processor.lispInvocationDepth = 0
        loader.beginLoad(source: Self.goodSource, path: "test://ribbon.lsp")
        await loader.waitForLoad()
        XCTAssertEqual(loader.status, .loaded)
    }

    func testRequestReloadIsDeferredWhileLispIsRunning() async throws {
        makeFixture()
        let file = try writeTempDefinition(Self.goodSource)
        defer { try? FileManager.default.removeItem(at: file) }
        loader.definitionURLProvider = { file }

        processor.lispInvocationDepth = 1
        loader.requestReload(reason: "test")
        XCTAssertFalse(loader.isLoading)
        XCTAssertEqual(loader.status, .idle)

        // poll() retries the queued request once the slot frees up.
        processor.lispInvocationDepth = 0
        loader.poll()
        await loader.waitForLoad()
        XCTAssertEqual(loader.status, .loaded)
        XCTAssertEqual(loader.spec.tabs.map(\.title), ["TestTab"])
    }

    // MARK: - Prompting definition timeout

    func testPromptingDefinitionTimesOutAndReleasesTheSlot() async {
        makeFixture()
        loader.loadTimeout = 0.2
        loader.beginLoad(
            source: """
            (getpoint "Pick something")
            (defun zephyr-ribbon () (zr-ribbon nil (zr-tabs (list))))
            (zephyr-ribbon)
            """,
            path: "test://prompt.lsp")
        await loader.waitForLoad(timeout: 3)

        XCTAssertFalse(loader.isLoading)
        XCTAssertEqual(loader.status, .failed)
        XCTAssertEqual(processor.lispInvocationDepth, 0,
                       "a stuck definition must not freeze every command")
        XCTAssertTrue(
            (loader.errorMessage ?? "").contains("did not finish"),
            loader.errorMessage ?? "nil")
    }

    // MARK: - File resolution

    func testMissingDefinitionFileFailsWithoutChangingTheModel() {
        makeFixture()
        loader.definitionURLProvider = { nil }
        let before = loader.spec
        loader.requestReload(reason: "test")

        XCTAssertEqual(loader.status, .failed)
        XCTAssertEqual(loader.spec, before)
        XCTAssertTrue(
            (loader.errorMessage ?? "").contains("no ribbon definition"),
            loader.errorMessage ?? "nil")
    }

    func testUnreadableDefinitionFileFailsCleanly() {
        makeFixture()
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("does-not-exist-\(UUID().uuidString).lsp")
        loader.definitionURLProvider = { missing }
        loader.requestReload(reason: "test")

        XCTAssertEqual(loader.status, .failed)
        XCTAssertTrue(
            (loader.errorMessage ?? "").contains("cannot read"),
            loader.errorMessage ?? "nil")
    }

    func testResolvedDefinitionURLPrefersUserFile() throws {
        makeFixture()
        let user = try writeTempDefinition("(defun zephyr-ribbon () nil)")
        let bundled = try writeTempDefinition("(defun zephyr-ribbon () nil)")
        defer {
            try? FileManager.default.removeItem(at: user)
            try? FileManager.default.removeItem(at: bundled)
        }
        XCTAssertEqual(
            RibbonSpecLoader.resolvedDefinitionURL(
                userFile: user, bundled: bundled)?.path,
            user.path)
    }

    func testResolvedDefinitionURLFallsBackToBundled() throws {
        makeFixture()
        let bundled = try writeTempDefinition("(defun zephyr-ribbon () nil)")
        defer { try? FileManager.default.removeItem(at: bundled) }
        let missingUser = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString).lsp")
        XCTAssertEqual(
            RibbonSpecLoader.resolvedDefinitionURL(
                userFile: missingUser, bundled: bundled)?.path,
            bundled.path)
    }

    func testResolvedDefinitionURLIsNilWhenNeitherExists() {
        makeFixture()
        let temp = FileManager.default.temporaryDirectory
        XCTAssertNil(
            RibbonSpecLoader.resolvedDefinitionURL(
                userFile: temp.appendingPathComponent("a-\(UUID()).lsp"),
                bundled: temp.appendingPathComponent("b-\(UUID()).lsp")))
    }

    func testSeedCopiesBundledDefinitionIntoUserLocation() throws {
        makeFixture()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ribbon-seed-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let bundled = directory.appendingPathComponent("bundled.lsp")
        let target = directory
            .appendingPathComponent("nested/lisp/user.lsp")
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        try "(defun zephyr-ribbon () nil)".write(
            to: bundled, atomically: true, encoding: .utf8)

        let seeded = RibbonSpecLoader.seed(from: bundled, to: target)

        XCTAssertEqual(seeded?.path, target.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
        XCTAssertEqual(
            try String(contentsOf: target, encoding: .utf8),
            "(defun zephyr-ribbon () nil)")
    }

    func testSeedNeverOverwritesAnExistingUserDefinition() throws {
        makeFixture()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ribbon-seed-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let bundled = directory.appendingPathComponent("bundled.lsp")
        let target = directory.appendingPathComponent("user.lsp")
        try "(defun zephyr-ribbon () (bundled))".write(
            to: bundled, atomically: true, encoding: .utf8)
        try "(defun zephyr-ribbon () (edited-by-user))".write(
            to: target, atomically: true, encoding: .utf8)

        _ = RibbonSpecLoader.seed(from: bundled, to: target)

        XCTAssertEqual(
            try String(contentsOf: target, encoding: .utf8),
            "(defun zephyr-ribbon () (edited-by-user))",
            "the user's edited definition must never be clobbered")
    }

    func testSeedIsANoOpWithoutABundledDefinition() throws {
        makeFixture()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ribbon-seed-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let bundled = directory.appendingPathComponent("missing.lsp")
        let target = directory.appendingPathComponent("user.lsp")

        XCTAssertNil(RibbonSpecLoader.seed(from: bundled, to: target))
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
    }

    // MARK: - Auto reload

    func testAutoReloadFiresWhenFileModificationDateChanges() async throws {
        makeFixture()
        let file = try writeTempDefinition(Self.goodSource)
        defer { try? FileManager.default.removeItem(at: file) }
        loader.definitionURLProvider = { file }
        loader.autoReloadEnabled = true

        loader.requestReload(reason: "initial")
        await loader.waitForLoad()
        XCTAssertEqual(loader.status, .loaded)
        XCTAssertEqual(loader.spec.tabs.map(\.title), ["TestTab"])

        loader.baselineFileTimestamp()

        // Rewrite with a different tab name and a newer timestamp.
        try """
        (defun zephyr-ribbon ()
          (zr-ribbon nil
            (zr-tabs
              (list (zr-tab "Edited"
                (list (zr-panel "Draw"
                  (list (zr-big "LINE" "Line" "line" nil)))))))))
        (zephyr-ribbon)
        """.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(2)],
            ofItemAtPath: file.path)

        loader.autoReloadIfFileChanged(now: Date().addingTimeInterval(5))
        await loader.waitForLoad()

        XCTAssertEqual(loader.spec.tabs.map(\.title), ["Edited"])
    }

    func testAutoReloadDisabledIgnoresChanges() async throws {
        makeFixture()
        let file = try writeTempDefinition(Self.goodSource)
        defer { try? FileManager.default.removeItem(at: file) }
        loader.definitionURLProvider = { file }
        loader.autoReloadEnabled = false

        loader.requestReload(reason: "initial")
        await loader.waitForLoad()
        loader.baselineFileTimestamp()

        try "(defun zephyr-ribbon () nil)".write(
            to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(2)],
            ofItemAtPath: file.path)

        loader.autoReloadIfFileChanged(now: Date().addingTimeInterval(5))
        XCTAssertEqual(loader.spec.tabs.map(\.title), ["TestTab"])
    }

    // MARK: - Helpers

    private func writeTempDefinition(_ source: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ribbon-\(UUID().uuidString).lsp")
        try source.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
