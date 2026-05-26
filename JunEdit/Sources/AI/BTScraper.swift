import Foundation

/// Scrapes Bergens Tidende articles using Facebookbot UA to bypass paywall.
enum BTScraper {
    /// Facebookbot UA — BT serves full content to Facebook's crawler.
    private static let userAgent = "facebookexternalhit/1.1 (+http://www.facebook.com/externalhit_uatext.php)"

    struct Article {
        let headline: String
        let paragraphs: [String]
        let imageURL: String?       // First figure image URL
        let imageCaption: String?   // First figure caption
        let sourceURL: String
    }

    /// Fetch and parse a BT article from URL.
    static func fetch(url: String, completion: @escaping (Article?) -> Void) {
        guard let requestURL = URL(string: url) else {
            completion(nil)
            return
        }

        var request = URLRequest(url: requestURL, timeoutInterval: 30)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("nb-NO,nb;q=0.9,no;q=0.8,en-US;q=0.7,en;q=0.6", forHTTPHeaderField: "Accept-Language")

        URLSession.shared.dataTask(with: request) { data, _, error in
            guard let data = data, error == nil,
                  let html = String(data: data, encoding: .utf8) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let article = parse(html: html, sourceURL: url)
            DispatchQueue.main.async { completion(article) }
        }.resume()
    }

    /// Fetch the BT front page and return article URLs.
    static func fetchLatestURLs(completion: @escaping ([String]) -> Void) {
        let frontURL = URL(string: "https://www.bt.no/")!
        var request = URLRequest(url: frontURL, timeoutInterval: 30)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { data, _, error in
            guard let data = data, error == nil,
                  let html = String(data: data, encoding: .utf8) else {
                DispatchQueue.main.async { completion([]) }
                return
            }

            // Extract article URLs from data-pulse-url attributes or href links
            let pattern = #"(?:data-pulse-url|href)="(https://www\.bt\.no/[^"]+/i/[^"]+)""#
            let urls = matches(for: pattern, in: html)
                .map { $0.replacingOccurrences(of: "&amp;", with: "&") }
            let unique = Array(NSOrderedSet(array: urls)) as? [String] ?? []
            DispatchQueue.main.async { completion(Array(unique.prefix(20))) }
        }.resume()
    }

    // MARK: - Parsing

    private static func parse(html: String, sourceURL: String) -> Article? {
        // Extract headline from <h1>
        let headline: String
        if let h1Match = firstMatch(for: #"<h1[^>]*>(.*?)</h1>"#, in: html, options: .dotMatchesLineSeparators) {
            headline = stripHTML(h1Match).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            headline = "Untitled"
        }

        // Extract paragraphs from <article>
        var paragraphs: [String] = []
        if let articleBody = firstMatch(for: #"<article[^>]*>(.*?)</article>"#, in: html, options: .dotMatchesLineSeparators) {
            let pMatches = matches(for: #"<p[^>]*>(.*?)</p>"#, in: articleBody, options: .dotMatchesLineSeparators)
            for p in pMatches {
                let text = stripHTML(p).trimmingCharacters(in: .whitespacesAndNewlines)
                if text.count > 15 { paragraphs.append(text) }
            }
        }

        guard !paragraphs.isEmpty else { return nil }

        // Extract first figure image
        var imageURL: String?
        var imageCaption: String?
        let figures = matches(for: #"<figure[^>]*>(.*?)</figure>"#, in: html, options: .dotMatchesLineSeparators)
        if let firstFig = figures.first {
            if let src = firstMatch(for: #"src="([^"]+)""#, in: firstFig) {
                imageURL = src.replacingOccurrences(of: "&amp;", with: "&")
            }
            if let cap = firstMatch(for: #"<figcaption[^>]*>(.*?)</figcaption>"#, in: firstFig, options: .dotMatchesLineSeparators) {
                imageCaption = stripHTML(cap).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return Article(
            headline: headline,
            paragraphs: paragraphs,
            imageURL: imageURL,
            imageCaption: imageCaption,
            sourceURL: sourceURL
        )
    }

    /// Download image data from URL.
    static func downloadImage(url: String, to destination: URL, completion: @escaping (Bool) -> Void) {
        guard let imgURL = URL(string: url) else { completion(false); return }
        URLSession.shared.dataTask(with: imgURL) { data, _, error in
            guard let data = data, error == nil, data.count > 1000 else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            do {
                try data.write(to: destination)
                DispatchQueue.main.async { completion(true) }
            } catch {
                DispatchQueue.main.async { completion(false) }
            }
        }.resume()
    }

    // MARK: - Regex helpers

    private static func firstMatch(for pattern: String, in text: String, options: NSRegularExpression.Options = []) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        let nsText = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)),
              match.numberOfRanges > 1 else { return nil }
        return nsText.substring(with: match.range(at: 1))
    }

    private static func matches(for pattern: String, in text: String, options: NSRegularExpression.Options = []) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
        let nsText = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)).compactMap { match in
            match.numberOfRanges > 1 ? nsText.substring(with: match.range(at: 1)) : nil
        }
    }

    private static func stripHTML(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }
}
