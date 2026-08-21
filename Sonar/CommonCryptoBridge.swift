import CommonCrypto
import Foundation

enum CommonCryptoBridge {
    static func crypt(base64: String, key: String, iv: String, mode: String, encrypt: Bool) throws -> String {
        guard let input = Data(base64Encoded: base64), let keyData = Data(base64Encoded: key), !keyData.isEmpty else { throw CocoaError(.coderInvalidValue) }
        let ivData: Data? = mode == "AES/CBC/PKCS7Padding" ? Data(base64Encoded: iv) : nil
        var options: CCOptions = CCOptions(kCCOptionPKCS7Padding)
        if mode != "AES/CBC/PKCS7Padding" { options |= CCOptions(kCCOptionECBMode) }
        var output = Data(count: input.count + kCCBlockSizeAES128)
        let outputCount = output.count
        var moved = 0
        let status = output.withUnsafeMutableBytes { outputBytes in
            input.withUnsafeBytes { inputBytes in
                keyData.withUnsafeBytes { keyBytes in
                    ivData?.withUnsafeBytes { ivBytes in
                        CCCrypt(encrypt ? CCOperation(kCCEncrypt) : CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), options, keyBytes.baseAddress, keyData.count, ivBytes.baseAddress, inputBytes.baseAddress, input.count, outputBytes.baseAddress, outputCount, &moved)
                    } ?? CCCrypt(encrypt ? CCOperation(kCCEncrypt) : CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), options, keyBytes.baseAddress, keyData.count, nil, inputBytes.baseAddress, input.count, outputBytes.baseAddress, outputCount, &moved)
                }
            }
        }
        guard status == kCCSuccess else { throw NSError(domain: "Sonar.Crypto", code: Int(status)) }
        output.removeSubrange(moved..<output.count)
        if encrypt { return output.base64EncodedString() }
        return output.base64EncodedString()
    }
}
