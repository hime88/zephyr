// MARK: - Control Flow Nodes

struct LispIf: LispNode {
    let condition: LispNode
    let trueBranch: LispNode
    let falseBranch: LispNode?

    func render(environment: LispEnvironment) -> String {
        let cond = condition.render(environment: environment)
        let tBlock = renderBranch(trueBranch, environment: environment).indent()
        if let fBranch = falseBranch {
            let fBlock = renderBranch(fBranch, environment: environment).indent()
            return "(if \(cond)\n\(tBlock)\n\(fBlock)\n)"
        }
        return "(if \(cond)\n\(tBlock)\n)"
    }
}

struct IfLet<Wrapped: LispType>: LispNode {
    let variable: LispVar<Wrapped>
    let assignment: LispOptional<Wrapped>
    let trueBranch: LispNode
    let falseBranch: LispNode?

    init(_ name: String, _ assignment: LispOptional<Wrapped>, trueBranch: LispNode, falseBranch: LispNode? = nil) {
        self.variable = LispVar<Wrapped>(name: name)
        self.assignment = assignment
        self.trueBranch = trueBranch
        self.falseBranch = falseBranch
    }

    func render(environment: LispEnvironment) -> String {
        environment.localVariables.insert(variable.name)
        let cond = "(setq \(variable.name) \(assignment.render(environment: environment)))"
        let tBlock = renderBranch(trueBranch, environment: environment).indent()
        if let falseBranch {
            let fBlock = renderBranch(falseBranch, environment: environment).indent()
            return "(if \(cond)\n\(tBlock)\n\(fBlock)\n)"
        }
        return "(if \(cond)\n\(tBlock)\n)"
    }
}

struct LispWhile: LispNode {
    let condition: LispNode
    let body: LispNode

    init(_ condition: LispNode, @AutoLISPBuilder body: () -> LispNode) {
        self.condition = condition
        self.body = body()
    }

    func render(environment: LispEnvironment) -> String {
        let cond = condition.render(environment: environment)
        return "(while \(cond)\n\(body.render(environment: environment).indent())\n)"
    }
}

struct LispCond: LispNode {
    struct Case { let condition: LispNode; let body: LispNode }
    let cases: [Case]

    func render(environment: LispEnvironment) -> String {
        let renderedCases = cases.map { c in
            let condStr = c.condition.render(environment: environment)
            let bodyStr: String = {
                if let block = c.body as? LispBlock {
                    return block.flattenedNodes.map { $0.render(environment: environment) }.joined(separator: "\n")
                }
                return c.body.render(environment: environment)
            }()
            return "(\(condStr)\n\(bodyStr.indent()))"
        }.joined(separator: "\n")
        return "(cond\n\(renderedCases.indent())\n)"
    }
}

struct LispRepeat: LispNode {
    let count: LispNode; let body: LispNode
    func render(environment: LispEnvironment) -> String {
        "(repeat \(count.render(environment: environment))\n\(renderBranch(body, environment: environment).indent())\n)"
    }
}

struct LispForeach: LispNode {
    let variable: String; let list: LispNode; let body: LispNode
    func render(environment: LispEnvironment) -> String {
        environment.localVariables.insert(variable)
        let listStr = list.render(environment: environment)
        let bodyStr = renderBranch(body, environment: environment)
        return "(foreach \(variable) \(listStr)\n\(bodyStr.indent())\n)"
    }
}
