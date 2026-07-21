import Foundation

/// Appends verbose generation telemetry to Application Support for field debugging.
enum GenerationLogFile {
    private static let fileName = "generation.log"
    private static let queue = DispatchQueue(label: "com.prateekranka.creatorcontenthelper.generation-log")

    static var fileURL: URL? {
        guard let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let folder = root
            .appendingPathComponent("CreatorContentOS", isDirectory: true)
            .appendingPathComponent("Logs", isDirectory: true)
        return folder.appendingPathComponent(fileName, isDirectory: false)
    }

    static func append(_ line: String) {
        queue.async {
            guard let fileURL else { return }
            let folder = fileURL.deletingLastPathComponent()
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let payload = line + "\n"
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    let handle = try FileHandle(forWritingTo: fileURL)
                    defer { try? handle.close() }
                    try handle.seekToEnd()
                    if let data = payload.data(using: .utf8) {
                        try handle.write(contentsOf: data)
                    }
                } else {
                    try payload.write(to: fileURL, atomically: true, encoding: .utf8)
                }
            } catch {
                print("[ContentHelperGeneration] log_file_write_failed error=\(error.localizedDescription)")
            }
        }
    }
}
