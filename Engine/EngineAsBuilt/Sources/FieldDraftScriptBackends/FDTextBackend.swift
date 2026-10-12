import FieldDraftScriptCore

// MARK: - Text Backend Protocol

public protocol FDTextBackend {
    func emit(_ program: FDProgram) throws -> String
}
