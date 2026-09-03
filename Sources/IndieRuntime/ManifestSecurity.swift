import CryptoKit
import Foundation
import IndieCore

public enum ManifestSecurity {
    public static func canonicalPayload(for manifest: RuntimeManifest) throws -> Data {
        let unsigned = RuntimeManifest(
            schemaVersion: manifest.schemaVersion,
            id: manifest.id,
            displayName: manifest.displayName,
            version: manifest.version,
            channel: manifest.channel,
            hostArchitecture: manifest.hostArchitecture,
            minimumMacOS: manifest.minimumMacOS,
            capabilities: manifest.capabilities,
            artifacts: manifest.artifacts,
            licenses: manifest.licenses,
            publishedAt: manifest.publishedAt,
            signature: nil
        )
        return try IndieJSON.encoder().encode(unsigned)
    }

    public static func verify(_ manifest: RuntimeManifest, publicKeyBase64: String) throws {
        guard manifest.schemaVersion == 1 else { throw IndieError.invalidData("不支持的运行时清单版本") }
        guard let signatureText = manifest.signature,
              let signature = Data(base64Encoded: signatureText),
              let keyData = Data(base64Encoded: publicKeyBase64) else {
            throw IndieError.securityViolation("运行时清单缺少有效签名")
        }
        let key = try Curve25519.Signing.PublicKey(rawRepresentation: keyData)
        guard key.isValidSignature(signature, for: try canonicalPayload(for: manifest)) else {
            throw IndieError.securityViolation("运行时清单签名验证失败")
        }
    }

    public static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while autoreleasepool(invoking: {
            let data = try? handle.read(upToCount: 1_048_576)
            guard let data, !data.isEmpty else { return false }
            hash.update(data: data)
            return true
        }) {}
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
