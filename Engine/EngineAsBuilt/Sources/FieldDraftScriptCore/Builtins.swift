// MARK: - Built-in Registry

/// Backend availability for a built-in symbol.
public enum FDBackend: String, CaseIterable {
    case autolisp
    case runtime
}

/// Single source of truth for all known FDScript statements and functions.
/// Shared by the parser, LSP, and all backends.
public struct FDBuiltinRegistry {

    /// All known statement names (keywords that start a line in a command body).
    /// These are matched case-sensitively in `parseStatement()`.
    public static let statements: Set<String> = [
        "setup", "restore", "comment", "doorPoints", "textSelect", "setq",
        "normalizeSignedAngle", "normalizeAngle", "drawDoorPanel", "drawDoorArc",
        "princ", "acadCommand", "if", "while", "macro", "yield", "ifLet", "setvar",
        "cond", "repeat", "foreach", "return", "selection", "raw", "rawTop", "function", "alias"
    ]

    /// All known function names (called with parens in expressions).
    public static let functions: Set<String> = [
        "vlaxEnameToVlaObject", "vlaxSafearrayToList", "vlaGetBoundingBox",
        "dictSet", "dictHas", "dictGet", "set",
        "symName", "symRead", "symGet", "symSet", "symBound", "symClear",
        "abs", "atan", "cos", "sin", "exp", "expt", "fix", "float", "gcd", "log",
        "max", "min", "rem", "sqrt", "onePlus", "oneMinus", "zerop", "minusp", "numberp",
        "boole", "logand", "logior", "lsh", "bitNot",
        "strcat", "strlen", "substr", "strcase", "ascii", "chr", "itoa", "atof", "atoi",
        "rtos", "angtof", "angtos", "distof", "wcmatch", "snvalid",
        "list", "cons", "car", "cdr", "cadr", "caddr", "last", "length", "nth",
        "appendList", "reverse", "member", "assoc", "subst",
        "and", "or", "not", "eq", "equal", "atom", "listp", "null", "boundp", "type_", "eval",
        "entlast", "entnext", "entdel", "entget", "entmod", "entmake", "entmakex", "entupd",
        "handent", "redraw", "regapp",
        "ssget", "ssadd", "ssdel", "sslength", "ssname", "ssmemb", "ssgetfirst", "sssetfirst",
        "tblnext", "tblsearch", "tblobjname", "namedobjdict",
        "dictadd", "dictnext", "dictremove", "dictrename", "dictsearch",
        "fileOpen", "fileClose", "readLine", "readChar", "writeLine", "writeChar",
        "findfile", "load",
        "getint", "getreal", "getstring", "getdist", "getangle", "getcorner", "getkword",
        "getorient", "initget", "getfiled", "nentsel", "entsel", "getpoint",
        "getenv", "setenv", "ver", "exit_", "quit_", "gc", "mem",
        "prompt", "prin1", "print_", "terpri", "alert",
        "vlSort", "vlRemove", "vlPosition", "vlEvery", "vlSome",
        "vlStringToList", "vlListToString", "vlStringSearch", "vlStringSubst",
        "vlCatchAllApply", "vlRegistryRead", "vlRegistryWrite",
        "trans", "cvunit", "osnap", "inters", "textbox",
        "commandS", "initcommandversion", "initdia", "help",
        "lambda", "mapcar", "apply", "quote"
    ]

    /// All known names (statements + functions + macros from source).
    public static func allKnown(macros: Set<String> = []) -> Set<String> {
        statements.union(functions).union(macros)
    }

    /// Returns the set of backends that support a given statement or function.
    /// Currently everything is AutoLISP-only. Runtime support is added in Phase 4.
    public static func backends(for name: String) -> Set<FDBackend> {
        if name == "rawTop" { return [.autolisp] }
        return [.autolisp]
    }

    /// Statements that require a specific backend and should emit diagnostics otherwise.
    public static func restrictedStatements() -> [String: Set<FDBackend>] {
        ["rawTop": [.autolisp]]
    }
}
