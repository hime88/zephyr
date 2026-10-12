// MARK: - List Functions

func list(_ args: any LispValue...) -> LispNode {
    LispListLiteral(items: args.map { $0.toLispNode() })
}
func cons(_ elem: any LispValue, _ listOrAtom: any LispValue) -> Call { Call("cons", elem, listOrAtom) }
func car(_ val: any LispValue) -> Call { Call("car", val) }
func cdr(_ val: any LispValue) -> Call { Call("cdr", val) }
func cadr(_ val: any LispValue) -> Call { Call("cadr", val) }
func caddr(_ val: any LispValue) -> Call { Call("caddr", val) }
func last(_ val: any LispValue) -> Call { Call("last", val) }
func length(_ val: any LispValue) -> Call { Call("length", val) }
func nth(_ n: any LispValue, _ listVal: any LispValue) -> Call { Call("nth", n, listVal) }
func append(_ args: any LispValue...) -> Call { Call(name: "append", args: args.map { $0.toLispNode() }) }
func reverse(_ val: any LispValue) -> Call { Call("reverse", val) }
func member(_ expr: any LispValue, _ listVal: any LispValue) -> Call { Call("member", expr, listVal) }
func assoc(_ key: any LispValue, _ alist: any LispValue) -> Call { Call("assoc", key, alist) }
func subst(_ newVal: any LispValue, _ old: any LispValue, _ listVal: any LispValue) -> Call { Call("subst", newVal, old, listVal) }
func vlRemove(_ elem: any LispValue, _ listVal: any LispValue) -> Call { Call("vl-remove", elem, listVal) }
func vlRemoveIf(_ pred: any LispValue, _ listVal: any LispValue) -> Call { Call("vl-remove-if", pred, listVal) }
func vlRemoveIfNot(_ pred: any LispValue, _ listVal: any LispValue) -> Call { Call("vl-remove-if-not", pred, listVal) }
func vlSort(_ listVal: any LispValue, _ compFn: any LispValue) -> Call { Call("vl-sort", listVal, compFn) }
func vlSortI(_ listVal: any LispValue, _ compFn: any LispValue) -> Call { Call("vl-sort-i", listVal, compFn) }
func vlPosition(_ elem: any LispValue, _ listVal: any LispValue) -> Call { Call("vl-position", elem, listVal) }
func vlMemberIf(_ pred: any LispValue, _ listVal: any LispValue) -> Call { Call("vl-member-if", pred, listVal) }
func vlMemberIfNot(_ pred: any LispValue, _ listVal: any LispValue) -> Call { Call("vl-member-if-not", pred, listVal) }
func vlEvery(_ pred: any LispValue, _ list1: any LispValue, _ moreLists: any LispValue...) -> Call { Call(name: "vl-every", args: [pred.toLispNode(), list1.toLispNode()] + moreLists.map { $0.toLispNode() }) }
func vlSome(_ pred: any LispValue, _ list1: any LispValue, _ moreLists: any LispValue...) -> Call { Call(name: "vl-some", args: [pred.toLispNode(), list1.toLispNode()] + moreLists.map { $0.toLispNode() }) }
func vlListLength(_ val: any LispValue) -> Call { Call("vl-list-length", val) }
func vlListStar(_ args: any LispValue...) -> Call { Call(name: "vl-list*", args: args.map { $0.toLispNode() }) }
func vlConsp(_ val: any LispValue) -> Call { Call("vl-consp", val) }
func acadStrlsort(_ val: any LispValue) -> Call { Call("acad_strlsort", val) }
