import { createHash, createPublicKey, verify } from "node:crypto";
import { createReadStream } from "node:fs";
import {
  readFile,
  mkdir,
  open,
  rename,
  rm,
  stat,
  copyFile,
} from "node:fs/promises";
import { join } from "node:path";

const keys: Record<string, string> = {
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
    envelope.contentType !==
      `application/vnd.textify.${kind}+json;version=${revocations ? 2 : 3}` ||
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
    // This first milestone cannot reconcile sticky revocations/restorations yet.
    // Refuse any nonempty signed policy rather than silently ignoring it.
    if (
      body.revocationVersion !== 2 ||
      !Array.isArray(body.records) ||
      !Array.isArray(body.restorations) ||
      body.records.length ||
      body.restorations.length ||
      Object.keys(body).sort().join() !==
        ["revocationVersion", "generatedAt", "records", "restorations"]
          .sort()
          .join()
    )
      throw new Error("revocation_policy_requires_upgrade");
    return body;
  }
  if (
    body.manifestVersion !== 3 ||
    !Array.isArray(body.models) ||
    !body.presentationGraph ||
    Object.keys(body).sort().join() !==
      ["manifestVersion", "generatedAt", "models", "presentationGraph"]
        .sort()
        .join()
  )
    throw new Error("catalog_schema");
  return body;
}
export interface ModelFile {
  filename: string;
  url: string;
  sha256: string;
  sizeBytes: number;
}
export async function hashFile(path: string): Promise<string> {
  const hash = createHash("sha256");
  for await (const chunk of createReadStream(path)) hash.update(chunk);
  return hash.digest("hex");
}
export class Models {
  readonly id = "ggml-small.en-q5_1";
  readonly name = "Whisper small.en";
  file!: ModelFile;
  installed = false;
  busy = false;
  progress: number | null = null;
  private abort?: AbortController;
  constructor(
    private resources: string,
    private storage: string,
    private changed: () => void,
  ) {}
  get path() {
    return join(this.storage, `${this.id}.bin`);
  }
  async init() {
    verifyCatalog(
      await readFile(join(this.resources, "revocations.json")),
      await readFile(join(this.resources, "revocations.json.sig")),
      true,
    );
    const catalog = verifyCatalog(
      await readFile(join(this.resources, "manifest.json")),
      await readFile(join(this.resources, "manifest.json.sig")),
    );
    const model = catalog.models.find((item: any) => item.id === this.id);
    if (
      !model ||
      model.files.length !== 1 ||
      model.runtime.engine !== "whisper_cpp"
    )
      throw new Error("catalog_model");
    const file = model.files[0] as ModelFile;
    if (
      !/^[a-f0-9]{64}$/.test(file.sha256) ||
      !Number.isSafeInteger(file.sizeBytes) ||
      file.sizeBytes <= 0 ||
      file.filename !== "ggml-small.en-q5_1.bin" ||
      file.url !==
        "https://github.com/Player0109/Textify/releases/download/models-v1/ggml-small.en-q5_1.bin"
    )
      throw new Error("catalog_artifact");
    this.file = file;
    await mkdir(this.storage, { recursive: true });
    this.installed = await this.valid(this.path);
  }
  async valid(path: string) {
    try {
      return (
        (await stat(path)).size === this.file.sizeBytes &&
        (await hashFile(path)) === this.file.sha256
      );
    } catch {
      return false;
    }
  }
  cancel() {
    this.abort?.abort();
  }
  async install(source?: string) {
    if (this.busy) throw new Error("model_busy");
    this.busy = true;
    this.progress = 0;
    this.abort = new AbortController();
    this.changed();
    const signal = this.abort.signal;
    const partial = `${this.path}.partial`;
    try {
      if (source) {
        await copyFile(source, partial);
        signal.throwIfAborted();
      } else {
        const response = await fetch(this.file.url, { signal });
        if (!response.ok || !response.body) throw new Error("download_failed");
        const output = await open(partial, "w", 0o600);
        let received = 0;
        try {
          for await (const data of response.body) {
            signal.throwIfAborted();
            received += data.length;
            if (received > this.file.sizeBytes)
              throw new Error("download_size");
            await output.writeFile(data);
            this.progress = received / this.file.sizeBytes;
            this.changed();
          }
          await output.sync();
        } finally {
          await output.close();
        }
      }
      if (!(await this.valid(partial))) throw new Error("model_integrity");
      signal.throwIfAborted();
      await rename(partial, this.path);
      this.installed = true;
    } finally {
      await rm(partial, { force: true });
      this.busy = false;
      this.progress = null;
      this.abort = undefined;
      this.changed();
    }
  }
}
