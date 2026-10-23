import Foundation
import ZephyrLisp

// =========================================================================
// MARK: - Ribbon model (pure data)
// =========================================================================
//
// The ribbon is a *declarative layout document*: an AutoLISP file defines a
// tree of tabs -> panels -> items, plus a classic menu bar tree. This file
// is the serialized shape of that document after evaluation and validation.
//
// Nothing here touches ImGui or the engine, so the grammar, the ordering
// rules and the live-state predicates are unit-testable without a window
// (see RibbonSpecParserTests / RibbonUIPolicyTests). The renderer in the
// app target (`Sources/Zephyr/RibbonUI.swift`) only reads this model.
//
// Item identity is the *command name*: a click is dispatched through
// `CADCommandProcessor.executeCommand(_:)`, exactly like a panel button, so
// the ribbon never duplicates command logic.

/// One evaluated + validated ribbon definition.
public struct RibbonSpec: Sendable, Equatable {
    /// Classic menu bar entries (`File`, `Edit`, …) shown in `.menu` mode.
    /// Empty is legal: the renderer then derives menus from `tabs`.
    public var menus: [RibbonMenu]
    /// Ribbon tabs (`Home`, `Insert`, …) shown in `.labels` / `.full` mode.
    public var tabs: [RibbonTab]

    public init(menus: [RibbonMenu] = [], tabs: [RibbonTab] = []) {
        self.menus = menus
        self.tabs = tabs
    }

    public var isEmpty: Bool {
        menus.isEmpty && tabs.isEmpty
    }

    /// The tab to activate for a requested id, falling back to the first tab.
    /// Keeps a persisted selection valid when the definition changes.
    public func resolvedTabID(requested: String?) -> String? {
        if let requested, tabs.contains(where: { $0.id == requested }) {
            return requested
        }
        return tabs.first?.id
    }

    public func tab(id: String?) -> RibbonTab? {
        guard let id else { return nil }
        return tabs.first { $0.id == id }
    }
}

/// One top-level menu of the classic menu bar.
public struct RibbonMenu: Sendable, Equatable, Identifiable {
    public var title: String
    public var items: [RibbonItem]

    /// The title doubles as the identity (titles are unique in a menubar).
    public var id: String { title }

    public init(title: String, items: [RibbonItem]) {
        self.title = title
        self.items = items
    }
}

/// One ribbon tab.
public struct RibbonTab: Sendable, Equatable, Identifiable {
    public var title: String
    public var panels: [RibbonPanel]

    /// Stable id used for persistence and the active-tab lookup.
    public var id: String { title }

    public init(title: String, panels: [RibbonPanel]) {
        self.title = title
        self.panels = panels
    }
}

/// One ribbon panel (a column group under the tab strip, with a title bar
/// at the bottom — AutoCAD's layout).
public struct RibbonPanel: Sendable, Equatable {
    public var title: String
    public var items: [RibbonItem]

    public init(title: String, items: [RibbonItem]) {
        self.title = title
        self.items = items
    }
}

/// One entry inside a panel or a menu. Menus reuse the same vocabulary:
/// `.command` is a menu entry, `.separator` a divider, `.dropdown` a submenu.
public enum RibbonItem: Sendable, Equatable {
    case command(RibbonCommand)
    case separator
    case dropdown(RibbonDropdown)
}

/// A dropdown/flyout (`zr-drop` in a panel) or submenu (`zr-sub` in a menu).
public struct RibbonDropdown: Sendable, Equatable {
    public var label: String
    /// Painter name; nil derives from the label lowercased.
    public var icon: String?
    public var items: [RibbonItem]
    public var tooltip: String?

    public init(
        label: String,
        icon: String? = nil,
        items: [RibbonItem],
        tooltip: String? = nil
    ) {
        self.label = label
        self.icon = icon
        self.items = items
        self.tooltip = tooltip
    }
}

/// A clickable command entry.
public struct RibbonCommand: Sendable, Equatable {
    /// Button size inside a ribbon panel. Menus render `.large` and `.small`
    /// identically, so this only matters for panels.
    public enum Size: String, Sendable, Equatable {
        case large
        case small
    }

    /// Canonical command name as typed on the command line ("LINE", "C:FOO"
    /// routines go in by their bare name, "FOO").
    public var command: String
    /// Display label. Supports `%SYSVAR%` interpolation (see `RibbonText`).
    public var label: String
    /// Icon painter name; nil means "derive from `command`".
    public var icon: String?
    public var size: Size
    public var tooltip: String?
    /// All must hold for the entry to be enabled (empty = always enabled).
    public var enabled: [RibbonPredicate]
    /// All must hold for the entry to render pressed/toggled (e.g. GRID).
    public var checked: [RibbonPredicate]

    public init(
        command: String,
        label: String? = nil,
        icon: String? = nil,
        size: Size = .small,
        tooltip: String? = nil,
        enabled: [RibbonPredicate] = [],
        checked: [RibbonPredicate] = []
    ) {
        self.command = command
        self.label = label ?? command
        self.icon = icon
        self.size = size
        self.tooltip = tooltip
        self.enabled = enabled
        self.checked = checked
    }

    /// Icon name to hand to the painter: explicit, else the command name
    /// lowercased (`LINE` -> `line`). The painter falls back to a letter box
    /// when the name is unknown, so this is always safe.
    public var resolvedIconName: String {
        if let icon, !icon.isEmpty { return icon.lowercased() }
        return command.lowercased()
    }
}

/// Declarative live-state predicate. Evaluated per frame by
/// `RibbonUIPolicy` against a `RibbonStateContext` — deliberately *not* a
/// LISP callback: evaluation runs on a detached task, so per-frame LISP is
/// neither safe nor affordable.
public enum RibbonPredicate: Sendable, Equatable {
    /// At least n entities selected.
    case selectionAtLeast(Int)
    /// No interactive command or feature command is running.
    case noActiveCommand
    /// This command (canonical name, uppercased) is active.
    case activeCommand(String)
    case undoAvailable
    case redoAvailable
    /// The active document has unsaved changes.
    case documentDirty
    /// Sysvar equals a value (int/real compare numerically, strings
    /// case-insensitively).
    case variableEquals(name: String, value: LispValue)
    /// At least n document tabs are open.
    case tabCountAtLeast(Int)
}
