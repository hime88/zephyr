// MARK: - User Input

func getint(_ prompt: (any LispValue)? = nil) -> Call { prompt.map { Call("getint", $0) } ?? Call("getint") }
func getreal(_ prompt: (any LispValue)? = nil) -> Call { prompt.map { Call("getreal", $0) } ?? Call("getreal") }
func getstring(_ flag: (any LispValue)? = nil, _ prompt: (any LispValue)? = nil) -> Call {
    var args: [any LispValue] = []
    if let f = flag { args.append(f); if let p = prompt { args.append(p) } }
    return Call(name: "getstring", args: args.map { $0.toLispNode() })
}
func getdist(_ pt: (any LispValue)? = nil, _ prompt: (any LispValue)? = nil) -> Call {
    var args: [any LispValue] = []
    if let p = pt { args.append(p); if let pr = prompt { args.append(pr) } }
    else if let pr = prompt { args.append(pr) }
    return Call(name: "getdist", args: args.map { $0.toLispNode() })
}
func getangle(_ pt: (any LispValue)? = nil, _ prompt: (any LispValue)? = nil) -> Call {
    var args: [any LispValue] = []
    if let p = pt { args.append(p); if let pr = prompt { args.append(pr) } }
    else if let pr = prompt { args.append(pr) }
    return Call(name: "getangle", args: args.map { $0.toLispNode() })
}
func getcorner(_ pt: any LispValue, _ prompt: (any LispValue)? = nil) -> Call { prompt.map { Call("getcorner", pt, $0) } ?? Call("getcorner", pt) }
func getkword(_ prompt: (any LispValue)? = nil) -> Call { prompt.map { Call("getkword", $0) } ?? Call("getkword") }
func getorient(_ pt: (any LispValue)? = nil, _ prompt: (any LispValue)? = nil) -> Call {
    var args: [any LispValue] = []
    if let p = pt { args.append(p); if let pr = prompt { args.append(pr) } }
    else if let pr = prompt { args.append(pr) }
    return Call(name: "getorient", args: args.map { $0.toLispNode() })
}
func initget(_ bits: (any LispValue)? = nil, _ keyword: (any LispValue)? = nil) -> Call {
    var args: [any LispValue] = []
    if let b = bits { args.append(b); if let k = keyword { args.append(k) } }
    return Call(name: "initget", args: args.map { $0.toLispNode() })
}
func getfiled(_ title: any LispValue, _ defaultPath: any LispValue, _ ext: any LispValue, _ flags: any LispValue) -> Call { Call("getfiled", title, defaultPath, ext, flags) }
func nentsel(_ prompt: (any LispValue)? = nil) -> Call { prompt.map { Call("nentsel", $0) } ?? Call("nentsel") }
func nentselp(_ prompt: (any LispValue)? = nil, _ pt: (any LispValue)? = nil) -> Call {
    var args: [any LispValue] = []
    if let pr = prompt { args.append(pr); if let p = pt { args.append(p) } }
    return Call(name: "nentselp", args: args.map { $0.toLispNode() })
}
func entsel(_ prompt: (any LispValue)? = nil) -> Call { prompt.map { Call("entsel", $0) } ?? Call("entsel") }
func getpoint(_ pt: (any LispValue)? = nil, _ prompt: (any LispValue)? = nil) -> Call {
    var args: [any LispValue] = []
    if let p = pt { args.append(p); if let pr = prompt { args.append(pr) } }
    else if let pr = prompt { args.append(pr) }
    return Call(name: "getpoint", args: args.map { $0.toLispNode() })
}
