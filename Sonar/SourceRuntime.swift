import CryptoKit
import Foundation
import JavaScriptCore
import os

private enum RuntimeFailure: Error {
    case javascript(String)
}

public final class JavaScriptSourceRuntime: SourceRuntime, @unchecked Sendable {
    private let queue = DispatchQueue(label: "cn.bobochang.sonar.source-runtime")
    private let logger = Logger(subsystem: "cn.bobochang.sonar", category: "SourceRuntime")
    private var context: JSContext?
    private var initializationError: String?
    private var nextTimerID: Int = 0
    private var timers: [Int: DispatchWorkItem] = [:]

    public init(bundleURL: URL? = Bundle.main.url(forResource: "source-bundle", withExtension: "js")) {
        queue.sync {
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
            let exception = context?.exception?.toString() ?? initializationError ?? "none"
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

    private func invokeData(_ name: String, arguments: [Any]) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard self.initializationError == nil,
                      let context = self.context,
                      let source = context.globalObject?.objectForKeyedSubscript("__source__"),
                      let function = source.objectForKeyedSubscript(name), !function.isUndefined else {
                    continuation.resume(throwing: SourceError.source(message: "音源运行时未初始化\(self.initializationError.map { ": \($0)" } ?? "")"))
                    return
                }

                let promise = function.call(withArguments: arguments)
                if let exception = context.exception {
                    context.exception = nil
                    continuation.resume(throwing: self.classify(RuntimeFailure.javascript(exception.toString())))
                    return
                }

                let resolve: @convention(block) (JSValue) -> Void = { value in
                    self.queue.async {
                        do {
                            let object = value.toObject() as Any
                            let data = try JSONSerialization.data(withJSONObject: object, options: [.fragmentsAllowed])
                            continuation.resume(returning: data)
                        } catch {
                            continuation.resume(throwing: SourceError.source(message: "音源返回数据异常: \(error.localizedDescription)"))
                        }
                    }
                }
                let reject: @convention(block) (JSValue) -> Void = { value in
                    self.queue.async {
                        continuation.resume(throwing: self.classify(RuntimeFailure.javascript(value.toString())))
                    }
                }
                _ = promise?.invokeMethod("then", withArguments: [resolve, reject])
                if let exception = context.exception {
                    context.exception = nil
                    continuation.resume(throwing: self.classify(RuntimeFailure.javascript(exception.toString())))
                }
            }
        }
    }

    private func classify(_ error: Error) -> SourceError {
        let message = (error as? RuntimeFailure).map { failure in
            if case let .javascript(text) = failure { return text }
            return String(describing: failure)
        } ?? error.localizedDescription
        if let marker = message.range(of: "__SONAR_NETWORK__:") {
            let detail = String(message[marker.upperBound...])
            return .network(underlying: NSError(domain: "Sonar.SourceRuntime", code: -1, userInfo: [NSLocalizedDescriptionKey: detail]))
        }
        if message.localizedCaseInsensitiveContains("credential") || message.contains("未配置") || message.contains("需要会员 token") {
            return .credentialRequired(hint: message)
        }
        return .source(message: message)
    }

    private func installHostFunctions() {
        guard let context else { return }
        context.exceptionHandler = { [weak self] _, exception in
            let message = exception?.toString() ?? "unknown"
            self?.initializationError = message
            self?.logger.error("JavaScript exception: \(message)")
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
