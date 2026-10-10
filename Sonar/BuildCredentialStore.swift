import Foundation

/// Reads playback parsing credentials from the local build resource first,
/// then falls back to Keychain for existing installations.
public struct BuildCredentialStore: CredentialStore {
    public let chkszKey: String?

    public init(bundle: Bundle = .main, fallback: CredentialStore = KeychainCredentialStore()) {
        self.init(
            resourceURL: bundle.url(forResource: "BuildCredentials", withExtension: "json"),
            fallback: fallback
        )
    }

    init(resourceURL: URL?, fallback: CredentialStore) {
        let bundled = Self.read(resourceURL: resourceURL)
        self.chkszKey = bundled ?? fallback.chkszKey
    }

    private static func read(resourceURL: URL?) -> String? {
        guard let resourceURL,
              let data = try? Data(contentsOf: resourceURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return nil
        }
        func value(_ key: String) -> String? {
            let value = object[key]?.trimmingCharacters(in: .whitespacesAndNewlines)
            return value?.isEmpty == false ? value : nil
        }
        return value("chkszKey")
    }
}
