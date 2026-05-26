import Foundation

/// Wraps the `claude` CLI to stream AI responses
class AIRunner {
    static let shared = AIRunner()

    private var currentProcess: Process?

    var isRunning: Bool { currentProcess?.isRunning ?? false }

    /// Run claude CLI with a prompt, streaming output line by line.
    /// - Parameters:
    ///   - prompt: The user instruction
    ///   - context: Optional document context (selected text or full markdown)
    ///   - onOutput: Called on main thread with each chunk of text as it streams
    ///   - onComplete: Called on main thread when done (nil error = success)
    func run(prompt: String, context: String? = nil, onOutput: @escaping (String) -> Void, onComplete: @escaping (Error?) -> Void) {
        cancel()

        let claudePath = BlogSettings.shared.claudePath

        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)
        process.arguments = ["--print", "--output-format", "text"]

        // Build the full prompt with context
        var fullPrompt = ""
        if let ctx = context, !ctx.isEmpty {
            fullPrompt += "<document>\n\(ctx)\n</document>\n\n"
        }
        fullPrompt += prompt

        // Pipe prompt via stdin
        let inputPipe = Pipe()
        process.standardInput = inputPipe

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        // Stream stdout
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async { onOutput(text) }
        }

        process.terminationHandler = { proc in
            outputPipe.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async {
                if proc.terminationStatus == 0 {
                    onComplete(nil)
                } else {
                    onComplete(AIError.processFailed(code: proc.terminationStatus))
                }
            }
        }

        do {
            try process.run()
            currentProcess = process

            // Write prompt to stdin then close
            let promptData = fullPrompt.data(using: .utf8) ?? Data()
            inputPipe.fileHandleForWriting.write(promptData)
            inputPipe.fileHandleForWriting.closeFile()
        } catch {
            onComplete(error)
        }
    }

    func cancel() {
        if let p = currentProcess, p.isRunning {
            p.terminate()
        }
        currentProcess = nil
    }

    enum AIError: LocalizedError {
        case processFailed(code: Int32)

        var errorDescription: String? {
            switch self {
            case .processFailed(let code):
                return "claude exited with code \(code)"
            }
        }
    }
}
