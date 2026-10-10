import Foundation
import Security

public protocol CredentialStore: Sendable {
    var chkszKey: String? { get }
}

public struct InMemoryCredentialStore: CredentialStore {
    public let chkszKey: String?

    public init(chkszKey: String? = nil) {
        self.chkszKey = chkszKey
    }
}

public struct KeychainCredentialStore: CredentialStore {
    public let service: String

    public init(service: String = "cn.bobochang.sonar.credentials") {
        self.service = service
    }

    public var chkszKey: String? { read(key: "chkszKey") }

    public func setChkszKey(_ value: String?) throws { try write(value, key: "chkszKey") }

    private func write(_ value: String?, key: String) throws {
        let base: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
        ]
        SecItemDelete(base as CFDictionary)
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return }
        var query = base
        query[kSecValueData] = Data(trimmed.utf8)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    private func read(key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

public protocol PlaybackHTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> PlaybackHTTPResponse
    func probe(_ request: URLRequest, maxBytes: Int, timeout: TimeInterval) async throws -> PlaybackHTTPResponse
}

public extension PlaybackHTTPClient {
    /// Compatibility for injected clients that already return an in-memory response.
    /// Network transports must override this to bound consumption before EOF.
    func probe(_ request: URLRequest, maxBytes: Int, timeout: TimeInterval) async throws -> PlaybackHTTPResponse {
        try Task.checkCancellation()
        let response = try await send(request)
        try Task.checkCancellation()
        return PlaybackHTTPResponse(
            statusCode: response.statusCode, headers: response.headers,
            body: Data(response.body.prefix(max(1, maxBytes)))
        )
    }
}

public struct PlaybackHTTPResponse: Sendable {
    public let statusCode: Int
    public let headers: [String: String]
    public let body: Data

    public init(statusCode: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }
}

public struct URLSessionPlaybackHTTPClient: PlaybackHTTPClient {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func probe(
        _ request: URLRequest, maxBytes: Int = 64, timeout: TimeInterval = 8
    ) async throws -> PlaybackHTTPResponse {
        let probe = PlaybackMediaPrefixProbe(maxBytes: maxBytes)
        do {
            let result = try await withTaskCancellationHandler {
                try Task.checkCancellation()
                return try await withCheckedThrowingContinuation { continuation in
                    probe.start(request, configuration: session.configuration, timeout: timeout, continuation: continuation)
                }
            } onCancel: {
                probe.cancel()
            }
            try Task.checkCancellation()
            return result
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw SourceError.network(underlying: error)
        }
    }

    public func send(_ request: URLRequest) async throws -> PlaybackHTTPResponse {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            let headers = http.allHeaderFields.reduce(into: [String: String]()) {
                $0[String(describing: $1.key).lowercased()] = String(describing: $1.value)
            }
            return PlaybackHTTPResponse(statusCode: http.statusCode, headers: headers, body: data)
        } catch let error as SourceError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled && Task.isCancelled {
            throw CancellationError()
        } catch {
            throw SourceError.network(underlying: error)
        }
    }
}

