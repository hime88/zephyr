// MARK: - Graphics

func grdraw(_ pt1: any LispValue, _ pt2: any LispValue, _ color: any LispValue, _ highlight: (any LispValue)? = nil) -> Call { highlight.map { Call("grdraw", pt1, pt2, color, $0) } ?? Call("grdraw", pt1, pt2, color) }
func grvecs(_ vlist: any LispValue, _ trans: (any LispValue)? = nil) -> Call { trans.map { Call("grvecs", vlist, $0) } ?? Call("grvecs", vlist) }
func grread(_ track: (any LispValue)? = nil, _ allkeys: (any LispValue)? = nil, _ curtype: (any LispValue)? = nil) -> Call {
    var args: [any LispValue] = []
    if let t = track { args.append(t); if let a = allkeys { args.append(a); if let c = curtype { args.append(c) } } }
    return Call(name: "grread", args: args.map { $0.toLispNode() })
}
func grtext(_ box: (any LispValue)? = nil, _ text: (any LispValue)? = nil, _ highlight: (any LispValue)? = nil) -> Call {
    var args: [any LispValue] = []
    if let b = box { args.append(b); if let t = text { args.append(t); if let h = highlight { args.append(h) } } }
    return Call(name: "grtext", args: args.map { $0.toLispNode() })
}
func grclear() -> Call { Call("grclear") }
func graphscr() -> Call { Call("graphscr") }
func textscr() -> Call { Call("textscr") }
func textpage() -> Call { Call("textpage") }
func menucmd(_ str: any LispValue) -> Call { Call("menucmd", str) }
func menugroup(_ group: any LispValue) -> Call { Call("menugroup", group) }
func tablet(_ code: any LispValue, _ row1: (any LispValue)? = nil, _ row2: (any LispValue)? = nil, _ row3: (any LispValue)? = nil, _ direction: (any LispValue)? = nil) -> Call {
    var args: [any LispValue] = [code]
    if let r1 = row1 { args.append(r1); if let r2 = row2 { args.append(r2); if let r3 = row3 { args.append(r3); if let d = direction { args.append(d) } } } }
    return Call(name: "tablet", args: args.map { $0.toLispNode() })
}
func setview(_ name: any LispValue, _ vpId: (any LispValue)? = nil) -> Call { vpId.map { Call("setview", name, $0) } ?? Call("setview", name) }
