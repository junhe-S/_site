import Cocoa

class BuildRunner {
    static let shared = BuildRunner()

    private var buildProcess: Process?

    func buildPost(slug: String, showAlert: Bool = true, noExec: Bool = false, completion: ((Bool) -> Void)? = nil) {
        var args = ["--post", slug]
        if noExec { args.append("--no-exec") }
        runBuildCommand(args, successMessage: showAlert ? "Built '\(slug)' successfully." : nil, silent: !showAlert, completion: completion)
    }

    func buildAll() {
        runBuildCommand([], successMessage: "Built all posts successfully.")
    }

    func deploy() {
        guard let blogDir = BlogSettings.shared.blogDirectory else {
            showAlert(title: "No Blog Directory", message: "Set your blog directory first (File > Set Blog Directory).")
            return
        }

        // First build all
        runBuildCommand([], successMessage: nil) { [weak self] success in
            guard success else { return }
            self?.runDeployCommand(at: blogDir)
        }
    }

    private func runBuildCommand(_ extraArgs: [String], successMessage: String?, silent: Bool = false, completion: ((Bool) -> Void)? = nil) {
        guard let blogDir = BlogSettings.shared.blogDirectory else {
            if !silent { showAlert(title: "No Blog Directory", message: "Set your blog directory first (File > Set Blog Directory).") }
            completion?(false)
            return
        }

        let buildScript = blogDir.appendingPathComponent("build.py")
        guard FileManager.default.fileExists(atPath: buildScript.path) else {
            if !silent { showAlert(title: "Build Script Not Found", message: "build.py not found in \(blogDir.path)") }
            completion?(false)
            return
        }

        let process = Process()
        let pythonPath = BlogSettings.shared.pythonPath
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = [buildScript.path] + extraArgs
        process.currentDirectoryURL = blogDir

        // Ensure the Python env's bin dir is in PATH so subprocess calls find the right python/Rscript
        let pythonBinDir = (pythonPath as NSString).deletingLastPathComponent
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = pythonBinDir + ":" + (env["PATH"] ?? "/usr/bin:/bin")
        process.environment = env

        NSLog("JunEdit Build: %@ %@", pythonPath, ([buildScript.path] + extraArgs).joined(separator: " "))

        let pipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errorPipe

        process.terminationHandler = { proc in
            DispatchQueue.main.async {
                let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let errorOutput = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

                NSLog("JunEdit Build exit=%d stdout=%@ stderr=%@", proc.terminationStatus, String(output.prefix(500)) as NSString, String(errorOutput.prefix(500)) as NSString)

                if proc.terminationStatus == 0 {
                    if let msg = successMessage {
                        self.showNotification(title: "Build Complete", message: msg)
                    }
                    completion?(true)
                } else {
                    if !silent {
                        self.showAlert(title: "Build Failed", message: "Exit code: \(proc.terminationStatus)\n\n\(errorOutput)\n\(output)")
                    }
                    completion?(false)
                }
            }
        }

        do {
            try process.run()
            buildProcess = process
        } catch {
            showAlert(title: "Build Error", message: error.localizedDescription)
            completion?(false)
        }
    }

    func deletePost(slug: String) {
        guard let blogDir = BlogSettings.shared.blogDirectory else { return }

        // Rebuild post listing first
        runBuildCommand([], successMessage: nil) { [weak self] _ in
            self?.runDeleteDeploy(slug: slug, at: blogDir)
        }
    }

    private func runDeleteDeploy(slug: String, at blogDir: URL) {
        let commands = [
            ["git", "-C", blogDir.path, "rm", "-r", "--cached", "posts/\(slug)"],
            ["git", "-C", blogDir.path, "add", "posts/index.html"],
            ["git", "-C", blogDir.path, "commit", "-m", "Delete post: \(slug)"],
            ["git", "-C", blogDir.path, "push"],
        ]

        DispatchQueue.global(qos: .userInitiated).async {
            var lastError: String?

            for cmd in commands {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = cmd
                process.currentDirectoryURL = blogDir

                let errorPipe = Pipe()
                process.standardError = errorPipe
                process.standardOutput = Pipe()

                do {
                    try process.run()
                    process.waitUntilExit()

                    if process.terminationStatus != 0 {
                        let err = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                        if cmd.contains("commit") && err.contains("nothing to commit") {
                            continue
                        }
                        lastError = "Command failed: \(cmd.joined(separator: " "))\n\(err)"
                        break
                    }
                } catch {
                    lastError = error.localizedDescription
                    break
                }
            }

            DispatchQueue.main.async {
                if let error = lastError {
                    self.showAlert(title: "Delete Deploy Failed", message: error)
                } else {
                    self.showNotification(title: "Deleted", message: "Post '\(slug)' removed from website.")
                }
            }
        }
    }

    private func runDeployCommand(at blogDir: URL) {
        let commands = [
            ["git", "-C", blogDir.path, "add", "-A"],
            ["git", "-C", blogDir.path, "commit", "-m", "Update blog posts"],
            ["git", "-C", blogDir.path, "push"],
        ]

        DispatchQueue.global(qos: .userInitiated).async {
            var lastError: String?

            for cmd in commands {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = cmd
                process.currentDirectoryURL = blogDir

                let errorPipe = Pipe()
                process.standardError = errorPipe
                process.standardOutput = Pipe()

                do {
                    try process.run()
                    process.waitUntilExit()

                    if process.terminationStatus != 0 {
                        let err = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                        // git commit returns 1 when nothing to commit — that's ok
                        if cmd.contains("commit") && err.contains("nothing to commit") {
                            continue
                        }
                        lastError = "Command failed: \(cmd.joined(separator: " "))\n\(err)"
                        break
                    }
                } catch {
                    lastError = error.localizedDescription
                    break
                }
            }

            DispatchQueue.main.async {
                if let error = lastError {
                    self.showAlert(title: "Deploy Failed", message: error)
                } else {
                    self.showNotification(title: "Deployed", message: "Site pushed to remote successfully.")
                }
            }
        }
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func showNotification(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.runModal()
    }
}
