import Foundation

// =========================================================================
// MARK: - Ribbon DSL prelude
// =========================================================================
//
// Prepended to every ribbon.lsp evaluation. It is the *contract* between the
// AutoLISP authoring surface and `RibbonSpecParser`, so it is embedded in
// Swift rather than shipped as an editable file.
//
// Design notes:
// * Everything a definition builds is a proper list whose first element is a
//   tag string — `("panel" "Draw" items…)`. The parser accepts tags as
//   strings or symbols and accepts a shorter list than the helper produces,
//   so raw `(list "big" "LINE" "Line")` is equally valid.
// * This AutoLISP implementation enforces exact arity
//   (`LispEvaluator.swift`: `args.count == fn.params.count`) and has no rest
//   arguments, so every helper takes a fixed parameter list. Containers take
//   a *list* of children, which keeps them arity-safe and composable with
//   `append`/`mapcar`.
// * Helpers are `zr-` prefixed and land in the persistent session, so a user
//   routine can never collide with them by accident.

public enum RibbonPrelude {
    /// Evaluated before the user file on every load.
    public static let source: String = #"""
;;; ---------------------------------------------------------------------
;;; Zephyr ribbon DSL — helper constructors.
;;; Arity is exact: always pass every parameter, using nil for "none".
;;; ---------------------------------------------------------------------

;; Top level: (zr-ribbon <menubar-or-nil> <tabs-or-nil>)
(defun zr-ribbon (menubar tabs) (list "ribbon" menubar tabs))

;; Containers -----------------------------------------------------------
(defun zr-menubar (menus)  (list "menubar" menus))
(defun zr-tabs    (tabs)   (list "tabs" tabs))
(defun zr-menu    (title items)  (list "menu" title items))
(defun zr-tab     (title panels) (list "tab" title panels))
(defun zr-panel   (title items)  (list "panel" title items))
(defun zr-sub     (title items)  (list "sub" title items))
(defun zr-drop    (label items)  (list "drop" label items))

;; Items ----------------------------------------------------------------
;; cmd   : command name as typed on the command line ("LINE", "MYROUTINE")
;; label : display text, may contain %SYSVAR% tokens
;; icon  : painter name, or nil to derive it from the command name
;; opts  : a list of option forms, or nil
(defun zr-big   (cmd label icon opts) (list "big"   cmd label icon opts))
(defun zr-small (cmd label icon opts) (list "small" cmd label icon opts))
(defun zr-item  (cmd label opts)      (list "item"  cmd label opts))
(defun zr-sep   ()                    (list "sep"))

;; Options --------------------------------------------------------------
(defun zr-enable (pred)  (list "enable" pred))
(defun zr-check  (pred)  (list "check" pred))
(defun zr-tip    (text)  (list "tip" text))

;; Predicates -----------------------------------------------------------
(defun zr-sel     (n)       (list "sel" n))
(defun zr-nocmd   ()        (list "nocmd"))
(defun zr-cmd     (name)    (list "cmd" name))
(defun zr-undoable ()       (list "undo"))
(defun zr-redoable ()       (list "redo"))
(defun zr-dirty   ()        (list "dirty"))
(defun zr-var     (name v)  (list "var" name v))
(defun zr-tabcount (n)      (list "tabcount" n))
"""#
}
