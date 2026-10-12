// MARK: - Command & Function Registration

struct Command: LispNode {
    let name: String; let body: LispNode
    init(_ name: String, @AutoLISPBuilder body: () -> LispNode) {
        self.name = name; self.body = body()
    }
    func render(environment: LispEnvironment) -> String {
        let env = LispEnvironment()
        let renderedBody = body.render(environment: env)
        let locals = env.localVariables.isEmpty ? "" : "/ " + env.localVariables.sorted().joined(separator: " ")
        let completeBody = "(vl-load-com)\n" + renderedBody + "\n(princ)"
        return ";;; Compiled FieldDraft Script\n(defun c:\(name) ( \(locals) )\n\(completeBody.indent())\n)"
    }
}

struct Function: LispNode {
    let name: String; let params: [String]; let body: LispNode
    init(_ name: String, params: [String] = [], @AutoLISPBuilder body: () -> LispNode) {
        self.name = name; self.params = params; self.body = body()
    }
    func render(environment: LispEnvironment) -> String {
        let env = LispEnvironment()
        for param in params { env.localVariables.insert(param) }
        let renderedBody = body.render(environment: env)
        let locals = env.localVariables.subtracting(Set(params)).sorted().joined(separator: " ")
        let localsPart = locals.isEmpty ? "" : " / \(locals)"
        return "(defun \(name) (\(params.joined(separator: " "))\(localsPart))\n\(renderedBody.indent()))"
    }
}

struct CommandAlias: LispNode {
    let alias: String; let target: String
    init(_ alias: String, _ target: String) { self.alias = alias; self.target = target }
    func render(environment: LispEnvironment) -> String { "(defun c:\(alias) () (c:\(target)))" }
}

struct Return: LispNode {
    let value: LispNode
    init(_ value: any LispValue) { self.value = value.toLispNode() }
    func render(environment: LispEnvironment) -> String { value.render(environment: environment) }
}

struct Comment: LispNode {
    let text: String
    init(_ text: String) { self.text = text }
    func render(environment: LispEnvironment) -> String { ";; \(text)" }
}

struct ErrorHandler: LispNode {
    let message: String
    init(_ message: String = "\\nCommand cancelled. Snap settings restored.") { self.message = message }
    func render(environment: LispEnvironment) -> String {
        environment.localVariables.insert("*error*")
        return "(defun *error* (msg)\n  (if oldOs (setvar \"OSMODE\" oldOs))\n  (if oldCmd (setvar \"CMDECHO\" oldCmd))\n  (princ \"\(message)\")\n  (princ)\n)"
    }
}

struct Call: LispType {
    let name: String; let args: [LispNode]
    init(name: String, args: [LispNode]) { self.name = name; self.args = args }
    init(_ name: String, _ args: any LispValue...) {
        self.name = name; self.args = args.map { $0.toLispNode() }
    }
    func render(environment: LispEnvironment) -> String {
        let renderedArgs = args.map { $0.render(environment: environment) }.joined(separator: " ")
        return args.isEmpty ? "(\(name))" : "(\(name) \(renderedArgs))"
    }
}

struct Prompt {
    static func point(_ message: String, basePoint: (any LispPointType)? = nil) -> LispOptional<LispPoint> {
        let bpStr = basePoint.map { $0.render(environment: LispEnvironment()) + " " } ?? ""
        return LispOptional(raw: "(getpoint \(bpStr)\"\\n\(message)\")")
    }
}

struct Math {
    static func distance(_ p1: any LispPointType, _ p2: any LispPointType) -> RawLispNode {
        RawLispNode("(distance \(p1.render(environment: LispEnvironment())) \(p2.render(environment: LispEnvironment())))")
    }
    static func angle(_ p1: any LispPointType, _ p2: any LispPointType) -> RawLispNode {
        RawLispNode("(angle \(p1.render(environment: LispEnvironment())) \(p2.render(environment: LispEnvironment())))")
    }
    static func polar(_ pt: any LispPointType, _ angle: any LispType, _ dist: any LispType) -> RawLispNode {
        RawLispNode("(polar \(pt.render(environment: LispEnvironment())) \(angle.render(environment: LispEnvironment())) \(dist.render(environment: LispEnvironment())))")
    }
    static func intersection(_ p1: any LispPointType, _ p2: any LispPointType, _ p3: any LispPointType, _ p4: any LispPointType, onSeg: (any LispValue)? = nil) -> RawLispNode {
        let env = LispEnvironment()
        let segArg = onSeg.map { " \($0.toLispNode().render(environment: env))" } ?? ""
        return RawLispNode("(inters \(p1.render(environment: env)) \(p2.render(environment: env)) \(p3.render(environment: env)) \(p4.render(environment: env))\(segArg))")
    }
}

struct Draw {
    static func line(_ p1: any LispPointType, _ p2: any LispPointType) -> Call {
        command("_.LINE", "_non", p1, "_non", p2, "")
    }
}

struct Entity {
    static func select(_ message: String) -> LispOptional<RawLispNode> {
        LispOptional(raw: "(car (entsel \"\\n\(message)\"))")
    }
    static func getLocation(_ entName: any LispType) -> RawLispNode {
        RawLispNode("(cdr (assoc 10 (entget \(entName.render(environment: LispEnvironment())))))")
    }
}
