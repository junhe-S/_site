import Foundation

struct BlogPost {
    let slug: String
    let path: URL

    var title: String {
        guard let content = try? String(contentsOf: path, encoding: .utf8) else {
            return slug
        }
        if content.hasPrefix("---") {
            let parts = content.components(separatedBy: "---")
            if parts.count >= 3 {
                let yaml = parts[1]
                for line in yaml.components(separatedBy: "\n") {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("title:") {
                        var t = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                        if (t.hasPrefix("\"") && t.hasSuffix("\"")) || (t.hasPrefix("'") && t.hasSuffix("'")) {
                            t = String(t.dropFirst().dropLast())
                        }
                        return t
                    }
                }
            }
        }
        return slug.replacingOccurrences(of: "-", with: " ").capitalized
    }

    var date: Date? {
        guard let content = try? String(contentsOf: path, encoding: .utf8),
              content.hasPrefix("---") else { return nil }
        let parts = content.components(separatedBy: "---")
        guard parts.count >= 3 else { return nil }
        for line in parts[1].components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("date:") {
                let dateStr = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                return formatter.date(from: dateStr)
            }
        }
        return nil
    }

    /// First line of body text (after frontmatter) for note list preview
    var preview: String {
        guard let content = try? String(contentsOf: path, encoding: .utf8) else { return "" }
        var body = content
        if content.hasPrefix("---") {
            let parts = content.components(separatedBy: "---")
            if parts.count >= 3 {
                body = parts[2...].joined(separator: "---")
            }
        }
        // Get first non-empty, non-heading line
        for line in body.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            if trimmed.hasPrefix("#") { continue }
            if trimmed.hasPrefix(">") { continue }
            if trimmed.hasPrefix("```") { continue }
            if trimmed.hasPrefix("---") { continue }
            // Strip markdown formatting
            var clean = trimmed
            clean = clean.replacingOccurrences(of: "\\*\\*(.+?)\\*\\*", with: "$1", options: .regularExpression)
            clean = clean.replacingOccurrences(of: "\\*(.+?)\\*", with: "$1", options: .regularExpression)
            clean = clean.replacingOccurrences(of: "`([^`]+)`", with: "$1", options: .regularExpression)
            clean = clean.replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^\\)]+\\)", with: "$1", options: .regularExpression)
            return String(clean.prefix(80))
        }
        return ""
    }
}
