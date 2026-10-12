// MARK: - Type Implementations

struct LispVar<T: LispType>: LispType {
    let name: String
    func render(environment: LispEnvironment) -> String { name }
}

extension LispVar: LispPointType where T: LispPointType {}
extension LispVar: LispNumberType where T: LispNumberType {}
extension LispVar: LispStringType where T: LispStringType {}

struct RawLispNode: LispPointType, LispNumberType, LispStringType {
    let raw: String
    init(_ raw: String) { self.raw = raw }
    init(raw: String) { self.raw = raw }
    func render(environment: LispEnvironment) -> String { raw }
}

struct LispListLiteral: LispNode {
    let items: [LispNode]
    let quoted: Bool

    init(items: [LispNode], quoted: Bool = false) {
        self.items = items
        self.quoted = quoted
    }

    func quotedLiteral() -> LispListLiteral {
        LispListLiteral(items: items, quoted: true)
    }

    func render(environment: LispEnvironment) -> String {
        if quoted {
            if items.isEmpty { return "'()" }
            let renderedItems = items.map { $0.render(environment: environment) }.joined(separator: " ")
            return "'(\(renderedItems))"
        }
        if items.isEmpty { return "'()" }
        let renderedItems = items.map { $0.render(environment: environment) }.joined(separator: " ")
        return "(list \(renderedItems))"
    }
}

struct LispPoint: LispPointType {
    let raw: String
    func render(environment: LispEnvironment) -> String { raw }
}

struct LispString: LispStringType {
    let value: String
    init(_ value: String) { self.value = value }
    func render(environment: LispEnvironment) -> String { "\"\(value)\"" }
}

struct InlineComment: LispNode {
    let node: LispNode
    let comment: String

    init(_ node: any LispValue, _ comment: String) {
        self.node = node.toLispNode()
        self.comment = comment
    }

    func render(environment: LispEnvironment) -> String {
        "\(node.render(environment: environment)) ; \(comment)"
    }
}

// MARK: - Optionals

protocol LispOptionalType: LispType {}

struct LispOptional<Wrapped: LispType>: LispOptionalType {
    let raw: String
    func render(environment: LispEnvironment) -> String { raw }
}
