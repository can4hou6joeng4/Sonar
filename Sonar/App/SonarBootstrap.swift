import Foundation
import Observation
import SwiftData

/// A failed open keeps the app in recovery; only opening the original store can leave it.
@MainActor @Observable
final class SonarBootstrap {
    private(set) var container: ModelContainer?
    private(set) var failed = false
    private let open: () throws -> ModelContainer

    init(open: @escaping () throws -> ModelContainer = { try SonarModelContainer.make() }) {
        self.open = open
        retry()
    }

    func retry() {
        guard container == nil else { return }
        do {
            container = try open()
            failed = false
        } catch {
            // Raw Core Data errors can contain paths and persisted values.
            failed = true
        }
    }
}

struct StoreRecoveryArchive: Codable {
    struct File: Codable {
        let name: String
        let data: Data
    }

    let format: String
    let version: Int
    let createdAt: Date
    let files: [File]

    static func capture(storeURL: URL) throws -> Data {
        let manager = FileManager.default
        let urls = [storeURL, URL(fileURLWithPath: storeURL.path + "-wal"),
                    URL(fileURLWithPath: storeURL.path + "-shm")]
            .filter { manager.fileExists(atPath: $0.path) }
        guard !urls.isEmpty else { throw RecoveryError.noFiles }

        // Called while startup is failed, before any live ModelContext exists.
        // Check the entire set before and after reading so an external change is rejected.
        func stamps() throws -> [String: FileStamp] {
            var result: [String: FileStamp] = [:]
            for url in [storeURL, URL(fileURLWithPath: storeURL.path + "-wal"),
                        URL(fileURLWithPath: storeURL.path + "-shm")] {
                guard manager.fileExists(atPath: url.path) else { continue }
                let attributes = try manager.attributesOfItem(atPath: url.path)
                guard attributes[.type] as? FileAttributeType == .typeRegular else {
                    throw RecoveryError.unreadable
                }
                result[url.lastPathComponent] = FileStamp(
                    size: (attributes[.size] as? NSNumber)?.uint64Value ?? 0,
                    modified: attributes[.modificationDate] as? Date
                )
            }
            return result
        }
        let before = try stamps()
        let files = try urls.map { File(name: $0.lastPathComponent, data: try Data(contentsOf: $0)) }
        guard try stamps() == before,
              files.count == before.count,
              files.allSatisfy({ UInt64($0.data.count) == before[$0.name]?.size }) else {
            throw RecoveryError.changed
        }
        let archive = Self(format: "sonar-store-recovery", version: 1, createdAt: Date(), files: files)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(archive)
    }

    private struct FileStamp: Equatable {
        let size: UInt64
        let modified: Date?
    }

    enum RecoveryError: LocalizedError {
        case noFiles, changed, unreadable

        var errorDescription: String? {
            switch self {
            case .noFiles: return "未找到可导出的资料文件，请重试打开资料库。"
            case .changed: return "资料文件发生变化，请重新导出。"
            case .unreadable: return "暂时无法读取资料文件，请稍后重试。"
            }
        }
    }
}

enum AppVersion {
    static func display(info: [String: Any] = Bundle.main.infoDictionary ?? [:]) -> String {
        let version = (info["CFBundleShortVersionString"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let build = (info["CFBundleVersion"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = [version, build].compactMap { value in
            value.flatMap { $0.isEmpty ? nil : $0 }
        }
        switch parts.count {
        case 2: return "版本 \(parts[0])（\(parts[1])）"
        case 1: return "版本 \(parts[0])"
        default: return "版本信息不可用"
        }
    }
}
