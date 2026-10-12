// MARK: - Function/Lambda/Mapcar/Apply/Quote

struct LispLambda: LispNode {
    let args: [String]; let body: LispNode
    func render(environment: LispEnvironment) -> String {
        let argsStr = args.joined(separator: " ")
        let bodyStr: String = {
            if let block = body as? LispBlock {
                return block.flattenedNodes.map { $0.render(environment: environment) }.joined(separator: "\n")
            }
            return body.render(environment: environment)
        }()
        return "(lambda (\(argsStr))\n\(bodyStr.indent())\n)"
    }
}

struct LispMapcar: LispNode {
    let function: LispNode; let lists: [LispNode]
    func render(environment: LispEnvironment) -> String {
        let fnStr = function is LispLambda
            ? "\n\(function.render(environment: environment).indent())"
            : function.render(environment: environment)
        let listStr = lists.map { $0.render(environment: environment) }.joined(separator: " ")
        return "(mapcar \(fnStr) \(listStr))"
    }
}

struct LispApply: LispNode {
    let function: LispNode; let argList: LispNode
    func render(environment: LispEnvironment) -> String {
        "(apply \(function.render(environment: environment)) \(argList.render(environment: environment)))"
    }
}

struct LispQuote: LispNode {
    let expr: LispNode; let shorthand: Bool
    init(_ expr: any LispValue, shorthand: Bool = true) {
        self.expr = expr.toLispNode(); self.shorthand = shorthand
    }
    func render(environment: LispEnvironment) -> String {
        shorthand ? "'\(expr.render(environment: environment))" : "(quote \(expr.render(environment: environment)))"
    }
}
