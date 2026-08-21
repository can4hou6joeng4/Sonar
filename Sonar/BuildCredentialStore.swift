import Foundation

/// Reads optional high-quality credentials from the local build resource first,
/// then falls back to Keychain for existing installations.
public struct BuildCredentialStore: CredentialStore {
    public let wyToken: String?
    public let chkszKey: String?

    public init(bundle: Bundle = .main, fallback: CredentialStore = KeychainCredentialStore()) {
        self.init(
            resourceURL: bundle.url(forResource: "BuildCredentials", withExtension: "json"),
            fallback: fallback
        )
    }

    init(resourceURL: URL?, fallback: CredentialStore) {
        let bundled = Self.read(resourceURL: resourceURL)
        self.wyToken = bundled.wyToken ?? fallback.wyToken
        self.chkszKey = bundled.chkszKey ?? fallback.chkszKey
    }

    private static func read(resourceURL: URL?) -> (wyToken: String?, chkszKey: String?) {
        guard let resourceURL,
              let data = try? Data(contentsOf: resourceURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return (nil, nil)
        }
        func value(_ key: String) -> String? {
            let value = object[key]?.trimmingCharacters(in: .whitespacesAndNewlines)
            return value?.isEmpty == false ? value : nil
        }
        return (value("wyToken"), value("chkszKey"))
    }
}
