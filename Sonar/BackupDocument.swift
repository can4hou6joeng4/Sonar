import SwiftUI
import UniformTypeIdentifiers

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct LibraryRecoveryView: View {
    let retry: () -> Void
    @State private var isPreparing = false
    @State private var isExporting = false
    @State private var document: BackupDocument?
    @State private var message: String?

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 46))
                .foregroundStyle(.secondary)
            Text("暂时无法打开资料库")
                .font(.title2.bold())
            Text("你的资料文件会保留。可以重试打开，或先导出原始资料文件以便恢复。")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("重试打开", action: retry)
                .buttonStyle(.borderedProminent)
                .disabled(isPreparing || isExporting)
                .accessibilityIdentifier("library-recovery-retry")
            Button(isPreparing ? "正在准备…" : "导出原始资料文件") {
                exportOriginals()
            }
            .buttonStyle(.bordered)
            .disabled(isPreparing || isExporting)
            .accessibilityIdentifier("library-recovery-export")
            Text("原始资料文件用于故障恢复，不能作为歌单备份直接导入。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fileExporter(isPresented: $isExporting, document: document,
                      contentType: .json, defaultFilename: "Sonar-原始资料") { result in
            if case .failure = result { message = "导出未完成，请重试并选择可写入的位置。" }
        }
        .alert("资料库恢复", isPresented: Binding(
            get: { message != nil }, set: { if !$0 { message = nil } }
        )) {
            Button("好", role: .cancel) { message = nil }
        } message: { Text(message ?? "") }
    }

    private func exportOriginals() {
        isPreparing = true
        Task {
            do {
                let data = try await Task.detached(priority: .userInitiated) {
                    let directory = try FileManager.default.url(
                        for: .applicationSupportDirectory, in: .userDomainMask,
                        appropriateFor: nil, create: false
                    )
                    return try StoreRecoveryArchive.capture(storeURL: directory.appendingPathComponent("Sonar.store"))
                }.value
                document = BackupDocument(data: data)
                isExporting = true
            } catch let error as StoreRecoveryArchive.RecoveryError {
                message = error.localizedDescription
            } catch {
                message = "暂时无法导出原始资料文件，请稍后重试。"
            }
            isPreparing = false
        }
    }
}
