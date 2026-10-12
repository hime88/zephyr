// MARK: - Math Functions

func abs(_ val: any LispValue) -> Call { Call("abs", val) }
func atan(_ val1: any LispValue, _ val2: (any LispValue)? = nil) -> Call { val2.map { Call("atan", val1, $0) } ?? Call("atan", val1) }
func cos(_ val: any LispValue) -> Call { Call("cos", val) }
func sin(_ val: any LispValue) -> Call { Call("sin", val) }
func exp(_ val: any LispValue) -> Call { Call("exp", val) }
func expt(_ base: any LispValue, _ power: any LispValue) -> Call { Call("expt", base, power) }
func fix(_ val: any LispValue) -> Call { Call("fix", val) }
func float(_ val: any LispValue) -> Call { Call("float", val) }
func gcd(_ val1: any LispValue, _ val2: any LispValue) -> Call { Call("gcd", val1, val2) }
func log(_ val: any LispValue) -> Call { Call("log", val) }
func max(_ args: any LispValue...) -> Call { Call(name: "max", args: args.map { $0.toLispNode() }) }
func min(_ args: any LispValue...) -> Call { Call(name: "min", args: args.map { $0.toLispNode() }) }
func rem(_ val1: any LispValue, _ val2: any LispValue) -> Call { Call("rem", val1, val2) }
func sqrt(_ val: any LispValue) -> Call { Call("sqrt", val) }
func onePlus(_ val: any LispValue) -> Call { Call("1+", val) }
func oneMinus(_ val: any LispValue) -> Call { Call("1-", val) }
func zerop(_ val: any LispValue) -> Call { Call("zerop", val) }
func minusp(_ val: any LispValue) -> Call { Call("minusp", val) }
func numberp(_ val: any LispValue) -> Call { Call("numberp", val) }
func boole(_ op: any LispValue, _ int1: any LispValue, _ int2: any LispValue, _ moreInts: any LispValue...) -> Call {
    Call(name: "boole", args: [op.toLispNode(), int1.toLispNode(), int2.toLispNode()] + moreInts.map { $0.toLispNode() })
}
func logand(_ args: any LispValue...) -> Call { Call(name: "logand", args: args.map { $0.toLispNode() }) }
func logior(_ args: any LispValue...) -> Call { Call(name: "logior", args: args.map { $0.toLispNode() }) }
func lsh(_ val: any LispValue, _ bits: any LispValue) -> Call { Call("lsh", val, bits) }
func bitNot(_ val: any LispValue) -> Call { Call("~", val) }
