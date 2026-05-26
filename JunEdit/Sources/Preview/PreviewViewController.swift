import Cocoa
import WebKit

class PreviewViewController: NSViewController {
    private let webView = WKWebView()
    private var shellLoaded = false
    private var currentPostDir: URL?

    override func loadView() {
        view = webView
    }

    // MARK: - Load built HTML file (after Build)

    func loadHTMLFile(_ url: URL) {
        resetShell()
        guard let blogRoot = BlogSettings.shared.blogDirectory else {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
            return
        }

        guard var html = try? String(contentsOf: url, encoding: .utf8) else { return }

        let postDir = url.deletingLastPathComponent()
        let relativePath = relativePathToRoot(from: postDir, to: blogRoot)

        html = html.replacingOccurrences(of: "href=\"/", with: "href=\"\(relativePath)")
        html = html.replacingOccurrences(of: "src=\"/", with: "src=\"\(relativePath)")

        let previewOverrides = """
        <script>
        (function() {
            if (window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches) {
                document.documentElement.setAttribute('data-theme', 'dark');
            } else {
                document.documentElement.setAttribute('data-theme', 'light');
            }
        })();
        </script>
        <style>
        /* Make links visible in preview */
        a { color: #3e69d7 !important; text-decoration-color: #3e69d7 !important; }
        a:hover { color: #f59102 !important; }
        [data-theme="light"] a { color: #2f479f !important; text-decoration-color: #2f479f !important; }
        </style>
        """
        html = html.replacingOccurrences(of: "<head>", with: "<head>\(previewOverrides)")

        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let tempFile = postDir.appendingPathComponent(".preview_temp_\(timestamp).html")
        // Clean up old temp files
        let fm = FileManager.default
        if let files = try? fm.contentsOfDirectory(at: postDir, includingPropertiesForKeys: nil) {
            for f in files where f.lastPathComponent.hasPrefix(".preview_temp_") && f != tempFile {
                try? fm.removeItem(at: f)
            }
        }
        try? html.write(to: tempFile, atomically: true, encoding: .utf8)

        webView.loadFileURL(tempFile, allowingReadAccessTo: blogRoot)
    }

    // MARK: - Live markdown preview

    func loadMarkdownContent(_ markdown: String, postDir: URL?) {
        let articleHTML = buildArticleBody(markdown)

        // If shell is already loaded for the same post directory, just swap the content via JS
        if shellLoaded && currentPostDir == postDir {
            let escaped = articleHTML
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "`", with: "\\`")
                .replacingOccurrences(of: "${", with: "\\${")
            let js = "document.getElementById('article').innerHTML = `\(escaped)`;"
            webView.evaluateJavaScript(js, completionHandler: nil)
            return
        }

        // First load or post directory changed — load full shell page
        currentPostDir = postDir
        let html = buildShellHTML(articleHTML)

