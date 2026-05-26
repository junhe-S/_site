import Cocoa
import WebKit

class PreviewViewController: NSViewController {
    private let webView = WKWebView()

    override func loadView() {
        view = webView
    }

    func loadHTMLFile(_ url: URL) {
        guard let blogRoot = BlogSettings.shared.blogDirectory else {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
            return
        }

        // Rewrite absolute paths to relative paths from the post directory
        guard var html = try? String(contentsOf: url, encoding: .utf8) else { return }

        // Calculate relative path from post dir to blog root
        // e.g. posts/my-post/index.html -> ../../
        let postDir = url.deletingLastPathComponent()
        let relativePath = relativePathToRoot(from: postDir, to: blogRoot)

        html = html.replacingOccurrences(of: "href=\"/", with: "href=\"\(relativePath)")
        html = html.replacingOccurrences(of: "src=\"/", with: "src=\"\(relativePath)")

        // Inject script to auto-detect system dark mode
        let darkModeScript = """
        <script>
        (function() {
            if (window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches) {
                document.documentElement.setAttribute('data-theme', 'dark');
            } else {
                document.documentElement.setAttribute('data-theme', 'light');
            }
        })();
        </script>
        """
        html = html.replacingOccurrences(of: "<head>", with: "<head>\(darkModeScript)")

        // Write to a temp file in the same directory so relative asset paths also work
        let tempFile = postDir.appendingPathComponent(".preview_temp.html")
        try? html.write(to: tempFile, atomically: true, encoding: .utf8)

        webView.loadFileURL(tempFile, allowingReadAccessTo: blogRoot)
    }

    private func relativePathToRoot(from postDir: URL, to blogRoot: URL) -> String {
        let postComponents = postDir.standardizedFileURL.pathComponents
        let rootComponents = blogRoot.standardizedFileURL.pathComponents

        // Count how many levels deep the post is relative to root
        let extra = postComponents.count - rootComponents.count
        if extra <= 0 { return "" }
        return String(repeating: "../", count: extra)
    }
}
