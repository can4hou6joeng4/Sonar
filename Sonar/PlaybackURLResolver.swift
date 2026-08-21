import CryptoKit
import Foundation
import Security

public protocol CredentialStore: Sendable {
    var wyToken: String? { get }
    var chkszKey: String? { get }
}

public struct InMemoryCredentialStore: CredentialStore {
    public let wyToken: String?
    public let chkszKey: String?

    public init(wyToken: String? = nil, chkszKey: String? = nil) {
        self.wyToken = wyToken
        self.chkszKey = chkszKey
    }
}

public struct KeychainCredentialStore: CredentialStore {
    public let service: String

    public init(service: String = "cn.bobochang.sonar.credentials") {
        self.service = service
    }

    public var wyToken: String? { read(key: "wyToken") }
    public var chkszKey: String? { read(key: "chkszKey") }

    public func setWyToken(_ value: String?) throws { try write(value, key: "wyToken") }
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
    public init() {}

    public func send(_ request: URLRequest) async throws -> PlaybackHTTPResponse {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
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

public protocol PlaybackURLResolving: Sendable {
    func musicURL(for track: Track, quality: Quality) async throws -> URL
}

public actor ChkszCircuitBreaker {
    private(set) var disabled = false
    private(set) var reason: String?

    public init() {}

    public func disable(reason: String) {
        disabled = true
        self.reason = reason
    }
}

public final class PlaybackURLResolver: PlaybackURLResolving, @unchecked Sendable {
    private let client: PlaybackHTTPClient
    private let credentials: CredentialStore
    private let breaker: ChkszCircuitBreaker
    private let cache: PlaybackURLCache

    public init(client: PlaybackHTTPClient = URLSessionPlaybackHTTPClient(), credentials: CredentialStore = KeychainCredentialStore(), breaker: ChkszCircuitBreaker = ChkszCircuitBreaker(), cache: PlaybackURLCache = PlaybackURLCache()) {
        self.client = client
        self.credentials = credentials
        self.breaker = breaker
        self.cache = cache
    }

    public func musicURL(for track: Track, quality: Quality) async throws -> URL {
        let key = PlaybackURLCache.Key(track: track, quality: quality)
        if let cached = await cache.value(for: key) { return cached }
        let result: (URL, Quality)
        switch track.source {
        case .wy:
            result = try await resolveWY(track: track, quality: quality)
        case .tx:
            result = try await resolveTX(track: track, quality: quality)
        }
        await cache.insert(result.0, actualQuality: result.1, for: key)
        return result.0
    }

    private func resolveWY(track: Track, quality: Quality) async throws -> (URL, Quality) {
        guard quality != .hiRes else {
            throw SourceError.source(message: "网易云不支持 Hi-Res 音质")
        }
        let path = "/api/song/enhance/player/url"
        let bitrate: Int
        switch quality {
        case .standard: bitrate = 128_000
        case .high: bitrate = 320_000
        case .lossless: bitrate = 999_000
        case .hiRes: bitrate = 999_000
        }
        let text = "{\"ids\":\"[\(track.songmid)]\",\"br\":\(bitrate)}"
        let digest = Self.md5("nobody\(path)use\(text)md5forencrypt")
        let payload = "\(path)-36cd479b6b5-\(text)-36cd479b6b5-\(digest)"
        let key = Data("e82ckenh8dichen8".utf8).base64EncodedString()
        let encrypted = try CommonCryptoBridge.crypt(base64: Data(payload.utf8).base64EncodedString(), key: key, iv: "", mode: "AES", encrypt: true)
        guard let encryptedData = Data(base64Encoded: encrypted) else {
            throw SourceError.source(message: "网易云: 加密请求失败")
        }
        var request = URLRequest(url: URL(string: "https://interface3.music.163.com/eapi\(path)")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("os=pc\(credentials.wyToken.map { "; MUSIC_U=\($0)" } ?? "")", forHTTPHeaderField: "Cookie")
        request.httpBody = Data("params=\(encryptedData.map { String(format: "%02X", $0) }.joined())".utf8)
        let response = try await client.send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw SourceError.source(message: "网易云: HTTP \(response.statusCode)")
        }
        let object = try Self.jsonObject(response.body)
        guard let item = (object["data"] as? [[String: Any]])?.first else {
            throw SourceError.source(message: "网易云: 返回数据异常")
        }
        if item["freeTrialInfo"] is [String: Any] || item["freeTrialInfo"] is [Any] {
            throw SourceError.source(message: "仅返回试听片段")
        }
        guard let rawURL = item["url"] as? String, let url = URL(string: rawURL), Self.isHTTP(url) else {
            if credentials.wyToken == nil {
                throw SourceError.credentialRequired(hint: "需要会员 token")
            }
            throw SourceError.source(message: "无版权，或该音质需要更高等级会员")
        }
        if quality == .lossless {
            let type = (item["type"] as? String ?? "").lowercased()
            if type != "flac" {
                throw SourceError.source(message: "该歌曲无法获取无损（实际返回 \(type.isEmpty ? "未知" : type)），请改用 320k")
            }
        }
        let actualQuality: Quality = switch (item["type"] as? String ?? "").lowercased() {
        case "flac": .lossless
        default:
            if let actualBitrate = (item["br"] as? NSNumber)?.intValue, actualBitrate >= 320_000 {
                .high
            } else {
                .standard
            }
        }
        return (url, actualQuality)
    }

    private func resolveTX(track: Track, quality: Quality) async throws -> (URL, Quality) {
        var errors: [SourceError] = []
        if let key = credentials.chkszKey {
            if await breaker.disabled {
                let reason = await breaker.reason ?? "未知原因"
                errors.append(.source(message: "ChKSz 已停用（\(reason)）"))
            } else {
                do {
                    return (try await resolveTXChksz(track: track, quality: quality, key: key), quality)
                } catch let error as SourceError {
                    errors.append(error)
                }
            }
        }
        do {
            return (try await resolveTXGuest(track: track, quality: quality), quality == .hiRes ? .lossless : quality)
        } catch let error as SourceError {
            errors.append(error)
            if credentials.chkszKey == nil {
                if case let .source(message) = error, Self.isEntitlementFailure(message) {
                    throw SourceError.credentialRequired(hint: "未配置 ChKSz Key，VIP 或高音质歌曲需要凭证")
                }
                if case .credentialRequired = error {
                    throw error
                }
            }
        }
        if let credential = errors.first(where: {
            if case .credentialRequired = $0 { return true }
            return false
        }) { throw credential }
        if errors.allSatisfy({
            if case .network = $0 { return true }
            return false
        }), let network = errors.first {
            throw network
        }
        throw SourceError.source(message: errors.map { $0.localizedDescription }.joined(separator: "；"))
    }

    private func resolveTXChksz(track: Track, quality: Quality, key: String) async throws -> URL {
        let size: String
        switch quality {
        case .standard: size = "128k"
        case .high: size = "320k"
        case .lossless: size = "flac"
        case .hiRes: size = "hires"
        }
        var components = URLComponents(string: "https://api.chksz.com/api/qq_music")!
        components.queryItems = [
            URLQueryItem(name: "mid", value: track.songmid),
            URLQueryItem(name: "size", value: size),
            URLQueryItem(name: "type", value: "json"),
            URLQueryItem(name: "apikey", value: key),
        ]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        var response = try await client.send(request)
        if response.statusCode == 429 {
            let retry = Double(response.headers["retry-after"] ?? "5") ?? 5
            if retry <= 10 {
                try await Task.sleep(for: .seconds(max(0, retry)))
                response = try await client.send(request)
            }
        }
        if [401, 403].contains(response.statusCode) {
            await breaker.disable(reason: "HTTP \(response.statusCode)")
            throw SourceError.source(message: "ChKSz 凭证无效或已过期（HTTP \(response.statusCode)）")
        }
        if response.statusCode == 402 {
            await breaker.disable(reason: "HTTP 402")
            throw SourceError.source(message: "ChKSz 额度已耗尽（HTTP 402）")
        }
        guard response.statusCode == 200 else {
            throw SourceError.source(message: "ChKSz: HTTP \(response.statusCode)")
        }
        let object = try Self.jsonObject(response.body)
        if let code = (object["code"] as? NSNumber)?.intValue, code != 200 {
            throw SourceError.source(message: (object["msg"] as? String) ?? "ChKSz 返回异常")
        }
        guard let rawURL = object["url"] as? String, let url = URL(string: rawURL), Self.isHTTP(url) else {
            throw SourceError.source(message: "未返回可用链接")
        }
        return url
    }

    private func resolveTXGuest(track: Track, quality: Quality) async throws -> URL {
        guard let mediaMid = track.rawPayload["strMediaMid"] as? String, !mediaMid.isEmpty else {
            throw SourceError.source(message: "QQ: 缺少 strMediaMid")
        }
        let prefix: String
        let suffix: String
        switch quality {
        case .standard: prefix = "M500"; suffix = ".mp3"
        case .high: prefix = "M800"; suffix = ".mp3"
        case .lossless, .hiRes: prefix = "F000"; suffix = ".flac"
        }
        let filename = "\(prefix)\(mediaMid)\(suffix)"
        let payload: [String: Any] = [
            "req_0": ["module": "vkey.GetVkeyServer", "method": "CgiGetVkey", "param": ["filename": [filename], "guid": "10000", "songmid": [track.songmid], "songtype": [0], "uin": "0", "loginflag": 1, "platform": "20"]],
            "loginUin": "0",
            "comm": ["uin": "0", "format": "json", "ct": 24, "cv": 0],
        ]
        var request = URLRequest(url: URL(string: "https://u.y.qq.com/cgi-bin/musicu.fcg?format=json&data=\(Self.urlEncodeJSON(payload))")!)
        request.httpMethod = "GET"
        request.setValue("0146951", forHTTPHeaderField: "channel")
        request.setValue("1234", forHTTPHeaderField: "uid")
        let response = try await client.send(request)
        guard response.statusCode == 200 else { throw SourceError.source(message: "QQ 游客直连: HTTP \(response.statusCode)") }
        let object = try Self.jsonObject(response.body)
        guard let data = object["req_0"] as? [String: Any] ?? object["data"] as? [String: Any] else {
            throw SourceError.source(message: "QQ: 缺少响应数据")
        }
        let nested = (data["data"] as? [String: Any]) ?? data
        let sip = (nested["sip"] as? [String])?.first ?? (nested["sip"] as? [Any])?.first as? String
        guard let sip, !sip.isEmpty else { throw SourceError.source(message: "缺少服务器地址") }
        guard let purl = (nested["midurlinfo"] as? [[String: Any]])?.first?["purl"] as? String, !purl.isEmpty else {
            throw SourceError.source(message: "无版权或需要会员")
        }
        guard let url = URL(string: sip + purl), Self.isHTTP(url) else { throw SourceError.source(message: "QQ: 未返回可用链接") }
        return url
    }

    private static func md5(_ value: String) -> String {
        Insecure.MD5.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func jsonObject(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SourceError.source(message: "音源返回 JSON 异常")
        }
        return object
    }

    private static func isHTTP(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased())
    }

    private static func isEntitlementFailure(_ message: String) -> Bool {
        message.contains("版权") || message.contains("会员") || message.localizedCaseInsensitiveContains("vip")
    }

    private static func urlEncodeJSON(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object), let text = String(data: data, encoding: .utf8) else { return "{}" }
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    }
}
