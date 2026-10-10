import SwiftUI

struct MacSettingsView: View {
    @Bindable var model: MacAppModel
    @AppStorage("macAppearance") private var appearance = "system"
    @State private var qualityNotice: String?
    @State private var importPresentation: ImportPresentation?

    private struct ImportPresentation: Identifiable {
        let id = UUID()
        let library: LibraryStore
    }

    var body: some View {
        TabView {
            Form {
                Section("外观") {
                    Picker("外观模式", selection: $appearance) {
                        Text("跟随系统").tag("system")
                        Text("浅色").tag("light")
                        Text("深色").tag("dark")
                    }
                }
                Section("刘海播放器") {
                    Toggle("显示在屏幕顶部", isOn: $model.notchEnabled)
                    Text("将指针移到屏幕顶部，展开播放控制。在没有刘海的显示器上，同样可以使用。")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("显示播放器") { model.showNotch() }
                }
            }.formStyle(.grouped).tabItem { Label("通用", systemImage: "gearshape") }
            Form {
                Section("音频") {
                    Picker("首选音质", selection: Binding(get: { model.playback.preferredQuality }, set: { quality in
                        Task {
                            let result = await model.playback.setPreferredQuality(quality)
                            switch result {
                            case .unchanged: qualityNotice = "已使用该音质设置。"
                            case .reloaded: qualityNotice = "已更新当前歌曲的音质。"
                            case .deferred: qualityNotice = "下一首歌曲将使用新的音质设置。"
                            case .failed(let message): qualityNotice = message
                            }
                        }
                    })) {
                        ForEach(Quality.allCases, id: \.self) { Text($0.macTitle).tag($0) }
                    }
                    Text("默认先尝试最高母带音质，无法获取时逐级降低。手动选择其他档位可调整尝试起点。")
                        .font(.callout).foregroundStyle(.secondary)
                    Slider(value: Binding(get: { model.playback.volume }, set: { model.playback.setVolume($0) }), in: 0...1) { Text("音量") }
                    if let qualityNotice { Text(qualityNotice).font(.callout).foregroundStyle(.secondary) }
                }
            }.formStyle(.grouped).tabItem { Label("播放", systemImage: "speaker.wave.2") }
            Form {
                Section("歌单迁移") {
                    Button("从 QQ 音乐或网易云导入…") {
                        if let library = model.library { importPresentation = ImportPresentation(library: library) }
                    }.disabled(model.library == nil)
                    Text("粘贴公开歌单分享链接，预览后合并到个人歌单。")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Section("歌单备份") {
                    LabeledContent("个人歌单", value: "\(model.libraryTracks.count) 首歌曲")
                    HStack {
                        Button("导入备份…") { model.importBackup() }
                        Button("导出备份…") { model.exportBackup() }
                    }.disabled(model.library == nil)
                    Text("备份保存歌曲信息。导入会合并已有收藏并跳过重复歌曲，不包含音频文件。")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped).tabItem { Label("资料库", systemImage: "externaldrive") }
        }.padding(12).frame(width: 530, height: 360)
        .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
        .sheet(item: $importPresentation) { presentation in
            OnlinePlaylistImportView(service: model.onlinePlaylistImporter, library: presentation.library,
                                     artworkService: model.artworkService,
                                     onImported: model.reloadLibrary)
                .frame(width: 530, height: 620)
        }
    }
}
