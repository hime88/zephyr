// MARK: - Neutral FDScript AST

public struct FDProgram: Sendable {
    public var declarations: [FDDecl]
    public init(declarations: [FDDecl]) { self.declarations = declarations }
}

public enum FDDecl: Sendable {
    case command(FDCommandDecl)
    case function(FDFunctionDecl)
    case alias(FDAliasDecl)
    case rawTop(String)
}

public struct FDCommandDecl: Sendable {
    public let name: String
    public let body: [FDStmt]
}

public struct FDFunctionDecl: Sendable {
    public let name: String
    public let params: [String]
    public let body: [FDStmt]
}

public struct FDAliasDecl: Sendable {
    public let alias: String
    public let target: String
}

public enum FDStmt: Sendable {
    case comment(String)
    case setup
    case restore
    case setq([(String, FDExpr)])
    case setvar(String, FDExpr)
    case expr(FDExpr)
    case ifStmt(condition: FDExpr, then: [FDStmt], elseBody: [FDStmt]?)
    case ifLet(name: String, assignment: FDInputExpr, then: [FDStmt], elseBody: [FDStmt]?)
    case whileStmt(condition: FDExpr, body: [FDStmt])
    case cond([(FDExpr, [FDStmt])])
    case `repeat`(FDExpr, [FDStmt])
    case foreach(name: String, list: FDExpr, body: [FDStmt])
    case returnStmt(FDExpr)
    case raw(String)
}

public enum FDInputExpr: Sendable {
    case point(prompt: String, base: String?)
    case select(prompt: String)
}

public indirect enum FDExpr: Sendable {
    case `nil`
    case bool(Bool)
    case number(Double)
    case string(String)
    case symbol(String)
    case list([FDExpr])
    case call(String, [FDExpr])
    case unary(String, FDExpr)
    case binary(String, FDExpr, FDExpr)
}
