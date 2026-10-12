// MARK: - System / Environment

func getenv(_ name: any LispValue) -> Call { Call("getenv", name) }
func setenv(_ name: any LispValue, _ value: any LispValue) -> Call { Call("setenv", name, value) }
func ver() -> Call { Call("ver") }
func exit_() -> Call { Call("exit") }
func quit_() -> Call { Call("quit") }
func gc() -> Call { Call("gc") }
func mem() -> Call { Call("mem") }
func alloc(_ size: any LispValue) -> Call { Call("alloc", size) }
func expand(_ segments: any LispValue) -> Call { Call("expand", segments) }
func getcfg(_ section: any LispValue) -> Call { Call("getcfg", section) }
func setcfg(_ section: any LispValue, _ value: any LispValue) -> Call { Call("setcfg", section, value) }
func getcname(_ cmd: any LispValue) -> Call { Call("getcname", cmd) }
func vlRegistryRead(_ key: any LispValue, _ value: (any LispValue)? = nil) -> Call { value.map { Call("vl-registry-read", key, $0) } ?? Call("vl-registry-read", key) }
func vlRegistryWrite(_ key: any LispValue, _ value: (any LispValue)? = nil, _ data: (any LispValue)? = nil) -> Call {
    var args: [any LispValue] = [key]
    if let v = value { args.append(v); if let d = data { args.append(d) } }
    return Call(name: "vl-registry-write", args: args.map { $0.toLispNode() })
}
func vlRegistryDelete(_ key: any LispValue, _ value: (any LispValue)? = nil) -> Call { value.map { Call("vl-registry-delete", key, $0) } ?? Call("vl-registry-delete", key) }
func vlRegistryDescendents(_ key: any LispValue) -> Call { Call("vl-registry-descendents", key) }
func trace(_ functions: any LispValue...) -> Call { Call(name: "trace", args: functions.map { $0.toLispNode() }) }
func untrace(_ functions: any LispValue...) -> Call { Call(name: "untrace", args: functions.map { $0.toLispNode() }) }
func arx() -> Call { Call("arx") }
func arxload(_ app: any LispValue, _ onFailure: (any LispValue)? = nil) -> Call { onFailure.map { Call("arxload", app, $0) } ?? Call("arxload", app) }
func arxunload(_ app: any LispValue, _ onFailure: (any LispValue)? = nil) -> Call { onFailure.map { Call("arxunload", app, $0) } ?? Call("arxunload", app) }
func autoarxload(_ app: any LispValue, _ cmdlist: any LispValue) -> Call { Call("autoarxload", app, cmdlist) }
func autoload(_ filename: any LispValue, _ commands: any LispValue) -> Call { Call("autoload", filename, commands) }
func vlLoadAll(_ filename: any LispValue) -> Call { Call("vl-load-all", filename) }
func vlVbaload(_ filename: any LispValue) -> Call { Call("vl-vbaload", filename) }
func vlVbarun(_ macro: any LispValue) -> Call { Call("vl-vbarun", macro) }
func vlVlxLoadedP(_ name: any LispValue) -> Call { Call("vl-vlx-loaded-p", name) }
func vlUnloadVlx(_ name: any LispValue) -> Call { Call("vl-unload-vlx", name) }
func vlListLoadedVlx() -> Call { Call("vl-list-loaded-vlx") }
func startapp(_ app: any LispValue, _ file: (any LispValue)? = nil) -> Call { file.map { Call("startapp", app, $0) } ?? Call("startapp", app) }
func atomsFamily(_ format: any LispValue, _ exclude: (any LispValue)? = nil) -> Call { exclude.map { Call("atoms-family", format, $0) } ?? Call("atoms-family", format) }
func layoutlist() -> Call { Call("layoutlist") }

// MARK: - VL Functions