/// The delegate never retains more than the requested prefix. Reaching that prefix is
/// success, so the cancellation used to stop a long response must not escape as an error.
private final class PlaybackMediaPrefixProbe: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let maxBytes: Int
    private let lock = NSLock()
    private var completed = false
    private var continuation: CheckedContinuation<PlaybackHTTPResponse, Error>?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var deadline: DispatchWorkItem?
    private var response: HTTPURLResponse?
    private var body = Data()

    init(maxBytes: Int) {
        self.maxBytes = max(1, maxBytes)
    }

    func start(
        _ request: URLRequest,
        configuration: URLSessionConfiguration,
        timeout: TimeInterval,
        continuation: CheckedContinuation<PlaybackHTTPResponse, Error>
    ) {
        lock.lock()
        guard !completed else {
            lock.unlock()
            continuation.resume(throwing: CancellationError())
            return
        }
        self.continuation = continuation
        let boundedTimeout = timeout.isFinite ? min(max(timeout, 0.01), 30) : 8
        var request = request
        request.timeoutInterval = boundedTimeout
        // A media prefix is deliberately incomplete and must not enter the URL cache.
        request.cachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.timeoutIntervalForResource = boundedTimeout
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        let task = session.dataTask(with: request)
        let deadline = DispatchWorkItem { [weak self] in
            self?.finish(.failure(URLError(.timedOut)))
        }
        self.session = session
        self.task = task
        self.deadline = deadline
        lock.unlock()
        DispatchQueue.global().asyncAfter(deadline: .now() + boundedTimeout, execute: deadline)
        task.resume()
    }

    func cancel() {
        finish(.failure(CancellationError()))
    }

    private func finish(_ result: Result<PlaybackHTTPResponse, Error>) {
        lock.lock()
        guard !completed else { lock.unlock(); return }
        completed = true
        let continuation = self.continuation
        let session = self.session
        let task = self.task
        let deadline = self.deadline
        self.continuation = nil
        self.session = nil
        self.task = nil
        self.deadline = nil
        lock.unlock()
        deadline?.cancel()
        task?.cancel()
        session?.invalidateAndCancel()
        continuation?.resume(with: result)
    }

    private func makeResponse(_ response: HTTPURLResponse) -> PlaybackHTTPResponse {
        let headers = response.allHeaderFields.reduce(into: [String: String]()) {
            $0[String(describing: $1.key).lowercased()] = String(describing: $1.value)
        }
        return PlaybackHTTPResponse(statusCode: response.statusCode, headers: headers, body: body)
    }

    func urlSession(
        _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let http = response as? HTTPURLResponse else {
            finish(.failure(URLError(.badServerResponse)))
            completionHandler(.cancel)
            return
        }
        lock.lock()
        guard !completed else { lock.unlock(); completionHandler(.cancel); return }
        self.response = http
        let rejected = ![200, 206].contains(http.statusCode)
        let result = makeResponse(http)
        lock.unlock()
        if rejected {
            finish(.success(result))
            completionHandler(.cancel)
        } else {
            completionHandler(.allow)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        guard !completed, let response else { lock.unlock(); return }
        body.append(contentsOf: data.prefix(maxBytes - body.count))
        let result = body.count == maxBytes ? makeResponse(response) : nil
        lock.unlock()
        if let result { finish(.success(result)) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        guard !completed else { lock.unlock(); return }
        let result: Result<PlaybackHTTPResponse, Error>
        if let error {
            result = .failure(error)
        } else if let response {
            result = .success(makeResponse(response))
        } else {
            result = .failure(URLError(.badServerResponse))
        }
        lock.unlock()
        finish(result)
    }
}

public protocol PlaybackURLResolving: Sendable {
    func musicURL(for track: Track, quality: Quality) async throws -> URL
}

public protocol PlaybackURLRefreshing: PlaybackURLResolving {
    func refreshMusicURL(for track: Track, quality: Quality) async throws -> URL
}

public actor ChkszCircuitBreaker {
    private(set) var disabled = false
    private(set) var reason: String?
    private var rateLimitedUntil: Date?

    public init() {}

    public func disable(reason: String) {
        disabled = true
        self.reason = reason
    }

    public func deferAfterRateLimit(seconds: TimeInterval) {
        let boundedDelay = min(max(seconds, 1), 60)
        let proposedDeadline = Date().addingTimeInterval(boundedDelay)
        rateLimitedUntil = max(rateLimitedUntil ?? proposedDeadline, proposedDeadline)
    }

    public func blockedMessage() -> String? {
        if disabled {
            return "ChKSz 已停用（\(reason ?? "未知原因")）"
        }
        guard let rateLimitedUntil else { return nil }
        guard rateLimitedUntil > Date() else {
            self.rateLimitedUntil = nil
            return nil
        }
        return "ChKSz 限流冷却中（HTTP 429）"
    }
}

public final class PlaybackURLResolver: PlaybackURLRefreshing, @unchecked Sendable {
    private let client: PlaybackHTTPClient
    private let chkszAPI: ChkszAPIRequesting
    private let netease: ChkszNetEaseProviding
    private let cache: PlaybackURLCache

    public init(
        client: PlaybackHTTPClient = URLSessionPlaybackHTTPClient(),
        credentials: CredentialStore = KeychainCredentialStore(),
        breaker: ChkszCircuitBreaker = ChkszCircuitBreaker(),
        cache: PlaybackURLCache = PlaybackURLCache(),
        chkszAPI: ChkszAPIRequesting? = nil,
        netease: ChkszNetEaseProviding? = nil
    ) {
        self.client = client
        let api = chkszAPI ?? ChkszAPIClient(client: client, credentials: credentials, breaker: breaker)
        self.chkszAPI = api
        self.netease = netease ?? ChkszNetEaseClient(api: api)
        self.cache = cache
    }

    public func musicURL(for track: Track, quality: Quality) async throws -> URL {
        try track.source.requireEnabled()
        let key = PlaybackURLCache.Key(track: track, quality: quality)
        if let cached = await cache.value(for: key) { return cached }
        return try await resolveAndCache(track: track, quality: quality, key: key)
    }

    public func refreshMusicURL(for track: Track, quality: Quality) async throws -> URL {
        try track.source.requireEnabled()
        let key = PlaybackURLCache.Key(track: track, quality: quality)
        await cache.removeValue(for: key)
        return try await resolveAndCache(track: track, quality: quality, key: key)
    }

    private func resolveAndCache(track: Track, quality: Quality, key: PlaybackURLCache.Key) async throws -> URL {
        let result: ChkszPlaybackResult
        switch track.source {
        case .tx:
            result = try await resolveTXChksz(track: track, quality: quality)
        case .wy:
            result = try await netease.musicURL(for: track, quality: quality)
        }
        guard let mediaURL = Self.mediaURL(from: result.url.absoluteString) else {
            throw SourceError.source(message: "播放解析未返回可用链接")
        }
        try await validateChkszMediaURL(mediaURL)
        await cache.insert(mediaURL, actualQuality: result.actualQuality, for: key)
        guard result.actualQuality.rank >= quality.rank else {
            throw SourceError.source(message: "该音质不可用，实际返回 \(result.actualQuality.rawValue)")
        }
        return mediaURL
    }

    private func resolveTXChksz(track: Track, quality: Quality) async throws -> ChkszPlaybackResult {
        let size: String
        switch quality {
        case .standard: size = "128k"
        case .high: size = "320k"
        case .lossless: size = "flac"
        case .hiRes: size = "hires"
        case .master: size = "master"
        }
        let data = try await chkszAPI.request(
            path: "/api/qq_music",
            parameters: [
                "mid": track.songmid,
                "size": size,
                "type": "json",
            ]
        )
        let object = try Self.jsonObject(data)
        guard let rawURL = object["url"] as? String, let url = Self.mediaURL(from: rawURL) else {
            throw SourceError.source(message: "未返回可用链接")
        }
        return ChkszPlaybackResult(url: url, actualQuality: Self.qqQuality(from: object))
    }

    /// The requested size is a preference, not proof of the returned audio quality.
    private static func qqQuality(from object: [String: Any]) -> Quality {
        if let value = object["bitrate"] as? String {
            switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "master": return .master
            case "hires", "flac24bit", "hi-res": return .hiRes
            case "flac", "lossless": return .lossless
            case "320k": return .high
            case "128k": return .standard
            default: break
            }
        }
        let bitrate = (object["bitrate"] as? NSNumber)?.intValue
            ?? (object["bitrate"] as? String).flatMap(Int.init)
        if let bitrate {
            if bitrate >= 1_500_000 { return .hiRes }
            if bitrate >= 700_000 { return .lossless }
            if bitrate >= 300_000 { return .high }
            return .standard
        }
        if (object["format"] as? String)?.lowercased() == "flac" { return .lossless }
        return .standard
    }

    private func validateChkszMediaURL(_ url: URL) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("bytes=0-1", forHTTPHeaderField: "Range")
        let response = try await client.probe(request, maxBytes: 64, timeout: 8)
        guard [200, 206].contains(response.statusCode) else {
            throw SourceError.source(message: "ChKSz 播放链接失效（HTTP \(response.statusCode)）")
        }
        guard !response.body.isEmpty, Self.looksLikeMedia(response) else {
            throw SourceError.source(message: "ChKSz 播放链接返回了非媒体内容")
        }
    }

    private static func jsonObject(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SourceError.source(message: "音源返回 JSON 异常")
        }
        return object
    }

    private static func mediaURL(from value: String) -> URL? {
        guard var components = URLComponents(string: value),
              components.host?.isEmpty == false,
              components.user == nil, components.password == nil,
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else { return nil }
        // QQ still returns HTTP media URLs; AVPlayer requires HTTPS under ATS.
        components.scheme = "https"
        return components.url
    }

    private static func looksLikeMedia(_ response: PlaybackHTTPResponse) -> Bool {
        let contentType = response.headers.first {
            $0.key.caseInsensitiveCompare("content-type") == .orderedSame
        }?.value.lowercased() ?? ""
        if contentType.hasPrefix("audio/") || contentType == "application/octet-stream" {
            return true
        }
        if contentType.hasPrefix("text/")
            || contentType.contains("html")
            || contentType.contains("json")
            || contentType.contains("xml") {
            return false
        }

        let prefix = String(decoding: response.body.prefix(64), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return !prefix.hasPrefix("<")
            && !prefix.hasPrefix("{")
            && !prefix.hasPrefix("[")
            && !prefix.hasPrefix("error")
    }

}
