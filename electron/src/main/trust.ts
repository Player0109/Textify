import { createHash, createPublicKey, verify } from "node:crypto";
export const keys: Record<string, string> = {
  "textify-model-manifest-2026-primary":
    "mLO7nEpXKrM6LkuQrMrpXtGDaJFEQWQivS9Hxm8RWY0=",
  "textify-model-manifest-2026-reserve":
    "4U2qV+TakjtL2HleKRPAhpd9LTTIfhGEmvZR4Opc1ZM=",
  "textify-model-manifest-2026-huggingface":
    "eg6XVGVQ4Kqh1dtN3B8JcFTtK0RSxkxd79W5tfIlfos=",
};
export function verifyCatalog(
  bytes: Buffer,
  signatureBytes: Buffer,
  revocations = false,
): Record<string, any> {
  const envelope = JSON.parse(signatureBytes.toString());
  const fileKey = revocations ? "revocationFile" : "manifestFile";
  const kind = revocations ? "model-revocations" : "model-manifest";
  const fields = [
    "signatureVersion",
    "signatureType",
    "algorithm",
    "keyId",
    fileKey,
    "contentType",
    "contentSHA256",
    "signature",
  ];
  if (
    Object.keys(envelope).sort().join() !== fields.sort().join() ||
    envelope.signatureVersion !== 1 ||
    envelope.signatureType !== `io.github.Player0109.Textify.${kind}` ||
    envelope.algorithm !== "Ed25519" ||
    envelope[fileKey] !==
      (revocations ? "revocations.json" : "manifest.json") ||
    !keys[envelope.keyId] ||
    !(revocations ? [1, 2] : [3])
      .map(
        (version) => `application/vnd.textify.${kind}+json;version=${version}`,
      )
      .includes(envelope.contentType) ||
    !/^[a-f0-9]{64}$/.test(envelope.contentSHA256) ||
    !/^[A-Za-z0-9_-]{86}$/.test(envelope.signature) ||
    createHash("sha256").update(bytes).digest("hex") !== envelope.contentSHA256
  )
    throw new Error("catalog_integrity");
  const payload =
    (revocations
      ? "TEXTIFY-MODEL-REVOCATIONS-SIGNATURE-V1\n"
      : "TEXTIFY-MODEL-MANIFEST-SIGNATURE-V1\n") +
    [
      "signatureVersion",
      "signatureType",
      "algorithm",
      "keyId",
      fileKey,
      "contentType",
      "contentSHA256",
    ]
      .map((key) => `${key}=${envelope[key]}\n`)
      .join("");
  const key = createPublicKey({
    key: Buffer.concat([
      Buffer.from("302a300506032b6570032100", "hex"),
      Buffer.from(keys[envelope.keyId], "base64"),
    ]),
    format: "der",
    type: "spki",
  });
  if (
    !verify(
      null,
      Buffer.from(payload),
      key,
      Buffer.from(envelope.signature, "base64url"),
    )
  )
    throw new Error("catalog_integrity");
  const body = JSON.parse(bytes.toString());
  if (revocations) {
    if (
      envelope.contentType !==
      `application/vnd.textify.${kind}+json;version=${body.revocationVersion}`
    )
      throw new Error("revocation_version");
    return body;
  }
  if (
    body.manifestVersion !== 3 ||
    !Array.isArray(body.models) ||
    !body.presentationGraph ||
    Object.keys(body)
      .filter((key) => key !== "artifactAliases")
      .sort()
      .join() !==
      ["manifestVersion", "generatedAt", "models", "presentationGraph"]
        .sort()
        .join()
  )
    throw new Error("catalog_schema");
  return body;
}
