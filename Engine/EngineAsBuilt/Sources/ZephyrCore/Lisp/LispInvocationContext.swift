import Foundation

// =========================================================================
// MARK: - Command Invocation Context (Lisp reentrancy policy)
// =========================================================================
//
// While an AutoLISP routine runs (a `LispCommand` feature command is
// active), no other interactive command may start: the CAD command surface
// is stateful (activeCommand, selection, feature-command singletons), and
// nesting a second command inside a suspended Lisp evaluation would corrupt
// both. The enforced policy:
//
// * `(command ...)` from Lisp NEVER routes through `executeCommand`. It is
//   served by the scripted dispatcher (`LispScriptedCommands`), which
//   implements an audited subset of commands directly against the document.
//   Anything outside that subset fails closed with a clean error naming the
//   offending command.
// * While `lispInvocationDepth > 0`, `executeCommand` rejects everything
//   except text routed to the running Lisp driver itself (which arrives via
//   `submitTextToActiveFeatureCommand`, not `executeCommand`). This single
//   gate covers the whole switch, the feature-command registry, the legacy
//   `startCommand` path, keyboard shortcuts, DDEDIT, and spacebar repeat,
//   because every one of those entries funnels through `executeCommand`.
// * The Lisp driver itself refuses to start nested (depth limit 1).
//
// Call-site audit (all `executeCommand` callers reach the gate):
// * CommandLineUI submit (canonical name / raw text)
// * EngineInputHandler hotkeys (COPYCLIP/COPYBASE/PASTECLIP/PASTEBLOCK/
//   PDFIMPORT/CLOSEALL, direct-distance buffer)
// * EngineLoopController double-click DDEDIT
// * Spacebar repeat-last-command (CADCommandProcessor:1464)
// * handleDrawingViewCommand (downstream of the gate, inside executeCommand)

/// Who initiated the current command execution.
public enum CommandInvocationContext: Sendable {
    /// Normal interactive use: keyboard, command line, menus.
    case user
    /// Execution on behalf of a running AutoLISP routine.
    case lisp
}

/// What a command name means when invoked from Lisp `(command ...)`.
public enum LispCommandDisposition: Sendable {
    /// The scripted dispatcher implements this command directly against
    /// the document, selection, and variable store. No interactive state
    /// is touched and no input is ever requested.
    case scripted
    /// The command is interactive-only (or not yet audited) and is
    /// rejected from Lisp with an error naming the command.
    case interactiveReject
}

extension CADCommandProcessor {

    /// Number of Lisp routines currently on the invocation stack.
    /// 0 when idle; 1 while a `LispCommand` driver runs. The driver refuses
    /// to start when this is already > 0 (depth limit 1).
    public internal(set) var lispInvocationDepth: Int {
        get { _lispInvocationDepth }
        set { _lispInvocationDepth = max(0, newValue) }
    }

    /// The reject-nested-interactive gate. Call at the top of
    /// `executeCommand`, before `lastExecutedCommand` is assigned.
    ///
    /// - Returns: `true` when the caller must return immediately (a Lisp
    ///   routine is running and the requested command was rejected).
    @discardableResult
    func rejectCommandIfLispActive(_ text: String) -> Bool {
        guard lispInvocationDepth > 0 else { return false }
        let name = text.uppercased().trimmingCharacters(in: .whitespaces)
        print("[Lisp] Command '\(name)' rejected: an AutoLISP routine is already running.")
        print("[Lisp] (Nested interactive commands are not allowed; Esc cancels the routine.)")
        return true
    }
}
