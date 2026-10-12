// MARK: - Block & Builder

struct LispBlock: LispNode {
    let nodes: [LispNode]

    var flattenedNodes: [LispNode] {
        nodes.flatMap { node in
            if let block = node as? LispBlock { return block.flattenedNodes }
            return [node]
        }
    }

    func render(environment: LispEnvironment) -> String {
        flattenedNodes.map { $0.render(environment: environment) }.joined(separator: "\n")
    }
}

@resultBuilder
struct AutoLISPBuilder {
    static func buildBlock(_ components: LispNode...) -> LispNode {
        LispBlock(nodes: components).flattened()
    }
}

extension LispBlock {
    func flattened() -> LispBlock {
        LispBlock(nodes: flattenedNodes)
    }
}

func renderBranch(_ node: LispNode, environment: LispEnvironment) -> String {
    if let block = node as? LispBlock {
        let flat = block.flattenedNodes
        if flat.count == 1, let only = flat.first {
            return only.render(environment: environment)
        }
        let rendered = flat.map { $0.render(environment: environment) }.joined(separator: "\n")
        return "(progn\n\(rendered.indent())\n)"
    }
    return node.render(environment: environment)
}

struct Progn: LispNode {
    let body: LispNode

    init(@AutoLISPBuilder _ body: () -> LispNode) {
        self.body = body()
    }

    func render(environment: LispEnvironment) -> String {
        "(progn\n\(body.render(environment: environment).indent())\n)"
    }
}

struct Setq: LispNode {
    let pairs: [(String, LispNode)]

    init(_ pairs: (String, any LispValue)...) {
        self.pairs = pairs.map { ($0.0, $0.1.toLispNode()) }
    }

    func render(environment: LispEnvironment) -> String {
        for pair in pairs { environment.localVariables.insert(pair.0) }
        guard let first = pairs.first else { return "(setq)" }
        if pairs.count == 1 {
            return "(setq \(first.0) \(first.1.render(environment: environment)))"
        }
        let rest = pairs.dropFirst().map {
            "      \($0.0) \($0.1.render(environment: environment))"
        }.joined(separator: "\n")
        return "(setq \(first.0) \(first.1.render(environment: environment))\n\(rest))"
    }
}
