// MARK: - String Functions

func strcat(_ args: any LispValue...) -> Call { Call(name: "strcat", args: args.map { $0.toLispNode() }) }
func strlen(_ val: any LispValue) -> Call { Call("strlen", val) }
func substr(_ str: any LispValue, _ start: any LispValue, _ length: (any LispValue)? = nil) -> Call { length.map { Call("substr", str, start, $0) } ?? Call("substr", str, start) }
func strcase(_ str: any LispValue, _ lower: (any LispValue)? = nil) -> Call { lower.map { Call("strcase", str, $0) } ?? Call("strcase", str) }
func ascii(_ val: any LispValue) -> Call { Call("ascii", val) }
func chr(_ val: any LispValue) -> Call { Call("chr", val) }
func itoa(_ val: any LispValue) -> Call { Call("itoa", val) }
func atof(_ val: any LispValue) -> Call { Call("atof", val) }
func atoi(_ val: any LispValue) -> Call { Call("atoi", val) }
func rtos(_ num: any LispValue, _ mode: (any LispValue)? = nil, _ prec: (any LispValue)? = nil) -> Call {
    var args: [any LispValue] = [num]
    if let m = mode { args.append(m); if let p = prec { args.append(p) } }
    return Call(name: "rtos", args: args.map { $0.toLispNode() })
}
func angtof(_ str: any LispValue, _ mode: (any LispValue)? = nil) -> Call { mode.map { Call("angtof", str, $0) } ?? Call("angtof", str) }
func angtos(_ angle: any LispValue, _ mode: (any LispValue)? = nil, _ prec: (any LispValue)? = nil) -> Call {
    var args: [any LispValue] = [angle]
    if let m = mode { args.append(m); if let p = prec { args.append(p) } }
    return Call(name: "angtos", args: args.map { $0.toLispNode() })
}
func distof(_ str: any LispValue, _ mode: (any LispValue)? = nil) -> Call { mode.map { Call("distof", str, $0) } ?? Call("distof", str) }
func read(_ val: any LispValue) -> Call { Call("read", val) }
func wcmatch(_ str: any LispValue, _ pattern: any LispValue) -> Call { Call("wcmatch", str, pattern) }
func snvalid(_ val: any LispValue) -> Call { Call("snvalid", val) }
func vlStringToList(_ val: any LispValue) -> Call { Call("vl-string->list", val) }
func vlListToString(_ val: any LispValue) -> Call { Call("vl-list->string", val) }
func vlStringElt(_ str: any LispValue, _ idx: any LispValue) -> Call { Call("vl-string-elt", str, idx) }
func vlStringLeftTrim(_ chars: any LispValue, _ str: any LispValue) -> Call { Call("vl-string-left-trim", chars, str) }
func vlStringRightTrim(_ chars: any LispValue, _ str: any LispValue) -> Call { Call("vl-string-right-trim", chars, str) }
func vlStringTrim(_ chars: any LispValue, _ str: any LispValue) -> Call { Call("vl-string-trim", chars, str) }
func vlStringMismatch(_ str1: any LispValue, _ str2: any LispValue) -> Call { Call("vl-string-mismatch", str1, str2) }
func vlStringPosition(_ char: any LispValue, _ str: any LispValue) -> Call { Call("vl-string-position", char, str) }
func vlStringSearch(_ pattern: any LispValue, _ str: any LispValue, _ start: (any LispValue)? = nil) -> Call { start.map { Call("vl-string-search", pattern, str, $0) } ?? Call("vl-string-search", pattern, str) }
func vlStringSubst(_ new: any LispValue, _ old: any LispValue, _ str: any LispValue, _ start: (any LispValue)? = nil) -> Call { start.map { Call("vl-string-subst", new, old, str, $0) } ?? Call("vl-string-subst", new, old, str) }
func vlStringTranslate(_ src: any LispValue, _ target: any LispValue, _ str: any LispValue) -> Call { Call("vl-string-translate", src, target, str) }
func vlPrin1ToString(_ val: any LispValue) -> Call { Call("vl-prin1-to-string", val) }
func vlPrincToString(_ val: any LispValue) -> Call { Call("vl-princ-to-string", val) }
func vlSymbolName(_ val: any LispValue) -> Call { Call("vl-symbol-name", val) }
func vlSymbolValue(_ val: any LispValue) -> Call { Call("vl-symbol-value", val) }
func vlSymbolp(_ val: any LispValue) -> Call { Call("vl-symbolp", val) }
