import {
  readFile,
  mkdir,
  rename,
  rm,
  stat,
  writeFile,
  readdir,
  lstat,
} from "node:fs/promises";
import { basename, join } from "node:path";
import { verifyCatalog } from "./trust";
import { Revocations } from "./revocations";
import { hashFile, validFile, transfer, type ModelFile } from "./transfer";
import type { ModelView } from "../shared";
export { verifyCatalog, hashFile };
export type { ModelFile };

const supported: Record<string, string> = {
  "ggml-small.en-q5_1": "Whisper small.en",
  "whisper-large-v2-q5_0": "Whisper large-v2",
  "whisper-large-v3-q5_0": "Whisper large-v3",
  "whisper-large-v3-turbo-q5_0": "Whisper large-v3-turbo",
};
export interface Model extends ModelView {
  file: ModelFile;
  files: ModelFile[];
  restorations: string[];
}
const extraArtifacts: Record<string, string> = {
  ...Object.fromEntries(
    ["bf16", "q8-0", "q5-k-m"].flatMap((quant) => [
      [`qwen3-asr-0.6b-${quant}`, "transcribe_cpp"],
      [`qwen3-asr-1.7b-${quant}`, "transcribe_cpp"],
    ]),
  ),
  ...Object.fromEntries(
    ["f16", "q8-0", "q5-k-m"].map((quant) => [
      `parakeet-tdt-0.6b-v3-${quant}`,
      "transcribe_cpp",
    ]),
  ),
  "confucius4-r2t2-q8_0": "audio_cpp",
  "confucius4-r2t2-f16": "audio_cpp",
};
export function catalogModels(catalog: any, supplement?: any): Model[] {
  if (
    supplement &&
    (supplement.models?.length !== 1 ||
      supplement.models[0].id !== "confucius4-r2t2-bf16" ||
      catalog.models.some((entry: any) => entry.id === "confucius4-r2t2-bf16"))
  )
    throw new Error("catalog_model");
  const engines = {
    ...Object.fromEntries(
      Object.keys(supported).map((id) => [id, "whisper_cpp"]),
    ),
    ...extraArtifacts,
    ...(supplement ? { "confucius4-r2t2-bf16": "audio_cpp" } : {}),
  };
  return Object.entries(engines).map(([id, engine]) => {
    const source = id === "confucius4-r2t2-bf16" ? supplement : catalog;
    const entry = source.models.find((item: any) => item.id === id);
    const directory = id === "confucius4-r2t2-bf16";
    if (
      !entry ||
      !Array.isArray(entry.files) ||
      !entry.files.length ||
      (!directory && entry.files.length !== 1) ||
      entry.runtime?.engine !== engine ||
      entry.runtime?.artifactLayout !==
        (directory ? "model_directory" : "single_file")
    )
      throw new Error("catalog_model");
    const files = entry.files as ModelFile[];
    for (const file of files) {
      if (
        !/^[a-f0-9]{64}$/.test(file.sha256) ||
        !Number.isSafeInteger(file.sizeBytes) ||
        file.sizeBytes <= 0 ||
        !(
          directory
            ? /^[a-zA-Z0-9_-]+\.(json|txt|safetensors)$/
            : /^[a-zA-Z0-9._-]+\.(bin|gguf)$/
        ).test(file.filename) ||
        (directory && (file as any).relativePath !== file.filename) ||
        !/^https:\/\/(github\.com\/Player0109\/Textify\/releases\/download\/[^/]+\/[^/]+|huggingface\.co\/[^/]+\/[^/]+\/resolve\/[a-f0-9]{40}\/[^?#]+)$/.test(
          file.url,
        )
      )
        throw new Error("catalog_artifact");
    }
    const bytes = files.reduce((total, file) => total + file.sizeBytes, 0);
    if (
      new Set(files.map((f) => f.filename)).size !== files.length ||
      !Number.isSafeInteger(bytes) ||
      bytes !== entry.sizeBytes
    )
      throw new Error("catalog_artifact");
    if (
      directory &&
      [
        "model.safetensors",
        "config.json",
        "generation_config.json",
        "preprocessor_config.json",
        "tokenizer.json",
      ].some((name) => !files.some((f) => f.filename === name))
    )
      throw new Error("catalog_artifact");
    const file = files[0];
    const languages = entry.capabilities?.languages;
    if (
      !Array.isArray(languages) ||
      !languages.length ||
      languages.some(
        (code: unknown) =>
          typeof code !== "string" || !/^[a-z]{2,3}$/.test(code),
      )
    )
      throw new Error("catalog_language");
    const checkpoint = source.presentationGraph?.checkpoints?.find(
      (item: any) => item.artifactIDs?.includes(id),
    );
    const artifact = source.presentationGraph?.artifacts?.find(
      (item: any) => item.id === id,
    );
    const family = source.presentationGraph?.families?.find((item: any) =>
      item.checkpointIDs?.includes(checkpoint?.id),
    );
    if (
      !checkpoint?.presentation?.displayName ||
      !artifact?.presentation?.displayName ||
      !family?.presentation?.provider?.displayName
    )
      throw new Error("catalog_presentation");
    return {
      id,
      engine: engine as ModelView["engine"],
      name: checkpoint.presentation.displayName,
      checkpointID: checkpoint.id,
      description:
        engine === "audio_cpp"
          ? "Live English and Chinese previews, with final insertion on release."
          : engine === "whisper_cpp"
            ? id.includes("turbo")
              ? "Fast Whisper dictation for English and Hindi."
              : id === "ggml-small.en-q5_1"
                ? "Compact Whisper model for everyday English dictation."
                : "Higher-capacity Whisper model for English dictation."
            : checkpoint.presentation.description,
      variant: artifact.presentation.displayName,
      provider: family.presentation.provider.displayName,
      license: entry.licenses[0].name,
      source: entry.provenance.originalModelUrl,
      vocabulary: engine === "whisper_cpp",

      bytes,
      directory,
      installed: false,
      status: "not-installed",
      languages:
        engine === "transcribe_cpp" && entry.runtimeParameters?.detectLanguage
          ? ["auto", ...languages]
          : languages,
      resumable: false,
      storedBytes: 0,
      file,
      files,
      restorations: [],
    };
  });
}
export class Models {
  id = "ggml-small.en-q5_1";
  entries: Model[] = [];
  busy = false;
  progress: number | null = null;
  progressID: string | null = null;
  private abort?: AbortController;
  private revocations: Revocations;
  constructor(
    private resources: string,
    private storage: string,
    private changed: () => void,
  ) {
    this.revocations = new Revocations(join(storage, "trust.json"));
  }
  get selected() {
    return this.entries.find((entry) => entry.id === this.id);
  }
  get name() {
    return this.selected?.name ?? "";
  }
  get file() {
    return this.selected?.file;
  }
  get installed() {
    return this.selected?.status === "installed";
  }
  get path() {
    return this.pathFor(this.id);
  }
  pathFor(id: string) {
    const model = this.get(id);
    if (model.directory) return join(this.storage, id);
    return join(
      this.storage,
      `${id}.${model.engine === "whisper_cpp" ? "bin" : "gguf"}`,
    );
  }
  get(id: string): Model {
    const model = this.entries.find((entry) => entry.id === id);
    if (!model) throw new Error("model_unknown");
    return model;
  }
  views(): ModelView[] {
    return this.entries.map(
      ({ file: _file, files: _files, restorations: _restorations, ...view }) =>
        view,
    );
  }
  async init(id = this.id) {
    this.busy = true;
    this.changed();
    try {
      await mkdir(this.storage, { recursive: true });
      const [
        catalog,
        signature,
        revocations,
        revocationSignature,
        extra,
        extraSignature,
      ] = await Promise.all([
        readFile(join(this.resources, "manifest.json")),
        readFile(join(this.resources, "manifest.json.sig")),
        readFile(join(this.resources, "revocations.json")),
        readFile(join(this.resources, "revocations.json.sig")),
        readFile(join(this.resources, "extra-models/manifest.json")),
        readFile(join(this.resources, "extra-models/manifest.json.sig")),
      ]);
      await this.revocations.load(
        catalog,
        signature,
        revocations,
        revocationSignature,
      );
      const supplement = verifyCatalog(extra, extraSignature);
      this.revocations.addAliases(supplement.artifactAliases);
      this.entries = catalogModels(
        verifyCatalog(catalog, signature),
        supplement,
      );
      this.id = id;
      for (const model of this.entries) await this.refresh(model);
    } finally {
      this.busy = false;
      this.changed();
    }
  }
  private async refresh(model: Model) {
    const protection = this.revocations.status(model.id, model.files);
    model.restorations = protection.restorations;
    model.installed = await this.valid(model);
    const partial = `${this.pathFor(model.id)}.partial`;
    model.resumable = model.directory
      ? await readdir(partial)
          .then((names) => names.length > 0)
          .catch(() => false)
      : await stat(partial)
          .then((value) => value.size > 0)
          .catch(() => false);
    model.storedBytes = 0;
    for (const name of await readdir(this.storage))
      if (
        name === basename(this.pathFor(model.id)) ||
        name === `${basename(this.pathFor(model.id))}.partial` ||
        name.startsWith(`${basename(this.pathFor(model.id))}.retained-`)
      )
        model.storedBytes += await storedBytes(join(this.storage, name));
    let receipt: string[] = [];
    try {
      receipt = JSON.parse(
        await readFile(`${this.pathFor(model.id)}.receipt.json`, "utf8"),
      ).restorations;
    } catch {}
    model.status = protection.revoked
      ? "revoked"
      : !model.installed
        ? "not-installed"
        : JSON.stringify(receipt) !== JSON.stringify(model.restorations)
          ? "verify-required"
          : "installed";
  }
  private admit(model: Model) {
    if (this.revocations.status(model.id, model.files).revoked)
      throw new Error("model_revoked");
  }
  private async receipt(model: Model) {
    const path = `${this.pathFor(model.id)}.receipt.json`;
    await writeFile(
      `${path}.tmp`,
      JSON.stringify({
        files: model.files.map(({ filename, sha256 }) => ({
          filename,
          sha256,
        })),
        restorations: model.restorations,
      }),
      { mode: 0o600 },
    );
    await rename(`${path}.tmp`, path);
  }
  cancel() {
    this.abort?.abort();
  }
  async verify(id = this.id) {
    if (this.busy) throw new Error("model_busy");
    this.busy = true;
    this.changed();
    try {
      const model = this.get(id);
      this.admit(model);
      if (!(await this.valid(model))) throw new Error("model_integrity");
      this.admit(model);
      await this.receipt(model);
      await this.refresh(model);
    } finally {
      this.busy = false;
      this.changed();
    }
  }
  async install(source?: string, id = this.id) {
    if (this.busy) throw new Error("model_busy");
    const model = this.get(id);
    this.admit(model);
    this.busy = true;
    this.progress = 0;
    this.progressID = id;
    this.abort = new AbortController();
    this.changed();
    try {
      // Restored content starts a fresh attempt and never consumes revoked partials.
      if (model.restorations.length && model.resumable) {
        const retained = `${this.pathFor(id)}.retained-${Date.now()}`;
        await rename(`${this.pathFor(id)}.partial`, retained);
        await rm(`${this.pathFor(id)}.partial.json`, { force: true });
      }
      if (model.directory) {
        await this.installDirectory(model, this.abort.signal, source);
      } else {
        const partial = await transfer(
          model.file,
          this.pathFor(id),
          this.abort.signal,
          (value) => {
            this.progress = value;
            this.changed();
          },
          source,
        );
        this.admit(model);
        this.abort.signal.throwIfAborted();
        await rename(partial, this.pathFor(id));
        await rm(`${partial}.json`, { force: true });
      }
      await this.receipt(model);
    } finally {
      try {
        await this.refresh(model);
      } finally {
        this.busy = false;
        this.progress = null;
        this.progressID = null;
        this.abort = undefined;
        this.changed();
      }
    }
  }
  async remove(id: string) {
    if (this.busy) throw new Error("model_busy");
    const model = this.get(id);
    this.busy = true;
    this.changed();
    try {
      for (const suffix of ["", ".partial", ".partial.json", ".receipt.json"])
        await rm(`${this.pathFor(id)}${suffix}`, {
          force: true,
          recursive: true,
        });
      for (const name of await readdir(this.storage))
        if (name.startsWith(`${basename(this.pathFor(id))}.retained-`))
          await rm(join(this.storage, name), { force: true, recursive: true });
      await this.refresh(model);
    } finally {
      this.busy = false;
      this.changed();
    }
  }
  private async valid(model: Model, path = this.pathFor(model.id)) {
    if (!model.directory) return validFile(path, model.file);
    try {
      // Never load extra GGUF weights, scripts, or symlinks from an imported folder.
      if (!(await lstat(path)).isDirectory()) return false;
      const names = await readdir(path);
      if (names.length !== model.files.length) return false;
      for (const file of model.files)
        if (
          !(await lstat(join(path, file.filename))).isFile() ||
          !(await validFile(join(path, file.filename), file))
        )
          return false;
      return true;
    } catch {
      return false;
    }
  }
  private async installDirectory(
    model: Model,
    signal: AbortSignal,
    source?: string,
  ) {
    const destination = this.pathFor(model.id),
      staging = `${destination}.partial`;
    await mkdir(staging, { recursive: true, mode: 0o700 });
    let completed = 0;
    for (const file of model.files) {
      signal.throwIfAborted();
      this.admit(model);
      const path = join(staging, file.filename);
      if (!(await validFile(path, file))) {
        const partial = await transfer(
          file,
          path,
          signal,
          (fraction) => {
            this.progress =
              (completed + fraction * file.sizeBytes) / model.bytes;
            this.changed();
          },
          source ? join(source, file.filename) : undefined,
        );
        signal.throwIfAborted();
        await rename(partial, path);
        await rm(`${partial}.json`, { force: true });
      }
      completed += file.sizeBytes;
    }
    if (!(await this.valid(model, staging))) throw new Error("model_integrity");
    this.admit(model);
    signal.throwIfAborted();
    // Keep an existing installation intact until every replacement file verifies.
    const retained = `${destination}.retained-${Date.now()}`;
    let moved = false;
    try {
      await rename(destination, retained).then(
        () => {
          moved = true;
        },
        (error) => {
          if (error.code !== "ENOENT") throw error;
        },
      );
      await rename(staging, destination);
    } catch (error) {
      if (moved) await rename(retained, destination);
      throw error;
    }
    if (moved) await rm(retained, { recursive: true, force: true });
  }
}

async function storedBytes(path: string): Promise<number> {
  const info = await lstat(path);
  if (info.isFile()) return info.size;
  if (!info.isDirectory()) return 0;
  let bytes = 0;
  for (const name of await readdir(path))
    bytes += await storedBytes(join(path, name));
  return bytes;
}
