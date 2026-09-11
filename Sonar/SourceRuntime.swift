import CryptoKit
import Foundation
import JavaScriptCore
import os

private enum RuntimeFailure: Error {
    case javascript(String)
}

private final class InvocationContinuationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data, Error>?
    private var completedResult: Result<Data, Error>?

    func install(_ continuation: CheckedContinuation<Data, Error>) {
        lock.lock()
        if let completedResult {
            lock.unlock()
            continuation.resume(with: completedResult)
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    func resume(with result: Result<Data, Error>) {
        lock.lock()
        guard completedResult == nil else {
            lock.unlock()
            return
        }
        completedResult = result
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}

public final class JavaScriptSourceRuntime: SourceRuntime, @unchecked Sendable {
    private let queue = DispatchQueue(label: "cn.bobochang.sonar.source-runtime")
    private let logger = Logger(subsystem: "cn.bobochang.sonar", category: "SourceRuntime")
    private var context: JSContext?
    private var initializationError: String?
    private var nextTimerID: Int = 0
    private var timers: [Int: DispatchWorkItem] = [:]

    public init(bundleURL: URL? = Bundle.main.url(forResource: "source-bundle", withExtension: "js")) {
        queue.async {
            self.context = JSContext()
            self.installHostFunctions()
            if let bundleURL, let source = try? String(contentsOf: bundleURL, encoding: .utf8) {
                _ = self.context?.evaluateScript(source)
                if let exception = self.context?.exception {
                    self.initializationError = exception.toString()
                    self.context?.exception = nil
                }
            }
        }
    }

    init(script: String) {
        queue.sync {
            self.context = JSContext()
            self.installHostFunctions()
            _ = self.context?.evaluateScript(script)
            if let exception = self.context?.exception {
                self.initializationError = exception.toString()
                self.context?.exception = nil
            }
        }
    }

    deinit {
        queue.sync {
            self.timers.values.forEach { $0.cancel() }
            self.timers.removeAll()
            self.context = nil
        }
    }

    func diagnostics() -> String {
        queue.sync {
            let sourceType = context?.evaluateScript("typeof globalThis.__source__")?.toString() ?? "missing-context"
            let globalType = context?.evaluateScript("typeof globalThis")?.toString() ?? "missing-context"
            let exception = context?.exception == nil && initializationError == nil ? "none" : "present"
            context?.exception = nil
            return "globalType=\(globalType); sourceType=\(sourceType); exception=\(exception)"
        }
    }

    public func search(_ keyword: String, source: MusicSource, page: Int = 1) async throws -> SearchPage {
        let data = try await invokeData("search", arguments: [source.rawValue, keyword, page, 25])
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawList = object["list"] as? [[String: Any]] else {
            throw SourceError.source(message: "音源返回搜索结果异常")
        }
        let tracks = try rawList.map { try Track(source: source, raw: $0) }
        return SearchPage(
            list: tracks,
            total: (object["total"] as? NSNumber)?.intValue ?? tracks.count,
            allPage: (object["allPage"] as? NSNumber)?.intValue ?? 1
        )
    }

    public func lyric(_ track: Track) async throws -> LyricInfo {
        try JSONDecoder().decode(LyricInfo.self, from: await invokeData("lyric", arguments: [track.source.rawValue, track.rawPayload]))
    }

    public func picURL(_ track: Track) async throws -> URL {
        let value = try JSONDecoder().decode(String.self, from: await invokeData("pic", arguments: [track.source.rawValue, track.rawPayload]))
        guard let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased()) else {
            throw SourceError.source(message: "音源返回封面地址异常")
        }
        return url
    }

    public func tipSearch(_ keyword: String) async throws -> [String] {
        try JSONDecoder().decode([String].self, from: await invokeData("tipSearch", arguments: [keyword]))
    }

    public func hotSearch(source: MusicSource) async throws -> [String] {
        try JSONDecoder().decode([String].self, from: await invokeData("hotSearch", arguments: [source.rawValue]))
    }

    public func playlistCatalog(
        source: MusicSource,
        sortId: String,
        tagId: String? = nil,
        page: Int = 1
    ) async throws -> PlaylistCatalogPage {
        try JSONDecoder().decode(
            PlaylistCatalogPage.self,
            from: await invokeData("playlistCatalog", arguments: [source.rawValue, sortId, tagId ?? NSNull(), page])
        )
    }

    public func playlistDetail(source: MusicSource, id: String, page: Int = 1) async throws -> PlaylistDetail {
        let data = try await invokeData("playlistDetail", arguments: [source.rawValue, id, page])
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawList = object["list"] as? [[String: Any]],
              let infoObject = object["info"] else {
            throw SourceError.source(message: "音源返回歌单详情异常")
        }
        let infoData = try JSONSerialization.data(withJSONObject: infoObject)
        let info = try JSONDecoder().decode(PlaylistDetailInfo.self, from: infoData)
        let tracks = try rawList.map { try Track(source: source, raw: $0) }
        return PlaylistDetail(
            list: tracks,
            total: (object["total"] as? NSNumber)?.intValue ?? tracks.count,
            page: (object["page"] as? NSNumber)?.intValue ?? 1,
            limit: (object["limit"] as? NSNumber)?.intValue ?? tracks.count,
            source: source,
            info: info
        )
    }

    public func searchArtists(_ keyword: String, source: MusicSource, page: Int = 1) async throws -> ArtistSearchPage {
        try await searchArtists(keyword, source: source, page: page, limit: 10)
    }

    public func searchArtists(
        _ keyword: String,
        source: MusicSource,
        page: Int,
        limit: Int
    ) async throws -> ArtistSearchPage {
        let normalizedPage = max(1, page)
        let normalizedLimit = max(1, limit)
        let data = try await invokeData(
            "artistSearch",
            arguments: [source.rawValue, keyword, normalizedPage, normalizedLimit]
        )
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawList = object["list"] as? [[String: Any]] else {
            throw SourceError.source(message: "音源返回歌手搜索结果异常")
        }
        let artists = rawList.compactMap { try? decodeArtist($0, source: source) }
        if !rawList.isEmpty, artists.isEmpty {
            throw SourceError.source(message: "音源返回歌手搜索结果异常")
        }
        return ArtistSearchPage(
            list: artists,
            total: (object["total"] as? NSNumber)?.intValue ?? artists.count,
            source: source,
            page: (object["page"] as? NSNumber)?.intValue ?? normalizedPage,
            limit: (object["limit"] as? NSNumber)?.intValue ?? normalizedLimit,
            hasMore: (object["hasMore"] as? NSNumber)?.boolValue
        )
    }

    public func artistPopularTracks(_ artist: ArtistSummary) async throws -> [Track] {
        try decodeTracks(
            await invokeData("artistPopular", arguments: [artist.source.rawValue, artist.id]),
            source: artist.source,
            failure: "音源返回热门歌曲异常"
        )
    }

    public func artistAlbums(_ artist: ArtistSummary, page: Int = 1) async throws -> AlbumPage {
        let data = try await invokeData("artistAlbums", arguments: [artist.source.rawValue, artist.id, page, 30])
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawList = object["list"] as? [[String: Any]] else {
            throw SourceError.source(message: "音源返回歌手专辑异常")
        }
        let albums = rawList.compactMap { try? decodeAlbum($0, source: artist.source, fallbackArtist: artist.name) }
        if !rawList.isEmpty, albums.isEmpty {
            throw SourceError.source(message: "音源返回歌手专辑异常")
        }
        return AlbumPage(
            list: albums,
            total: (object["total"] as? NSNumber)?.intValue ?? albums.count,
            source: artist.source
        )
    }

    public func albumTracks(_ album: AlbumSummary) async throws -> AlbumDetail {
        let data = try await invokeData("albumTracks", arguments: [album.source.rawValue, album.id])
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawList = object["list"] as? [[String: Any]] else {
            throw SourceError.source(message: "音源返回专辑曲目异常")
        }
        let decodedAlbum = (object["info"] as? [String: Any])
            .flatMap { try? decodeAlbum($0, source: album.source, fallbackArtist: album.artist) }
            ?? album
        let tracks = rawList.compactMap { try? Track(source: album.source, raw: $0) }
        if !rawList.isEmpty, tracks.isEmpty {
            throw SourceError.source(message: "音源返回专辑曲目异常")
        }
        let resolvedAlbum: AlbumSummary
        if (decodedAlbum.trackCount ?? 0) <= 0, !tracks.isEmpty {
            resolvedAlbum = (try? AlbumSummary(
                id: decodedAlbum.id,
                source: decodedAlbum.source,
                name: decodedAlbum.name,
                artist: decodedAlbum.artist,
                imageURL: decodedAlbum.imageURL,
                releaseDate: decodedAlbum.releaseDate,
                trackCount: tracks.count
            )) ?? decodedAlbum
        } else {
            resolvedAlbum = decodedAlbum
        }
        return AlbumDetail(album: resolvedAlbum, tracks: tracks)
    }

    public func trackDetail(_ track: Track) async throws -> Track {
        let data = try await invokeData("musicInfo", arguments: [track.source.rawValue, track.songmid])
        guard let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SourceError.source(message: "音源返回曲目信息异常")
        }
        return try Track(source: track.source, raw: raw)
    }

    private func decodeTracks(_ data: Data, source: MusicSource, failure: String) throws -> [Track] {
        guard let rawList = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw SourceError.source(message: failure)
        }
        let tracks = rawList.compactMap { try? Track(source: source, raw: $0) }
        if !rawList.isEmpty, tracks.isEmpty { throw SourceError.source(message: failure) }
        return tracks
    }

    private func decodeArtist(_ raw: [String: Any], source: MusicSource) throws -> ArtistSummary {
        try ArtistSummary(
            id: stringValue(raw["id"]),
            source: source,
            name: raw["name"] as? String ?? "",
            imageURL: raw["img"] as? String,
            songCount: (raw["songCount"] as? NSNumber)?.intValue,
            albumCount: (raw["albumCount"] as? NSNumber)?.intValue
        )
    }

    private func decodeAlbum(_ raw: [String: Any], source: MusicSource, fallbackArtist: String) throws -> AlbumSummary {
        try AlbumSummary(
            id: stringValue(raw["id"]),
            source: source,
            name: raw["name"] as? String ?? "",
            artist: raw["artist"] as? String ?? fallbackArtist,
            imageURL: raw["img"] as? String,
            releaseDate: raw["releaseDate"] as? String,
            trackCount: (raw["trackCount"] as? NSNumber)?.intValue
        )
    }

    private func stringValue(_ value: Any?) -> String {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return ""
    }

    private func invokeData(_ name: String, arguments: [Any]) async throws -> Data {
        let gate = InvocationContinuationGate()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                gate.install(continuation)
                queue.async {
                    guard self.initializationError == nil,
                          let context = self.context,
                          let source = context.globalObject?.objectForKeyedSubscript("__source__"),
                          let function = source.objectForKeyedSubscript(name), !function.isUndefined else {
                        gate.resume(with: .failure(SourceError.source(message: "音源运行时未初始化")))
                        return
                    }

                    let promise = function.call(withArguments: arguments)
                    if let exception = context.exception {
                        context.exception = nil
                        gate.resume(with: .failure(self.classify(RuntimeFailure.javascript(exception.toString()))))
                        return
                    }

                    let resolve: @convention(block) (JSValue) -> Void = { value in
                        self.queue.async {
                            do {
                                let object = value.toObject() as Any
                                let data = try JSONSerialization.data(withJSONObject: object, options: [.fragmentsAllowed])
                                gate.resume(with: .success(data))
                            } catch {
                                gate.resume(with: .failure(SourceError.source(message: "音源返回数据异常")))
                            }
                        }
                    }
                    let reject: @convention(block) (JSValue) -> Void = { value in
                        self.queue.async {
                            gate.resume(with: .failure(self.classify(RuntimeFailure.javascript(value.toString()))))
                        }
                    }
                    _ = promise?.invokeMethod("then", withArguments: [resolve, reject])
                    if let exception = context.exception {
                        context.exception = nil
                        gate.resume(with: .failure(self.classify(RuntimeFailure.javascript(exception.toString()))))
                    }
                }
            }
        } onCancel: {
            gate.resume(with: .failure(CancellationError()))
        }
    }

    private func classify(_ error: Error) -> SourceError {
        let rawMessage = (error as? RuntimeFailure).map { failure in
            if case let .javascript(text) = failure { return text }
            return String(describing: failure)
        } ?? error.localizedDescription
        let message = Self.sanitizedRuntimeMessage(rawMessage)
        if let marker = message.range(of: "__SONAR_NETWORK__:") {
            let detail = String(message[marker.upperBound...])
            return .network(underlying: NSError(domain: "Sonar.SourceRuntime", code: -1, userInfo: [NSLocalizedDescriptionKey: detail]))
        }
        if message.localizedCaseInsensitiveContains("credential") || message.contains("未配置") || message.contains("需要会员 token") {
            return .credentialRequired(hint: message)
        }
        return .source(message: message)
    }

    private static func sanitizedRuntimeMessage(_ rawMessage: String) -> String {
        let lowercased = rawMessage.lowercased()
        if lowercased.contains("payload=")
            || lowercased.contains("payload:")
            || lowercased.contains("response body")
            || lowercased.contains("raw response") {
            return "音源服务暂时不可用"
        }

        let sensitiveKeys = "apikey|api[_-]?key|token|authorization|cookie|password|secret"
        var message = rawMessage
        message = message.replacingOccurrences(
            of: "(?i)(\\b(?:\(sensitiveKeys))=)[^&\\s]+",
            with: "$1<redacted>",
            options: .regularExpression
        )
        message = message.replacingOccurrences(
            of: "(?i)(\"(?:\(sensitiveKeys))\"\\s*:\\s*\")[^\"]*(\")",
            with: "$1<redacted>$2",
            options: .regularExpression
        )
        message = message.replacingOccurrences(
            of: "(?i)(\\b(?:authorization|cookie)\\s*:\\s*)[^\\r\\n]+",
            with: "$1<redacted>",
            options: .regularExpression
        )
        message = message
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
        guard !message.isEmpty else { return "音源服务暂时不可用" }
        return String(message.prefix(240))
    }

    private func installHostFunctions() {
        guard let context else { return }
        context.exceptionHandler = { [weak self] _, exception in
            let message = exception?.toString() ?? "unknown"
            self?.initializationError = message
            self?.logger.error("JavaScript exception captured")
        }
        let md5: @convention(block) (String) -> String = { input in
            Insecure.MD5.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
        }
        context.setObject(md5, forKeyedSubscript: "__sonar_md5__" as NSString)
        let b64Encode: @convention(block) (String) -> String = { input in
            Data(input.utf8).base64EncodedString()
        }
        context.setObject(b64Encode, forKeyedSubscript: "__sonar_b64_encode__" as NSString)
        let b64Decode: @convention(block) (String) -> String = { input in
            String(data: Data(base64Encoded: input) ?? Data(), encoding: .utf8) ?? ""
        }
        context.setObject(b64Decode, forKeyedSubscript: "__sonar_b64_decode__" as NSString)
        let aesEncrypt: @convention(block) (String, String, String, String) -> String = { data, mode, key, iv in
            (try? CommonCryptoBridge.crypt(base64: data, key: key, iv: iv, mode: mode, encrypt: true)) ?? ""
        }
        context.setObject(aesEncrypt, forKeyedSubscript: "__sonar_aes_encrypt__" as NSString)
        let aesDecrypt: @convention(block) (String, String, String, String) -> String = { data, mode, key, iv in
            (try? CommonCryptoBridge.crypt(base64: data, key: key, iv: iv, mode: mode, encrypt: false)) ?? ""
        }
        context.setObject(aesDecrypt, forKeyedSubscript: "__sonar_aes_decrypt__" as NSString)
        let rsaEncrypt: @convention(block) (String, String, String) -> String = { data, publicKey, padding in
            (try? SecurityBridge.encrypt(base64: data, publicKey: publicKey, padding: padding)) ?? ""
        }
        context.setObject(rsaEncrypt, forKeyedSubscript: "__sonar_rsa_encrypt__" as NSString)
        let httpFetch: @convention(block) (String, String, JSValue, JSValue) -> Void = { [weak self] url, optionsJSON, resolve, reject in
            self?.performHTTP(url: url, optionsJSON: optionsJSON, resolve: resolve, reject: reject)
        }
        context.setObject(httpFetch, forKeyedSubscript: "__sonar_http_fetch__" as NSString)
        let setTimeout: @convention(block) (Double, JSValue) -> Int = { [weak self] delay, callback in
            guard let self else { return -1 }
            let id = self.nextTimerID
            self.nextTimerID += 1
            let item = DispatchWorkItem { [weak self] in
                guard let self, let context = self.context else { return }
                self.timers[id] = nil
                _ = callback.call(withArguments: [])
                context.exception = nil
            }
            self.timers[id] = item
            self.queue.asyncAfter(deadline: .now() + max(delay, 0) / 1000, execute: item)
            return id
        }
        context.setObject(setTimeout, forKeyedSubscript: "__sonar_set_timeout__" as NSString)
        let clearTimeout: @convention(block) (Int) -> Void = { [weak self] id in
            self?.timers[id]?.cancel()
            self?.timers[id] = nil
        }
        context.setObject(clearTimeout, forKeyedSubscript: "__sonar_clear_timeout__" as NSString)
        _ = context.evaluateScript("""
        globalThis.global = globalThis;
        globalThis.process = { versions: { app: '1.0.0-ios' } };
        globalThis.AbortController = class { constructor() { this.signal = { aborted: false }; } abort() { this.signal.aborted = true; } };
        globalThis.fetch = function(url, options = {}) {
          return new Promise((resolve, reject) => __sonar_http_fetch__(String(url), JSON.stringify(options), resolve, reject));
        };
        globalThis.setTimeout = function(fn, delay) { return __sonar_set_timeout__(delay || 0, fn); };
        globalThis.clearTimeout = function(id) { return __sonar_clear_timeout__(id); };
        globalThis.console = { log() {}, info() {}, warn() {}, error() {} };
        """)
    }

    private func performHTTP(url: String, optionsJSON: String, resolve: JSValue, reject: JSValue) {
        guard let requestURL = URL(string: url), var options = (try? JSONSerialization.jsonObject(with: Data(optionsJSON.utf8))) as? [String: Any] else {
            _ = reject.call(withArguments: ["__SONAR_NETWORK__:invalid request"])
            return
        }
        var request = URLRequest(url: requestURL, timeoutInterval: 15)
        request.httpMethod = (options["method"] as? String ?? "GET").uppercased()
        if let headers = options["headers"] as? [String: String] {
            headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        }
        if let body = options["body"] as? String { request.httpBody = Data(body.utf8) }
        if let form = options["form"] as? [String: String] {
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = form.map { "\(Self.urlEncode($0.key))=\(Self.urlEncode($0.value))" }.joined(separator: "&").data(using: .utf8)
        }
        URLSession.shared.dataTask(with: request) { data, response, error in
            self.queue.async {
                if let error {
                    _ = reject.call(withArguments: ["__SONAR_NETWORK__:\(error.localizedDescription)"])
                    return
                }
                let http = response as? HTTPURLResponse
                let result: [String: Any] = [
                    "status": http?.statusCode ?? 0,
                    "statusText": HTTPURLResponse.localizedString(forStatusCode: http?.statusCode ?? 0),
                    "headers": http?.allHeaderFields.reduce(into: [String: String]()) { $0[String(describing: $1.key).lowercased()] = String(describing: $1.value) } ?? [:],
                    "body": String(data: data ?? Data(), encoding: .utf8) ?? "",
                ]
                guard let resultData = try? JSONSerialization.data(withJSONObject: result),
                      let resultJSON = String(data: resultData, encoding: .utf8) else {
                    _ = reject.call(withArguments: ["__SONAR_NETWORK__:response encoding failed"])
                    return
                }
                let script = """
                (() => { const r = \(resultJSON); r.statusCode = r.status; r.statusText = r.statusText; r.ok = r.status >= 200 && r.status < 300; r.headers = { map: r.headers }; r.text = () => Promise.resolve(r.body); r.blob = () => Promise.resolve(r.body); return r; })()
                """
                guard let value = self.context?.evaluateScript(script) else {
                    _ = reject.call(withArguments: ["__SONAR_NETWORK__:response bridge failed"])
                    return
                }
                _ = resolve.call(withArguments: [value])
            }
        }.resume()
        options.removeAll()
    }

    private static func urlEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
