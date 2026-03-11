import Foundation

class FileLog {
    static let shared = FileLog()

    private let fileHandle: FileHandle?
    private let logPath: String
    private let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        return f
    }()

    private init() {
        logPath = NSTemporaryDirectory() + "claude-usage.log"
        FileManager.default.createFile(atPath: logPath, contents: nil)
        fileHandle = FileHandle(forWritingAtPath: logPath)
        fileHandle?.seekToEndOfFile()
        info("=== ClaudeUsage started, log at \(logPath) ===")
    }

    func debug(_ message: String) { write("DEBUG", message) }
    func info(_ message: String) { write("INFO", message) }
    func warning(_ message: String) { write("WARN", message) }
    func error(_ message: String) { write("ERROR", message) }

    private func write(_ level: String, _ message: String) {
        let timestamp = formatter.string(from: Date())
        let line = "\(timestamp) [\(level)] \(message)\n"
        if let data = line.data(using: .utf8) {
            fileHandle?.write(data)
            fileHandle?.synchronizeFile()
        }
    }

    deinit {
        fileHandle?.closeFile()
    }
}
