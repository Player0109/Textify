#!/usr/bin/env bash
set -euo pipefail

: "${TEXTIFY_MODEL_MANIFEST_PRIVATE_KEY_BASE64:?local private key required}"
: "${TEXTIFY_MODEL_MANIFEST_KEY_ID:?key id required}"

usage() {
  cat >&2 <<'USAGE'
Usage: script/models/sign_model_manifest.sh [manifest.json] [manifest.json.sig]

Signs the exact manifest JSON bytes with the local Textify model-manifest
Ed25519 private key. TEXTIFY_MODEL_MANIFEST_PRIVATE_KEY_BASE64 must be the
base64-encoded CryptoKit raw private key representation, not a PEM file.
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
    let keyId: String
    let algorithm: String
    let signatureBase64: String
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

do {
    let manifestData = try Data(contentsOf: manifestURL)
    let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: privateKeyData)
    let signature = try privateKey.signature(for: manifestData)
    let envelope = SignatureEnvelope(
        signatureVersion: 1,
        keyId: keyID,
        algorithm: "Ed25519",
        signatureBase64: signature.base64EncodedString()
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
