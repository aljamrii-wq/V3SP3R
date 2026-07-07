import Foundation

/// Computes a compact line-level unified diff for MEDIUM file writes.
struct DiffService {

    struct DiffLine: Identifiable, Equatable {
        enum Kind: Equatable { case context, added, removed }
        let id = UUID()
        let kind: Kind
        let text: String

        var marker: String {
            switch kind { case .context: return " "; case .added: return "+"; case .removed: return "-" }
        }
    }

    /// Structured diff for rendering in the approval sheet.
    func diffLines(old: String, new: String) -> [DiffLine] {
        let oldLines = old.components(separatedBy: "\n")
        let newLines = new.components(separatedBy: "\n")
        let lcs = longestCommonSubsequence(oldLines, newLines)

        var result: [DiffLine] = []
        var i = 0, j = 0
        for common in lcs {
            while i < oldLines.count && oldLines[i] != common {
                result.append(DiffLine(kind: .removed, text: oldLines[i])); i += 1
            }
            while j < newLines.count && newLines[j] != common {
                result.append(DiffLine(kind: .added, text: newLines[j])); j += 1
            }
            result.append(DiffLine(kind: .context, text: common))
            i += 1; j += 1
        }
        while i < oldLines.count { result.append(DiffLine(kind: .removed, text: oldLines[i])); i += 1 }
        while j < newLines.count { result.append(DiffLine(kind: .added, text: newLines[j])); j += 1 }
        return result
    }

    /// Plain-text unified diff (used for audit metadata and tests).
    func unifiedDiff(old: String, new: String) -> String {
        diffLines(old: old, new: new)
            .filter { $0.kind != .context }
            .map { "\($0.marker) \($0.text)" }
            .joined(separator: "\n")
    }

    private func longestCommonSubsequence(_ a: [String], _ b: [String]) -> [String] {
        let n = a.count, m = b.count
        if n == 0 || m == 0 { return [] }
        var table = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                table[i][j] = a[i] == b[j] ? table[i + 1][j + 1] + 1
                                           : max(table[i + 1][j], table[i][j + 1])
            }
        }
        var result: [String] = []
        var i = 0, j = 0
        while i < n && j < m {
            if a[i] == b[j] {
                result.append(a[i]); i += 1; j += 1
            } else if table[i + 1][j] >= table[i][j + 1] {
                i += 1
            } else {
                j += 1
            }
        }
        return result
    }
}
