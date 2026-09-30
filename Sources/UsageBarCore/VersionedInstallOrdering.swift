import Foundation

/// Orders the version-named directories an installer keeps side by side, such
/// as the copies of Claude Code the Claude desktop app downloads into
/// `~/Library/Application Support/Claude/claude-code/<version>/`.
///
/// Only names made entirely of dot-separated decimal components are accepted,
/// so a stray folder, a partial download (`2.1.0.tmp`) or a hidden entry is
/// never mistaken for an installation. The result is newest first, compared
/// numerically so `2.1.10` sorts above `2.1.9`.
public enum VersionedInstallOrdering {
    public static func newestFirst(_ names: [String]) -> [String] {
        names
            .compactMap { name in components(of: name).map { (name, $0) } }
            .sorted { isNewer($0.1, than: $1.1) }
            .map(\.0)
    }

    static func components(of name: String) -> [Int]? {
        let parts = name.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty else { return nil }
        var values: [Int] = []
        for part in parts {
            guard
                !part.isEmpty,
                part.count <= 9,
                part.allSatisfy({ $0.isASCII && $0.isNumber }),
                let value = Int(part)
            else { return nil }
            values.append(value)
        }
        return values
    }

    private static func isNewer(_ lhs: [Int], than rhs: [Int]) -> Bool {
        for index in 0..<max(lhs.count, rhs.count) {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left != right { return left > right }
        }
        return false
    }
}
