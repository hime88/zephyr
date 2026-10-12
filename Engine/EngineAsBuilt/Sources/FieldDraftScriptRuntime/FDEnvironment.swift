import FieldDraftScriptCore

// MARK: - Runtime Environment

public struct FDEnvironment {
    public var variables: [String: FDValue] = [:]
    public var functions: [String: FDFunctionDecl] = [:]
    public init() {}
}