        if let postDir = postDir, let blogRoot = BlogSettings.shared.blogDirectory {
            let tempFile = postDir.appendingPathComponent(".live_preview.html")
            try? html.write(to: tempFile, atomically: true, encoding: .utf8)
            webView.loadFileURL(tempFile, allowingReadAccessTo: blogRoot)
        } else {
            webView.loadHTMLString(html, baseURL: nil)
        }
        shellLoaded = true
    }

    /// Reset shell state when switching posts or loading built HTML
    private func resetShell() {
        shellLoaded = false
        currentPostDir = nil
    }

    // MARK: - Markdown → HTML

    /// Parse frontmatter and convert markdown body to article HTML (no shell wrapper)
    private func buildArticleBody(_ raw: String) -> String {
        var body = raw
        var title = ""
        var date = ""
        var tags: [String] = []

        // Parse frontmatter
        if raw.hasPrefix("---") {
            let parts = raw.components(separatedBy: "---")
            if parts.count >= 3 {
                let yaml = parts[1]
                body = parts[2...].joined(separator: "---").trimmingCharacters(in: .whitespacesAndNewlines)
                for line in yaml.components(separatedBy: "\n") {
                    let t = line.trimmingCharacters(in: .whitespaces)
                    if t.hasPrefix("title:") {
                        title = String(t.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                        if title.hasPrefix("\"") && title.hasSuffix("\"") { title = String(title.dropFirst().dropLast()) }
                    } else if t.hasPrefix("date:") {
                        date = String(t.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                    } else if t.hasPrefix("tags:") {
                        let tagStr = String(t.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                        if tagStr.hasPrefix("[") {
                            tags = tagStr.dropFirst().dropLast()
                                .components(separatedBy: ",")
                                .map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
                                .filter { !$0.isEmpty }
                        }
                    }
                }
            }
        }

        let tagsHTML = tags.isEmpty ? "" : "<div class=\"tags\">" + tags.map { "<span class=\"tag\">\(esc($0))</span>" }.joined(separator: " ") + "</div>"

        return """
        \(title.isEmpty ? "" : "<h1>\(esc(title))</h1>")
        \(date.isEmpty ? "" : "<div class=\"meta\">\(esc(date))</div>")
        \(tagsHTML)
        \(convertMD(body))
        """
    }

    /// Wrap article body in a full HTML shell (used for first load only)
    private func buildShellHTML(_ articleBody: String) -> String {
        """
        <!DOCTYPE html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>\(previewCSS())</style>
        <script>\(darkModeJS())</script>
        </head><body><article id="article">
        \(articleBody)
        </article></body></html>
        """
    }

    private func convertMD(_ md: String) -> String {
        var html = ""
        var inCode = false
        var codeBuf = ""
        var codeLang = ""
        var inList = false
        var listItems: [String] = []
        var inQuote = false
        var quoteLines: [String] = []

        for line in md.components(separatedBy: "\n") {
            // Code blocks
            if line.hasPrefix("```") {
                if inCode {
                    html += "<pre><code class=\"language-\(esc(codeLang))\">\(esc(codeBuf))</code></pre>\n"
                    codeBuf = ""; inCode = false
                } else {
                    if inList { html += flushList(&listItems); inList = false }
                    if inQuote { html += flushQuote(&quoteLines); inQuote = false }
                    inCode = true
                    codeLang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    if let r = codeLang.range(of: #"\s*\{(show|hide)\}"#, options: .regularExpression) {
                        codeLang = String(codeLang[..<r.lowerBound])
                    }
                }
                continue
            }
            if inCode { codeBuf += line + "\n"; continue }

            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Blockquotes / callouts — collect consecutive > lines
            if trimmed.hasPrefix(">") {
                if inList { html += flushList(&listItems); inList = false }
                inQuote = true
                quoteLines.append(trimmed)
                continue
            } else if inQuote {
                html += flushQuote(&quoteLines)
                inQuote = false
            }

            // Lists
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                inList = true
                listItems.append(String(trimmed.dropFirst(2)))
                continue
            } else if inList {
                html += flushList(&listItems)
                inList = false
            }

            // Headings
            if trimmed.hasPrefix("######") {
                html += "<h6>\(inlineMD(String(trimmed.dropFirst(7))))</h6>\n"
            } else if trimmed.hasPrefix("#####") {
                html += "<h5>\(inlineMD(String(trimmed.dropFirst(6))))</h5>\n"
            } else if trimmed.hasPrefix("####") {
                html += "<h4>\(inlineMD(String(trimmed.dropFirst(5))))</h4>\n"
            } else if trimmed.hasPrefix("###") {
                html += "<h3>\(inlineMD(String(trimmed.dropFirst(4))))</h3>\n"
            } else if trimmed.hasPrefix("##") {
                html += "<h2>\(inlineMD(String(trimmed.dropFirst(3))))</h2>\n"
            } else if trimmed.hasPrefix("#") {
                html += "<h1>\(inlineMD(String(trimmed.dropFirst(2))))</h1>\n"
            }
            // Images
            else if trimmed.hasPrefix("![") {
                if let ae = trimmed.range(of: "]("), let ue = trimmed.range(of: ")", range: ae.upperBound..<trimmed.endIndex) {
                    let alt = String(trimmed[trimmed.index(trimmed.startIndex, offsetBy: 2)..<ae.lowerBound])
                    let url = String(trimmed[ae.upperBound..<ue.lowerBound])
                    html += "<div class=\"img\"><img src=\"\(url)\" alt=\"\(esc(alt))\"></div>\n"
                }
            }
            // Horizontal rule
            else if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                html += "<hr>\n"
            }
            // Empty line
            else if trimmed.isEmpty {
                html += "\n"
            }
            // Paragraph
            else {
                html += "<p>\(inlineMD(trimmed))</p>\n"
            }
        }

        if inList { html += flushList(&listItems) }
        if inQuote { html += flushQuote(&quoteLines) }
        if inCode { html += "<pre><code>\(esc(codeBuf))</code></pre>\n" }

        return html
    }

    private func flushList(_ items: inout [String]) -> String {
        let html = "<ul>\n" + items.map { "<li>\(inlineMD($0))</li>" }.joined(separator: "\n") + "\n</ul>\n"
        items.removeAll()
        return html
    }

    private func flushQuote(_ lines: inout [String]) -> String {
        guard !lines.isEmpty else { return "" }

        // Strip leading > from each line
        var stripped: [String] = []
        for line in lines {
            var s = line
            if s.hasPrefix(">") { s = String(s.dropFirst()) }
            s = s.trimmingCharacters(in: .init(charactersIn: " "))
            stripped.append(s)
        }

        // Check if first line is a callout: [!type]
        let first = stripped[0]
        if first.hasPrefix("[!"),
           let end = first.range(of: "]") {
            let calloutType = String(first[first.index(first.startIndex, offsetBy: 2)..<end.lowerBound]).lowercased()
            let titleText = String(first[end.upperBound...]).trimmingCharacters(in: .whitespaces)

            let cssClass: String
            switch calloutType {
            case "warning": cssClass = "callout callout-warning"
            case "tip": cssClass = "callout callout-tip"
            case "important": cssClass = "callout callout-important"
            case "caution": cssClass = "callout callout-caution"
            default: cssClass = "callout"
            }

            let label = calloutType.prefix(1).uppercased() + calloutType.dropFirst()
            var bodyParts: [String] = []
            if !titleText.isEmpty { bodyParts.append(titleText) }
            bodyParts.append(contentsOf: stripped.dropFirst())

            let bodyHTML = bodyParts.map { inlineMD($0) }.joined(separator: "<br>")
            lines.removeAll()
            return "<div class=\"\(cssClass)\"><strong>\(esc(label))</strong>\(bodyHTML)</div>\n"
        }

        // Plain blockquote
        let bodyHTML = stripped.map { inlineMD($0) }.joined(separator: "<br>")
        lines.removeAll()
        return "<blockquote>\(bodyHTML)</blockquote>\n"
    }

    private func inlineMD(_ t: String) -> String {
        var r = esc(t)
        // Bold
        r = r.replacingOccurrences(of: #"\*\*(.+?)\*\*"#, with: "<strong>$1</strong>", options: .regularExpression)
        // Italic
        r = r.replacingOccurrences(of: #"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)"#, with: "<em>$1</em>", options: .regularExpression)
        // Strikethrough
        r = r.replacingOccurrences(of: #"~~(.+?)~~"#, with: "<del>$1</del>", options: .regularExpression)
        // Inline code
        r = r.replacingOccurrences(of: #"`([^`]+)`"#, with: "<code>$1</code>", options: .regularExpression)
        // Links
        r = r.replacingOccurrences(of: #"\[([^\]]+)\]\(([^\)]+)\)"#, with: "<a href=\"$2\">$1</a>", options: .regularExpression)
        return r
    }

    private func esc(_ t: String) -> String {
        t.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
    }

    // MARK: - CSS

    private func previewCSS() -> String {
        """
        :root { color-scheme: light dark; }
        /* Mdmdt Dark (default) */
        body {
            font-family: "PingFang SC", -apple-system, "Helvetica Neue", Arial, sans-serif;
            max-width: 720px; margin: 0 auto; padding: 24px 28px;
            line-height: 1.6; font-size: 16px;
            color: #d0d0d0; background: #1b1b1f;
        }
        /* Mdmdt Light */
        @media (prefers-color-scheme: light) {
            body { color: #000; background: #fafafc; }
            code { background: rgba(62,105,215,0.15); color: #2f479f; }
            pre { background: #ececee; border-color: #d2d2d2; }
            pre code { color: #2f479f; }
            blockquote { background: rgba(62,105,215,0.06); border-color: #3e69d7; color: #666; }
            .callout { background: rgba(62,105,215,0.06); border-color: #3e69d7; }
            .callout-warning { background: rgba(245,145,2,0.06); border-color: #f59102; }
            .callout-tip { background: rgba(3,183,54,0.06); border-color: #03b736; }
            .callout-important { background: rgba(130,80,223,0.06); border-color: #8250df; }
            .tag { background: rgba(62,105,215,0.15); color: #3e69d7; }
            hr { border-color: #d2d2d2; }
            table th { background: #ececee; }
            table td, table th { border-color: #d2d2d2; }
        }
        h1 { font-size: 32px; margin-top: 0; margin-bottom: 8px; letter-spacing: 2px; line-height: 1.5; }
        h2 { font-size: 28px; margin-top: 28px; letter-spacing: 2px; line-height: 1.5; }
        h3 { font-size: 24px; margin-top: 20px; letter-spacing: 2px; line-height: 1.5; }
        h4 { font-size: 20px; margin-top: 16px; }
        p { margin: 0.8em 0; }
        .meta { color: #666; font-size: 14px; margin-bottom: 0.5rem; }
        .tags { margin-bottom: 1.5rem; }
        .tag {
            display: inline-block; font-size: 12px; padding: 2px 10px;
            border-radius: 4px; background: rgba(62,105,215,0.15); color: #bbc7fd;
            margin-right: 6px;
        }
        code {
            font-family: "JetBrains Mono", "Source Code Pro", "Fira Code", Consolas, monospace;
            font-size: 0.85em; background: rgba(62,105,215,0.15); color: #bbc7fd;
            padding: 3px 5px; border-radius: 4px;
        }
        pre {
            background: rgb(40,42,50); padding: 16px; border-radius: 8px;
            overflow-x: auto; border: 1px solid #3a3a3e;
        }
        pre code { background: none; padding: 0; font-size: 14px; line-height: 1.6; color: #bbc7fd; }
        a { color: #3e69d7; text-decoration: none; font-weight: 500; }
        a:hover { color: #f59102; text-decoration: underline; }
        blockquote {
            border-left: 4px solid #3e69d7; margin-left: 0; padding: 12px 16px;
            background: rgba(62,105,215,0.06); border-radius: 8px;
            color: #999; font-style: italic;
        }
        .img { margin: 1.5rem 0; }
        .img img { max-width: 100%; border-radius: 8px; }
        hr { border: none; border-top: 1px solid #3a3a3e; margin: 2rem 0; }
        ul { padding-left: 1.5em; }
        li { margin: 0.4em 0; }
        .callout {
            border-left: 4px solid #3e69d7; background: rgba(62,105,215,0.06);
            padding: 12px 16px; border-radius: 8px; margin: 1rem 0;
        }
        .callout-warning { border-color: #f59102; background: rgba(245,145,2,0.06); }
        .callout-tip { border-color: #03b736; background: rgba(3,183,54,0.06); }
        .callout-important { border-color: #8250df; background: rgba(130,80,223,0.06); }
        .callout-caution { border-color: #e30f2e; background: rgba(227,15,46,0.06); }
        .callout strong { display: block; margin-bottom: 4px; }
        table { border-collapse: collapse; width: 100%; margin: 1rem 0; font-size: 14px; }
        th, td { border: 1px solid #3a3a3e; padding: 8px 12px; text-align: left; }
        th { font-weight: 600; background: rgb(40,42,50); }
        del { color: #666; }
        """
    }

    private func darkModeJS() -> String {
        """
        (function() {
            if (window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches) {
                document.documentElement.setAttribute('data-theme', 'dark');
            } else {
                document.documentElement.setAttribute('data-theme', 'light');
            }
        })();
        """
    }

    // MARK: - Helpers

    private func relativePathToRoot(from postDir: URL, to blogRoot: URL) -> String {
        let postComponents = postDir.standardizedFileURL.pathComponents
        let rootComponents = blogRoot.standardizedFileURL.pathComponents
        let extra = postComponents.count - rootComponents.count
        if extra <= 0 { return "" }
        return String(repeating: "../", count: extra)
    }
}
