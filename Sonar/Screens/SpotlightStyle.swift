import SwiftData
import SwiftUI
import UIKit

// iOS presentation palette. Shared playback, data, and Mac appearance remain independent.
extension M3Scheme {
    static func spotlight(dark: Bool) -> M3Scheme {
        let surface = dark ? "#242529" : "#F4F1EC"
        let card = dark ? "#303136" : "#FFFFFF"
        let ink = dark ? "#F8F6F2" : "#292725"
        let muted = dark ? "#B9B8BE" : "#73706E"
        let accent = dark ? "#F1E9DF" : "#51443B"
        let container = dark ? "#454044" : "#E6DCD1"
        return M3Scheme(seedHex: accent, isDark: dark, hex: HexValues(
            primary: accent, onPrimary: dark ? "#292725" : "#FFFFFF",
            primaryContainer: container, onPrimaryContainer: ink,
            secondary: accent, secondaryContainer: container, onSecondaryContainer: ink,
            tertiaryContainer: container, onTertiaryContainer: ink,
            surface: surface, surfaceContainerLowest: surface, surfaceContainerLow: card,
            surfaceContainer: card, surfaceContainerHigh: card, surfaceContainerHighest: card,
            onSurface: ink, onSurfaceVariant: muted, outline: dark ? "#77767C" : "#9B9793",
            outlineVariant: dark ? "#3A3B40" : "#E0DCD7", error: "#ED8B82", onError: "#FFFFFF",
            appSurface: surface, appInputFill: card, capsuleBackground: card
        ))
    }
}

enum SpotlightLayout {
    static let navigationHeight: CGFloat = 50
    static let miniPlayerHeight: CGFloat = 62
    static let chromeSpacing: CGFloat = 8
    static let bottomPadding: CGFloat = 6

    static func bottomReservation(hasTrack: Bool) -> CGFloat {
        navigationHeight + bottomPadding + 12
            + (hasTrack ? miniPlayerHeight + chromeSpacing : 0)
    }
}

/// Flexible artwork for the full-width hero, using the existing coalesced cache.
struct SpotlightArtwork: View {
    let track: Track?
    @Environment(\.artworkService) private var artworkService
    @Environment(\.m3Scheme) private var scheme
    @Environment(\.sonarReduceMotion) private var reduceMotion
    @State private var image: UIImage?
    @State private var displayedTrackID: String?
    @State private var requests = ArtworkRequestGate()

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .id(displayedTrackID)
                        .transition(.opacity)
                } else {
                    LinearGradient(colors: [scheme.primaryContainer, scheme.appSurface], startPoint: .topLeading, endPoint: .bottomTrailing)
                        .overlay {
                            Image(systemName: "waveform")
                                .font(.system(size: 92, weight: .ultraLight))
                                .foregroundStyle(scheme.primary.opacity(0.28))
                        }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .task(id: track?.musicID) {
            let request = requests.begin(trackID: track?.musicID)
            guard let track, let artworkService else {
                image = nil
                displayedTrackID = nil
                return
            }
            let loaded = try? await artworkService.image(for: track)
            requests.commit(request, currentTrackID: track.musicID) {
                withAnimation(AppMotion.emphasized(duration: 0.4, reduceMotion: reduceMotion)) {
                    image = loaded
                    displayedTrackID = track.musicID
                }
            }
        }
        .accessibilityHidden(true)
    }
}

struct SonarWelcomeView: View {
    let onComplete: () -> Void

    @Environment(\.sonarReduceMotion) private var reduceMotion
    @Query(sort: \Playlist.sortIndex) private var playlists: [Playlist]
    @State private var coverIsVisible = false
    @State private var discIsRevealed = false
    @State private var brandIsVisible = false
    @State private var taglineIsVisible = false
    @State private var discRotation = -24.0
    @State private var introOpacity = 1.0

    private var track: Track? {
        playlists.first { $0.isPrimaryPersonal && !$0.isArchived }?.orderedItems.first?.track.track
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.57, green: 0.19, blue: 0.17), Color(red: 0.14, green: 0.07, blue: 0.11)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .overlay {
                    RadialGradient(colors: [Color.red.opacity(0.18), .clear], center: UnitPoint(x: 0.5, y: 0.4), startRadius: 0, endRadius: 360)
                        .ignoresSafeArea()
                }
            VStack(spacing: 32) {
                ZStack {
                    Circle()
                        .fill(AngularGradient(colors: [.black, Color(white: 0.16), .black, Color(white: 0.23), .black], center: .center))
                        .frame(width: 174, height: 174)
                        .overlay {
                            ForEach(0..<7) { index in
                                Circle().stroke(.white.opacity(0.045), lineWidth: 1)
                                    .padding(CGFloat(8 + index * 9))
                            }
                        }
                        .overlay { PlayerArtwork(track: track, size: 52, circular: true) }
                        .rotationEffect(.degrees(reduceMotion ? 0 : discRotation))
                        .offset(x: discIsRevealed ? 62 : 0)
                    PlayerArtwork(track: track, size: 180, cornerRadius: 9)
                        .offset(x: discIsRevealed ? -40 : 0)
                        .shadow(color: .black.opacity(0.30), radius: 18, y: 10)
                }
                .scaleEffect(coverIsVisible || reduceMotion ? 1 : 0.88)
                .opacity(coverIsVisible ? 1 : 0)
                VStack(spacing: 8) {
                    Text("sonar")
                        .font(.system(size: 52, weight: .heavy, design: .rounded))
                        .tracking(-2.5)
                        .opacity(brandIsVisible ? 1 : 0)
                        .offset(y: brandIsVisible || reduceMotion ? 0 : 16)
                    Text("在深水里，靠声音辨路。")
                        .font(.system(size: 14, design: .serif))
                        .foregroundStyle(.white.opacity(0.70))
                        .opacity(taglineIsVisible ? 1 : 0)
                        .offset(y: taglineIsVisible || reduceMotion ? 0 : 8)
                }
            }
            .foregroundStyle(.white)
        }
        .opacity(introOpacity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sonar 音乐播放器")
        .task(id: reduceMotion) { await runIntro() }
    }

    @MainActor
    private func runIntro() async {
        do {
            if reduceMotion {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    coverIsVisible = true
                    discIsRevealed = true
                    brandIsVisible = true
                    taglineIsVisible = true
                    introOpacity = 1
                }
                try await Task.sleep(for: .milliseconds(150))
            } else {
                await Task.yield()
                try Task.checkCancellation()
                withAnimation(.easeOut(duration: 0.55)) { coverIsVisible = true }
                try await Task.sleep(for: .milliseconds(420))
                withAnimation(.timingCurve(0.22, 0.7, 0.18, 1, duration: 0.8)) {
                    discIsRevealed = true
                }
                withAnimation(.linear(duration: 2.5)) { discRotation = 190 }
                try await Task.sleep(for: .milliseconds(520))
                withAnimation(.easeOut(duration: 0.45)) { brandIsVisible = true }
                try await Task.sleep(for: .milliseconds(160))
                withAnimation(.easeOut(duration: 0.4)) { taglineIsVisible = true }
                try await Task.sleep(for: .milliseconds(900))
                withAnimation(.easeInOut(duration: 0.6)) {
                    discIsRevealed = false
                    brandIsVisible = false
                    taglineIsVisible = false
                    introOpacity = 0
                }
                try await Task.sleep(for: .milliseconds(650))
            }
            try Task.checkCancellation()
            onComplete()
        } catch {
            // Leaving the root or changing motion preferences cancels this sequence.
        }
    }
}
