// MARK: - Runtime Values

public enum FDValue: Equatable {
    case nilValue
    case bool(Bool)
    case number(Double)
    case string(String)
    case point(x: Double, y: Double, z: Double)
    case list([FDValue])
    case entity(String)
}
