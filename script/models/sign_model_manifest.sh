#!/usr/bin/env bash
set -euo pipefail

: "${TEXTIFY_MODEL_MANIFEST_KEY_ID:?key id required}"

keychain_service="${TEXTIFY_MODEL_MANIFEST_KEYCHAIN_SERVICE:-io.github.Player0109.Textify.model-manifest-signing}"
private_key="${TEXTIFY_MODEL_MANIFEST_PRIVATE_KEY_BASE64:-}"
if [[ -z "$private_key" ]]; then
  private_key="$(security find-generic-password \
    -a "$TEXTIFY_MODEL_MANIFEST_KEY_ID" \
    -s "$keychain_service" \
    -w 2>/dev/null)" || {
      echo "error: no manifest private key in the environment or macOS Keychain" >&2
      exit 1
    }
fi
export TEXTIFY_MODEL_MANIFEST_PRIVATE_KEY_BASE64="$private_key"
unset private_key

usage() {
  cat >&2 <<'USAGE'
Usage: script/models/sign_model_manifest.sh [manifest.json] [manifest.json.sig]

Signs the canonical model-manifest envelope with the local Ed25519 private
key. The key is read from TEXTIFY_MODEL_MANIFEST_PRIVATE_KEY_BASE64 when set,
or from the macOS Keychain account matching TEXTIFY_MODEL_MANIFEST_KEY_ID.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

manifest_path="${1:-manifest.json}"
signature_path="${2:-${manifest_path}.sig}"

if [[ ! -f "$manifest_path" ]]; then
  echo "error: manifest not found: $manifest_path" >&2
  exit 1
fi

mkdir -p "$(dirname "$signature_path")"

swift - "$manifest_path" "$signature_path" <<'SWIFT'
import CryptoKit
import Foundation

struct SignatureEnvelope: Encodable {
    let signatureVersion: Int
    let signatureType: String
    let algorithm: String
    let keyId: String
    let manifestFile: String
    let contentType: String
    let contentSHA256: String
    let signature: String
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

let args = Array(CommandLine.arguments.dropFirst())
guard args.count == 2 else {
    fail("expected manifest path and signature path")
}

let environment = ProcessInfo.processInfo.environment
guard let privateKeyBase64 = environment["TEXTIFY_MODEL_MANIFEST_PRIVATE_KEY_BASE64"],
      let privateKeyData = Data(base64Encoded: privateKeyBase64) else {
    fail("TEXTIFY_MODEL_MANIFEST_PRIVATE_KEY_BASE64 is not valid base64")
}
guard let keyID = environment["TEXTIFY_MODEL_MANIFEST_KEY_ID"],
      !keyID.isEmpty else {
    fail("TEXTIFY_MODEL_MANIFEST_KEY_ID is empty")
}

let manifestURL = URL(fileURLWithPath: args[0])
let signatureURL = URL(fileURLWithPath: args[1])
let signatureType = "io.github.Player0109.Textify.model-manifest"
let algorithm = "Ed25519"
let manifestFile = "manifest.json"

do {
    let manifestData = try Data(contentsOf: manifestURL)
    guard let manifestObject = try JSONSerialization.jsonObject(with: manifestData)
        as? [String: Any],
          let manifestVersion = manifestObject["manifestVersion"] as? Int,
          manifestVersion == 1 || manifestVersion == 2 else {
        fail("manifestVersion must be 1 or 2")
    }
    let contentType = "application/vnd.textify.model-manifest+json;version=\(manifestVersion)"
    let contentSHA256 = SHA256.hash(data: manifestData)
        .map { String(format: "%02x", $0) }
        .joined()
    let canonicalPayload = Data("""
    TEXTIFY-MODEL-MANIFEST-SIGNATURE-V1
    signatureVersion=1
    signatureType=\(signatureType)
    algorithm=\(algorithm)
    keyId=\(keyID)
    manifestFile=\(manifestFile)
    contentType=\(contentType)
    contentSHA256=\(contentSHA256)

    """.utf8)
    let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: privateKeyData)
    let signature = try privateKey.signature(for: canonicalPayload)
        .base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
    let envelope = SignatureEnvelope(
        signatureVersion: 1,
        signatureType: signatureType,
        algorithm: algorithm,
        keyId: keyID,
        manifestFile: manifestFile,
        contentType: contentType,
        contentSHA256: contentSHA256,
        signature: signature
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    var output = try encoder.encode(envelope)
    output.append(0x0a)
    try output.write(to: signatureURL, options: .atomic)
} catch {
    fail(String(describing: error))
}
SWIFT

echo "Wrote $signature_path"
unset TEXTIFY_MODEL_MANIFEST_PRIVATE_KEY_BASE64
