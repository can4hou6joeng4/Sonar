import SwiftUI

struct MacHomeView: View {
    let model: MacAppModel
    let search: () -> Void
    let openFavorites: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("留一点时间，给音乐。")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                    Text("现在就听").font(.title3).foregroundStyle(.secondary)
                }
                hero
                if !model.recentTracks.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("继续聆听").font(.title2.bold())
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 18) {
                                ForEach(Array(model.recentTracks.prefix(10)), id: \.musicID) { track in
                                    Button {
                                        let index = model.recentTracks.firstIndex { $0.musicID == track.musicID } ?? 0
                                        Task { await model.play(model.recentTracks, at: index) }
                                    } label: {
                                        VStack(alignment: .leading, spacing: 8) {
                                            MacArtworkView(track: track, service: model.artworkService, size: 144, radius: 14)
                                            Text(track.title).fontWeight(.medium).lineLimit(1)
                                            Text(track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                        }.frame(width: 144, alignment: .leading)
                                    }.buttonStyle(.plain).help("播放 \(track.title)")
                                }
                            }.padding(.bottom, 4)
                        }
                    }
                }
                HStack(spacing: 20) {
                    Image(systemName: "heart.fill").font(.system(size: 32)).foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("你的个人歌单").font(.title3.bold())
                        Text("\(model.libraryTracks.count) 首收藏 · 保存在这台 Mac 上")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("打开歌单", action: openFavorites)
                }
                .padding(24).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 18))
            }.padding(30).frame(maxWidth: 1250, alignment: .leading).frame(maxWidth: .infinity)
        }
    }

    private var hero: some View {
        HStack(spacing: 30) {
            VStack(alignment: .leading, spacing: 14) {
                Label("SONAR FOR MAC", systemImage: "waveform").font(.caption.weight(.semibold)).tracking(2)
                    .foregroundStyle(.tint)
                Text(model.recentTracks.first?.title ?? "从一首好歌开始")
                    .font(.system(size: 30, weight: .semibold)).lineLimit(2)
                Text(model.recentTracks.first?.artist ?? "搜索喜欢的歌曲、歌手和歌单，发现属于你的声音。")
                    .foregroundStyle(.secondary).lineLimit(2)
                HStack(spacing: 12) {
                    if !model.recentTracks.isEmpty {
                        Button("继续播放", systemImage: "play.fill") { Task { await model.play(model.recentTracks) } }
                            .buttonStyle(.borderedProminent).controlSize(.large)
                    }
                    Button("探索音乐", systemImage: "magnifyingglass", action: search)
                        .controlSize(.large)
                }.padding(.top, 8)
            }.frame(maxWidth: .infinity, alignment: .leading)
            if let track = model.recentTracks.first {
                MacArtworkView(track: track, service: model.artworkService, size: 185, radius: 22)
                    .shadow(color: .black.opacity(0.15), radius: 18, y: 8)
            } else {
                Image(systemName: "waveform.circle")
                    .font(.system(size: 110, weight: .ultraLight)).foregroundStyle(Color.accentColor.opacity(0.6))
                    .frame(width: 185, height: 185).accessibilityHidden(true)
            }
        }.padding(30)
        .background {
            RoundedRectangle(cornerRadius: 24)
                .fill(LinearGradient(colors: [.accentColor.opacity(0.14), .accentColor.opacity(0.025)], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
    }
}
