import Foundation

final class StreamLogger {
    static let shared = StreamLogger()

    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.streamvue.logger")
    private let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss.SSS"
        return df
    }()

    private init() {
        let logsDir: URL
        if let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            logsDir = caches.appendingPathComponent("StreamVue")
        } else {
            logsDir = FileManager.default.temporaryDirectory.appendingPathComponent("StreamVue")
        }
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        fileURL = logsDir.appendingPathComponent("stream.log")

        // Rotate: truncate if over 1MB
        if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
           let size = attrs[.size] as? Int, size > 1_000_000 {
            try? "".write(to: fileURL, atomically: true, encoding: .utf8)
        }

        // Log the path itself so we can find it
        let startLine = "--- StreamVue logger started: \(fileURL.path) ---\n"
        try? startLine.write(to: fileURL, atomically: false, encoding: .utf8)
        NSLog("StreamVue log file: %@", fileURL.path)
    }

    func log(_ message: String, level: String = "INFO") {
        let timestamp = dateFormatter.string(from: Date())
        let line = "[\(timestamp)] [\(level)] \(message)\n"
        queue.async { [fileURL] in
            if let data = line.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    if let handle = try? FileHandle(forWritingTo: fileURL) {
                        handle.seekToEndOfFile()
                        handle.write(data)
                        handle.closeFile()
                    }
                } else {
                    try? data.write(to: fileURL)
                }
            }
        }
    }

    var logFilePath: String { fileURL.path }
}
