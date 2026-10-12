// MARK: - Global API Helpers

func v(_ name: String) -> RawLispNode { RawLispNode(name) }
func pointVar(_ name: String) -> LispVar<LispPoint> { LispVar<LispPoint>(name: name) }
func rawVar(_ name: String) -> LispVar<RawLispNode> { LispVar<RawLispNode>(name: name) }
func numVar(_ name: String) -> LispVar<RawLispNode> { LispVar<RawLispNode>(name: name) }
func strVar(_ name: String) -> LispVar<LispString> { LispVar<LispString>(name: name) }
func getvar(_ name: String) -> Call { Call(name: "getvar", args: [name.toLispNode()]) }
func setvar(_ name: String, _ value: any LispValue) -> Call { Call(name: "setvar", args: [name.toLispNode(), value.toLispNode()]) }
func princ(_ message: String) -> Call { Call(name: "princ", args: [message.toLispNode()]) }
func princ(_ value: any LispValue) -> Call { Call(name: "princ", args: [value.toLispNode()]) }
func command(_ args: any LispValue...) -> Call { Call(name: "command", args: args.map { $0.toLispNode() }) }
func raw(_ text: String) -> RawLispNode { RawLispNode(text) }

// MARK: - Control flow helpers

func whileLoop(_ condition: any LispValue, @AutoLISPBuilder body: () -> LispNode) -> LispWhile {
    LispWhile(condition.toLispNode(), body: body)
}
func ifDo(_ condition: any LispValue, @AutoLISPBuilder _ trueBranch: () -> LispNode) -> LispIf {
    LispIf(condition: condition.toLispNode(), trueBranch: trueBranch(), falseBranch: nil)
}
func ifElse(_ condition: any LispValue, @AutoLISPBuilder _ trueBranch: () -> LispNode, @AutoLISPBuilder `else` falseBranch: () -> LispNode) -> LispIf {
    LispIf(condition: condition.toLispNode(), trueBranch: trueBranch(), falseBranch: falseBranch())
}
func ifLet<Wrapped: LispType>(_ name: String, _ assignment: LispOptional<Wrapped>, @AutoLISPBuilder _ trueBranch: () -> LispNode, @AutoLISPBuilder `else` falseBranch: () -> LispNode) -> IfLet<Wrapped> {
    IfLet(name, assignment, trueBranch: trueBranch(), falseBranch: falseBranch())
}
func ifLet<Wrapped: LispType>(_ name: String, _ assignment: LispOptional<Wrapped>, @AutoLISPBuilder _ trueBranch: () -> LispNode) -> IfLet<Wrapped> {
    IfLet(name, assignment, trueBranch: trueBranch(), falseBranch: nil)
}
func repeatLoop(_ count: any LispValue, @AutoLISPBuilder body: () -> LispNode) -> LispRepeat {
    LispRepeat(count: count.toLispNode(), body: body())
}
func foreachLoop(_ variable: String, in list: any LispValue, @AutoLISPBuilder body: () -> LispNode) -> LispForeach {
    LispForeach(variable: variable, list: list.toLispNode(), body: body())
}
func lambda(_ args: String..., @AutoLISPBuilder body: () -> LispNode) -> LispLambda {
    LispLambda(args: args, body: body())
}
func mapcar(_ function: any LispValue, _ lists: any LispValue...) -> LispMapcar {
    LispMapcar(function: function.toLispNode(), lists: lists.map { $0.toLispNode() })
}
func apply(_ function: any LispValue, _ argList: any LispValue) -> LispApply {
    LispApply(function: function.toLispNode(), argList: argList.toLispNode())
}
func quote(_ expr: any LispValue) -> LispNode {
    if let list = expr.toLispNode() as? LispListLiteral { return list.quotedLiteral() }
    return LispQuote(expr, shorthand: true)
}

// MARK: - Common Patterns

func commandSetup() -> LispNode {
    LispBlock(nodes: [
        Comment("1. Store current environmental variables"),
        Setq(("oldOs", getvar("OSMODE")), ("oldCmd", getvar("CMDECHO"))),
        setvar("CMDECHO", 0),
        Comment("2. Define Custom Error Handler (Catches \"Esc\" and failures)"),
        ErrorHandler()
    ])
}

func commandRestore() -> LispNode {
    LispBlock(nodes: [
        Comment("4. Standard Restore (If command finishes successfully)"),
        setvar("OSMODE", rawVar("oldOs")),
        setvar("CMDECHO", rawVar("oldCmd"))
    ])
}

func normalizeAngle(_ angle: any LispNumberType) -> LispNode {
    let pi = numVar("pi")
    return LispBlock(nodes: [
        whileLoop(angle >= (pi * 2.0)) {
            Setq((angle.render(environment: LispEnvironment()), angle - (pi * 2.0)))
        },
        whileLoop(angle < 0.0) {
            Setq((angle.render(environment: LispEnvironment()), angle + (pi * 2.0)))
        }
    ])
}

func normalizeSignedAngle(_ angle: any LispNumberType) -> LispNode {
    let pi = numVar("pi")
    return LispBlock(nodes: [
        whileLoop(angle > pi) {
            Setq((angle.render(environment: LispEnvironment()), angle - (pi * 2.0)))
        },
        whileLoop(angle < -pi) {
            Setq((angle.render(environment: LispEnvironment()), angle + (pi * 2.0)))
        }
    ])
}
