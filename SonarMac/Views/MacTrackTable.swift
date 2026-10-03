import SwiftUI

private struct MacTrackRow: Identifiable {
    let track: Track
    let index: Int
    var id: String { track.musicID }
}

struct MacTrackTable: View {
    let model: MacAppModel
    let tracks: [Track]
    var allowsRemoval = false
    @State private var selection = Set<String>()

    private var rows: [MacTrackRow] {
        var seen = Set<String>()
        return tracks.enumerated().compactMap { index, track in
            seen.insert(track.musicID).inserted ? MacTrackRow(track: track, index: index) : nil
        }
    }

    var body: some View {
        Table(rows, selection: $selection) {
            TableColumn("歌曲") { row in
                HStack(spacing: 10) {
                    MacArtworkView(track: row.track, service: model.artworkService, size: 34, radius: 6)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.track.title).fontWeight(model.playback.queue.current?.musicID == row.id ? .semibold : .regular)
                            .lineLimit(1)
                        Text(row.track.source.displayName).font(.caption2).foregroundStyle(.tertiary)
                    }
                    if model.playback.queue.current?.musicID == row.id {
                        Image(systemName: model.playback.state == .playing ? "waveform" : "pause.fill")
                            .foregroundStyle(.tint).accessibilityLabel("当前播放")
                    }
                }
                .padding(.vertical, 4)
            }.width(min: 180, ideal: 260)
            TableColumn("歌手") { row in Text(row.track.artist).foregroundStyle(.secondary).lineLimit(1) }
                .width(min: 90, ideal: 135)
            TableColumn("专辑") { row in Text(row.track.album).foregroundStyle(.secondary).lineLimit(1) }
                .width(min: 90, ideal: 160)
            TableColumn("时长") { row in
                Text(row.track.interval ?? "—").monospacedDigit().foregroundStyle(.secondary)
            }.width(48)
        }
        .contextMenu(forSelectionType: String.self) { selectedIDs in
            let selected = rows.filter { selectedIDs.contains($0.id) }
            if let first = selected.first {
                Button("播放", systemImage: "play.fill") { play(first.index) }
                Button("下一首播放", systemImage: "text.line.first.and.arrowtriangle.forward") {
                    Task {
                        if model.playback.queue.current == nil {
                            for row in selected { _ = await model.playback.enqueue(row.track) }
                        } else {
                            for row in selected.reversed() { await model.playback.playNext(row.track) }
                        }
                    }
                }
                Button("添加到个人歌单", systemImage: "heart") { selected.forEach { model.collect($0.track) } }
                if allowsRemoval {
                    Divider()
                    Button("从个人歌单移除", systemImage: "heart.slash", role: .destructive) {
                        selected.forEach { model.removeFavorite($0.track) }
                    }
                }
            }
        } primaryAction: { selectedIDs in
            if let row = rows.first(where: { selectedIDs.contains($0.id) }) { play(row.index) }
        }
        .overlay {
            if tracks.isEmpty { MacEmptyState(title: "这里还没有歌曲", description: "搜索音乐，或导入已有的 Sonar 歌单。") }
        }
        .onChange(of: tracks.map(\.musicID)) { _, ids in selection.formIntersection(ids) }
        .accessibilityLabel("歌曲列表，双击播放")
    }

    private func play(_ index: Int) {
        Task {
            if allowsRemoval { await model.playFavorites(at: index) }
            else { await model.play(tracks, at: index) }
        }
    }
}
