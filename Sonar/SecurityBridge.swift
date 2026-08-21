import Foundation
import Security

enum SecurityBridge {
    static func encrypt(base64: String, publicKey: String, padding: String) throws -> String {
        guard let input = Data(base64Encoded: base64),
              let keyData = Data(base64Encoded: publicKey, options: .ignoreUnknownCharacters) else {
            throw CocoaError(.coderInvalidValue)
        }
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits: 1024,
        ]
        var creationError: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(keyData as CFData, attributes as CFDictionary, &creationError) else {
            if let error = creationError?.takeRetainedValue() { throw error }
            throw CocoaError(.coderInvalidValue)
        }
        let algorithm: SecKeyAlgorithm = padding == "RSA/ECB/OAEPWithSHA1AndMGF1Padding" ? .rsaEncryptionOAEPSHA1 : .rsaEncryptionRaw
        guard SecKeyIsAlgorithmSupported(key, .encrypt, algorithm) else {
            throw CocoaError(.featureUnsupported)
        }
        var encryptionError: Unmanaged<CFError>?
        guard let encrypted = SecKeyCreateEncryptedData(key, algorithm, input as CFData, &encryptionError) else {
            if let error = encryptionError?.takeRetainedValue() { throw error }
            throw CocoaError(.coderInvalidValue)
        }
        return (encrypted as Data).base64EncodedString()
    }
}
