import AVFoundation
import Foundation

public enum LocalAudioScanner {
    public static let supportedExtensions: Set<String> = [
        "mp3", "flac", "m4a", "wav", "aac", "aiff", "aif", "alac", "ogg"
    ]

    public static func isAudioFile(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    public static func scan(urls: [URL]) async -> [Track] {
        var fileURLs: [URL] = []
        for url in urls {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }

            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
                if isDir.boolValue {
                    if let enumerator = FileManager.default.enumerator(
                        at: url,
                        includingPropertiesForKeys: [.isRegularFileKey],
                        options: [.skipsHiddenFiles, .skipsPackageDescendants]
                    ) {
                        for case let file as URL in enumerator {
                            if isAudioFile(file) {
                                fileURLs.append(file)
                            }
                        }
                    }
                } else if isAudioFile(url) {
                    fileURLs.append(url)
                }
            }
        }

        var tracks: [Track] = []
        for fileURL in fileURLs {
            if let track = await track(from: fileURL) {
                tracks.append(track)
            }
        }
        return tracks
    }

    public static func track(from fileURL: URL) async -> Track? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let asset = AVURLAsset(url: fileURL)

        var title = fileURL.deletingPathExtension().lastPathComponent
        var artist = "本地音乐"
        var album = fileURL.deletingLastPathComponent().lastPathComponent

        if let metadata = try? await asset.load(.commonMetadata) {
            for item in metadata {
                guard let key = item.commonKey else { continue }
                if key == .commonKeyTitle,
                   let value = try? await item.load(.stringValue),
                   !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    title = value.trimmingCharacters(in: .whitespacesAndNewlines)
                } else if key == .commonKeyArtist,
                          let value = try? await item.load(.stringValue),
                          !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    artist = value.trimmingCharacters(in: .whitespacesAndNewlines)
                } else if key == .commonKeyAlbumName,
                          let value = try? await item.load(.stringValue),
                          !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    album = value.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }

        var intervalString: String? = nil
        if let duration = try? await asset.load(.duration) {
            let seconds = Int(CMTimeGetSeconds(duration))
            if seconds > 0 {
                let minutes = seconds / 60
                let remaining = seconds % 60
                intervalString = "\(minutes):\(String(format: "%02d", remaining))"
            }
        }

        var rawPayload: [String: Any] = [
            "filePath": fileURL.path,
            "filename": fileURL.lastPathComponent,
            "fileSize": (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size]) ?? 0
        ]

        #if os(macOS)
        if let bookmarkData = try? fileURL.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            rawPayload["bookmark"] = bookmarkData.base64EncodedString()
        }
        #endif

        let payload = (try? JSONSerialization.data(withJSONObject: rawPayload, options: [.sortedKeys])) ?? Data()

        return Track(
            source: .local,
            songmid: fileURL.path,
            title: title,
            artist: artist,
            album: album,
            interval: intervalString,
            payload: payload
        )
    }
}