func vlCatchAllApply(_ function: any LispValue, _ listVal: any LispValue) -> Call { Call("vl-catch-all-apply", function, listVal) }
func vlaxEnameToVlaObject(_ ent: any LispValue) -> Call { Call("vlax-ename->vla-object", ent) }
func vlaxSafearrayToList(_ arr: any LispValue) -> Call { Call("vlax-safearray->list", arr) }
func vlaGetBoundingBox(_ obj: any LispValue, _ minPt: any LispValue, _ maxPt: any LispValue) -> Call { Call("vla-getboundingbox", obj, minPt, maxPt) }
func vlCatchAllErrorMessage(_ err: any LispValue) -> Call { Call("vl-catch-all-error-message", err) }
func vlCatchAllErrorP(_ arg: any LispValue) -> Call { Call("vl-catch-all-error-p", arg) }
func vlAcadDefun(_ symbol: any LispValue) -> Call { Call("vl-acad-defun", symbol) }
func vlAcadUndefun(_ symbol: any LispValue) -> Call { Call("vl-acad-undefun", symbol) }
func vlArxImport(_ function: (any LispValue)? = nil) -> Call { function.map { Call("vl-arx-import", $0) } ?? Call("vl-arx-import") }
func vlBbRef(_ symbol: any LispValue) -> Call { Call("vl-bb-ref", symbol) }
func vlBbSet(_ symbol: any LispValue, _ value: any LispValue) -> Call { Call("vl-bb-set", symbol, value) }
func vlCmdf(_ args: any LispValue...) -> Call { Call(name: "vl-cmdf", args: args.map { $0.toLispNode() }) }
func vlDocExport(_ symbol: any LispValue) -> Call { Call("vl-doc-export", symbol) }
func vlDocImport(_ symbol: any LispValue) -> Call { Call("vl-doc-import", symbol) }
func vlDocRef(_ symbol: any LispValue) -> Call { Call("vl-doc-ref", symbol) }
func vlDocSet(_ symbol: any LispValue, _ value: any LispValue) -> Call { Call("vl-doc-set", symbol, value) }
func vlExitWithError(_ str: any LispValue) -> Call { Call("vl-exit-with-error", str) }
func vlExitWithValue(_ value: any LispValue) -> Call { Call("vl-exit-with-value", value) }
func vlPropagate(_ symbol: any LispValue) -> Call { Call("vl-propagate", symbol) }

// MARK: - Layer State

func layerstateSave(_ name: any LispValue, _ mask: (any LispValue)? = nil, _ vpId: (any LispValue)? = nil) -> Call {
    var args: [any LispValue] = [name]
    if let m = mask { args.append(m); if let v = vpId { args.append(v) } }
    return Call(name: "layerstate-save", args: args.map { $0.toLispNode() })
}
func layerstateRestore(_ name: any LispValue, _ vpId: (any LispValue)? = nil, _ flags: (any LispValue)? = nil) -> Call {
    var args: [any LispValue] = [name]
    if let v = vpId { args.append(v); if let f = flags { args.append(f) } }
    return Call(name: "layerstate-restore", args: args.map { $0.toLispNode() })
}
func layerstateDelete(_ name: any LispValue) -> Call { Call("layerstate-delete", name) }
func layerstateGetnames() -> Call { Call("layerstate-getnames") }
func layerstateGetlayers(_ name: any LispValue) -> Call { Call("layerstate-getlayers", name) }
func layerstateGetlastrestored() -> Call { Call("layerstate-getlastrestored") }
func layerstateHas(_ name: any LispValue) -> Call { Call("layerstate-has", name) }
func layerstateRename(_ old: any LispValue, _ new: any LispValue) -> Call { Call("layerstate-rename", old, new) }
func layerstateAddlayers(_ name: any LispValue, _ list: any LispValue) -> Call { Call("layerstate-addlayers", name, list) }
func layerstateRemovelayers(_ name: any LispValue, _ list: any LispValue) -> Call { Call("layerstate-removelayers", name, list) }
func layerstateExport(_ name: any LispValue, _ file: any LispValue) -> Call { Call("layerstate-export", name, file) }
func layerstateImport(_ file: any LispValue) -> Call { Call("layerstate-import", file) }
func layerstateImportfromdb(_ name: any LispValue, _ database: any LispValue) -> Call { Call("layerstate-importfromdb", name, database) }
func layerstateCompare(_ name: any LispValue, _ drawing: any LispValue) -> Call { Call("layerstate-compare", name, drawing) }
