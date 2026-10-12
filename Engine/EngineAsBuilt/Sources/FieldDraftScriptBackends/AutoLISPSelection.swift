// MARK: - Selection Set

func ssget(_ mode: (any LispValue)? = nil, _ pt1: (any LispValue)? = nil, _ pt2: (any LispValue)? = nil, _ filter: (any LispValue)? = nil) -> Call {
    var args: [any LispValue] = []
    if let m = mode { args.append(m) }
    if let p1 = pt1 { args.append(p1); if let p2 = pt2 { args.append(p2) } }
    if let f = filter { args.append(f) }
    return Call(name: "ssget", args: args.map { $0.toLispNode() })
}
func ssadd(_ ename: (any LispValue)? = nil, _ ss: (any LispValue)? = nil) -> Call {
    var args: [any LispValue] = []
    if let e = ename { args.append(e); if let s = ss { args.append(s) } }
    return Call(name: "ssadd", args: args.map { $0.toLispNode() })
}
func ssdel(_ ename: any LispValue, _ ss: any LispValue) -> Call { Call("ssdel", ename, ss) }
func sslength(_ ss: any LispValue) -> Call { Call("sslength", ss) }
func ssname(_ ss: any LispValue, _ index: any LispValue) -> Call { Call("ssname", ss, index) }
func ssnamex(_ ss: any LispValue, _ index: any LispValue) -> Call { Call("ssnamex", ss, index) }
func ssmemb(_ ename: any LispValue, _ ss: any LispValue) -> Call { Call("ssmemb", ename, ss) }
func ssgetfirst() -> Call { Call("ssgetfirst") }
func sssetfirst(_ gripped: any LispValue, _ selected: (any LispValue)? = nil) -> Call { selected.map { Call("sssetfirst", gripped, $0) } ?? Call("sssetfirst", gripped) }
