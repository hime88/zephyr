// MARK: - Parser Helpers

/// Edit distance between two strings (Levenshtein).
public func editDistance(_ a: String, _ b: String) -> Int {
    let a = Array(a), b = Array(b)
    var dp = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
    for i in 0...a.count { dp[i][0] = i }
    for j in 0...b.count { dp[0][j] = j }
    if !a.isEmpty && !b.isEmpty {
        for i in 1...a.count {
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                dp[i][j] = min(dp[i - 1][j] + 1, dp[i][j - 1] + 1, dp[i - 1][j - 1] + cost)
            }
        }
    }
    return dp[a.count][b.count]
}
