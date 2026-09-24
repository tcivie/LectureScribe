import Foundation

enum WordDiff {
    static func changedWords(raw: String, corrected: String) -> Set<Int> {
        let old = raw.split(whereSeparator: \.isWhitespace).map(normalized)
        let new = corrected.split(whereSeparator: \.isWhitespace).map(normalized)
        guard old != new else { return [] }
        let kept = commonIndices(old, new)
        return Set(new.indices.filter { !kept.contains($0) && !new[$0].isEmpty })
    }

    static func normalized<S: StringProtocol>(_ word: S) -> String {
        String(word.lowercased().unicodeScalars.filter(CharacterSet.alphanumerics.contains))
    }

    private static func commonIndices(_ old: [String], _ new: [String]) -> Set<Int> {
        let table = lcsTable(old, new)
        var (i, j, kept) = (0, 0, Set<Int>())
        while i < old.count, j < new.count {
            if old[i] == new[j] {
                kept.insert(j)
                (i, j) = (i + 1, j + 1)
            } else if table[i + 1][j] >= table[i][j + 1] {
                i += 1
            } else {
                j += 1
            }
        }
        return kept
    }

    private static func lcsTable(_ old: [String], _ new: [String]) -> [[Int]] {
        var table = Array(repeating: Array(repeating: 0, count: new.count + 1), count: old.count + 1)
        for i in old.indices.reversed() {
            for j in new.indices.reversed() {
                table[i][j] = old[i] == new[j] ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
            }
        }
        return table
    }
}
