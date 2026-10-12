// MARK: - Logic / Comparison

func and(_ args: any LispValue...) -> Call { Call(name: "and", args: args.map { $0.toLispNode() }) }
func or(_ args: any LispValue...) -> Call { Call(name: "or", args: args.map { $0.toLispNode() }) }
func not(_ val: any LispValue) -> Call { Call("not", val) }
func eq(_ expr1: any LispValue, _ expr2: any LispValue) -> Call { Call("eq", expr1, expr2) }
func equal(_ expr1: any LispValue, _ expr2: any LispValue, _ tolerance: (any LispValue)? = nil) -> Call { tolerance.map { Call("equal", expr1, expr2, $0) } ?? Call("equal", expr1, expr2) }
func atom(_ val: any LispValue) -> Call { Call("atom", val) }
func listp(_ val: any LispValue) -> Call { Call("listp", val) }
func null(_ val: any LispValue) -> Call { Call("null", val) }
func boundp(_ val: any LispValue) -> Call { Call("boundp", val) }
func type_(_ val: any LispValue) -> Call { Call("type", val) }
func eval(_ val: any LispValue) -> Call { Call("eval", val) }
func set(_ symbol: any LispValue, _ value: any LispValue) -> Call { Call("set", symbol, value) }

// MARK: - Entity Functions

func entlast() -> Call { Call("entlast") }
func entnext(_ ename: (any LispValue)? = nil) -> Call { ename.map { Call("entnext", $0) } ?? Call("entnext") }
func entdel(_ ename: any LispValue) -> Call { Call("entdel", ename) }
func entget(_ ename: any LispValue, _ appList: (any LispValue)? = nil) -> Call { appList.map { Call("entget", ename, $0) } ?? Call("entget", ename) }
func entmod(_ elist: any LispValue) -> Call { Call("entmod", elist) }
func entmake(_ elist: any LispValue) -> Call { Call("entmake", elist) }
func entmakex(_ elist: any LispValue) -> Call { Call("entmakex", elist) }
func entupd(_ ename: any LispValue) -> Call { Call("entupd", ename) }
func handent(_ handle: any LispValue) -> Call { Call("handent", handle) }
func redraw(_ ename: (any LispValue)? = nil, _ mode: (any LispValue)? = nil) -> Call {
    var args: [any LispValue] = []
    if let e = ename { args.append(e); if let m = mode { args.append(m) } }
    return Call(name: "redraw", args: args.map { $0.toLispNode() })
}
func regapp(_ name: any LispValue) -> Call { Call("regapp", name) }
func xdroom(_ ename: any LispValue) -> Call { Call("xdroom", ename) }
func xdsize(_ listVal: any LispValue) -> Call { Call("xdsize", listVal) }
func dumpallproperties(_ ename: any LispValue, _ ctx: (any LispValue)? = nil) -> Call { ctx.map { Call("dumpallproperties", ename, $0) } ?? Call("dumpallproperties", ename) }
func getPropertyValue(_ ename: any LispValue, _ prop: any LispValue, _ index: (any LispValue)? = nil) -> Call { index.map { Call("getpropertyvalue", ename, prop, $0) } ?? Call("getpropertyvalue", ename, prop) }
func setPropertyValue(_ ename: any LispValue, _ prop: any LispValue, _ value: any LispValue) -> Call { Call("setpropertyvalue", ename, prop, value) }
func isPropertyReadOnly(_ ename: any LispValue, _ prop: any LispValue) -> Call { Call("ispropertyreadonly", ename, prop) }
func textbox(_ elist: any LispValue) -> Call { Call("textbox", elist) }
