import Foundation
import os

/// 轻量性能埋点：同时写 os_signpost（Instruments）和 Documents/perf.log（可直接拉取比对）。
enum PerfLog {
    private static let logger = Logger(subsystem: "cn.bobochang.sonar", category: "perf")
    private static let signposter = OSSignposter(subsystem: "cn.bobochang.sonar", category: "perf")
    private static let startedAt = ProcessInfo.processInfo.systemUptime
    private static let queue = DispatchQueue(label: "cn.bobochang.sonar.perflog")

    private static let fileURL: URL? = {
        guard let dir = try? FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        return dir.appendingPathComponent("perf.log")
    }()

    static func mark(_ name: String, _ detail: String = "") {
        let ms = Int((ProcessInfo.processInfo.systemUptime - startedAt) * 1000)
        let line = "\(ms)\t\(name)\t\(detail)\n"
        logger.info("perf \(name, privacy: .public) \(detail, privacy: .public) at \(ms)ms")
        signposter.emitEvent("perf", "\(name, privacy: .public) \(ms)ms")
        queue.async {
            guard let fileURL else { return }
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: Data(line.utf8))
            } else {
                try? Data(line.utf8).write(to: fileURL)
            }
        }
    }
}
