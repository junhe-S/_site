import Foundation

class BlogSettings {
    static let shared = BlogSettings()
    private let defaults = UserDefaults.standard

    private let blogDirKey = "blogDirectory"
    private let pythonPathKey = "pythonPath"
    private let claudePathKey = "claudePath"

    var blogDirectory: URL? {
        get {
            guard let path = defaults.string(forKey: blogDirKey) else { return nil }
            return URL(fileURLWithPath: path)
        }
        set {
            defaults.set(newValue?.path, forKey: blogDirKey)
        }
    }

    var pythonPath: String {
        get { defaults.string(forKey: pythonPathKey) ?? "/opt/homebrew/anaconda3/envs/ban438/bin/python3" }
        set { defaults.set(newValue, forKey: pythonPathKey) }
    }

    var claudePath: String {
        get { defaults.string(forKey: claudePathKey) ?? "/opt/homebrew/bin/claude" }
        set { defaults.set(newValue, forKey: claudePathKey) }
    }

    var postsDirectory: URL? {
        blogDirectory?.appendingPathComponent("posts")
    }

    var buildScriptPath: URL? {
        blogDirectory?.appendingPathComponent("build.py")
    }

    /// All content sections matching site navigation
    static let sections = ["posts", "research", "data", "bergen"]

    func directoryFor(section: String) -> URL? {
        blogDirectory?.appendingPathComponent(section)
    }
}
