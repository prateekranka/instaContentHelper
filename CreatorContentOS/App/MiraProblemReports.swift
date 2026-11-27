import Foundation
import MetricKit
import SwiftUI

@MainActor
@Observable
final class MiraProblemReports: NSObject, MXMetricManagerSubscriber {
    private(set) var files: [URL] = []

    private let directory: URL? = {
        var directory = URL.applicationSupportDirectory.appending(path: "ProblemReports", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try directory.setResourceValues(values)
            return directory
        } catch {
            return nil
        }
    }()

    private var runningFlag: URL? { directory?.appending(path: "running") }

    func start() {
        if let directory, let runningFlag {
            let previousSessionEndedCleanly = !FileManager.default.fileExists(atPath: runningFlag.path)
            setRunning(true)
            let facts: [String: Any] = [
                "appVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
                "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
                "osVersion": ProcessInfo.processInfo.operatingSystemVersionString,
                "previousSessionEndedCleanly": previousSessionEndedCleanly
            ]
            if let data = try? JSONSerialization.data(withJSONObject: facts) {
                try? data.write(to: directory.appending(path: "last-launch.json"), options: .atomic)
            }
            refreshFiles(in: directory)
        }
        MXMetricManager.shared.add(self)
    }

    func setRunning(_ running: Bool) {
        guard let runningFlag else { return }
        if running {
            try? Data().write(to: runningFlag, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: runningFlag)
        }
    }

    nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let reports = payloads.map { payload in
            let start = Int(payload.timeStampBegin.timeIntervalSince1970)
            let end = Int(payload.timeStampEnd.timeIntervalSince1970)
            return (name: "metrickit_\(end)_\(start)_\(UUID().uuidString).json", data: payload.jsonRepresentation())
        }
        Task { @MainActor in
            guard let directory else { return }
            for report in reports {
                try? report.data.write(to: directory.appending(path: report.name), options: .atomic)
            }
            refreshFiles(in: directory)
        }
    }

    private func refreshFiles(in directory: URL) {
        let fileManager = FileManager.default
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .creationDateKey]
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: Array(keys)
        ) else { return }
        let reports = urls.compactMap { url -> (url: URL, end: Int, created: Date)? in
            let parts = url.deletingPathExtension().lastPathComponent.split(separator: "_")
            guard url.pathExtension == "json",
                  parts.count == 4, parts[0] == "metrickit",
                  let end = Int(parts[1]), Int(parts[2]) != nil,
                  UUID(uuidString: String(parts[3])) != nil,
                  let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true else { return nil }
            return (url, end, values.creationDate ?? .distantPast)
        }.sorted {
            if $0.end != $1.end { return $0.end > $1.end }
            return $0.created > $1.created
        }
        for report in reports.dropFirst(20) {
            try? fileManager.removeItem(at: report.url)
        }
        files = reports.prefix(20).map(\.url)
    }
}
