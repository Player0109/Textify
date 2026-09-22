import {
  readFile,
  mkdir,
  rename,
  rm,
  stat,
  writeFile,
  readdir,
} from "node:fs/promises";
import { join } from "node:path";
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
  restorations: string[];
}
export function catalogModels(catalog: any): Model[] {
  return Object.entries(supported).map(([id, name]) => {
    const entry = catalog.models.find((item: any) => item.id === id);
    if (
      !entry ||
      entry.files?.length !== 1 ||
      entry.runtime?.engine !== "whisper_cpp" ||
      entry.runtime?.artifactLayout !== "single_file"
    )
      throw new Error("catalog_model");
    const file = entry.files[0] as ModelFile;
    if (
      !/^[a-f0-9]{64}$/.test(file.sha256) ||
      !Number.isSafeInteger(file.sizeBytes) ||
      file.sizeBytes <= 0 ||
      !/^[a-zA-Z0-9._-]+\.bin$/.test(file.filename) ||
      !/^https:\/\/(github\.com\/Player0109\/Textify\/releases\/download\/[^/]+\/[^/]+|huggingface\.co\/[^/]+\/[^/]+\/resolve\/[a-f0-9]{40}\/[^?#]+)$/.test(
        file.url,
      )
    )
      throw new Error("catalog_artifact");
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
    return {
      id,
      name,
      bytes: file.sizeBytes,
      installed: false,
      status: "not-installed",
      languages,
      resumable: false,
      storedBytes: 0,
      file,
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
    this.get(id);
    return join(this.storage, `${id}.bin`);
  }
  get(id: string): Model {
    const model = this.entries.find((entry) => entry.id === id);
    if (!model) throw new Error("model_unknown");
    return model;
  }
  views(): ModelView[] {
    return this.entries.map(
      ({ file: _file, restorations: _restorations, ...view }) => view,
    );
  }
  async init(id = this.id) {
    this.busy = true;
    this.changed();
    try {
      await mkdir(this.storage, { recursive: true });
      const [catalog, signature, revocations, revocationSignature] =
        await Promise.all([
          readFile(join(this.resources, "manifest.json")),
          readFile(join(this.resources, "manifest.json.sig")),
          readFile(join(this.resources, "revocations.json")),
          readFile(join(this.resources, "revocations.json.sig")),
        ]);
      await this.revocations.load(
        catalog,
        signature,
        revocations,
        revocationSignature,
      );
      this.entries = catalogModels(verifyCatalog(catalog, signature));
      this.id = id;
      for (const model of this.entries) await this.refresh(model);
    } finally {
      this.busy = false;
      this.changed();
    }
  }
  private async refresh(model: Model) {
    const protection = this.revocations.status(model.id, model.file);
    model.restorations = protection.restorations;
    model.installed = await validFile(this.pathFor(model.id), model.file);
    model.resumable = await stat(`${this.pathFor(model.id)}.partial`)
      .then((value) => value.size > 0)
      .catch(() => false);
    model.storedBytes = 0;
    for (const name of await readdir(this.storage))
      if (
        name === `${model.id}.bin` ||
        name === `${model.id}.bin.partial` ||
        name.startsWith(`${model.id}.bin.retained-`)
      )
        model.storedBytes += (await stat(join(this.storage, name))).size;
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
    if (this.revocations.status(model.id, model.file).revoked)
      throw new Error("model_revoked");
  }
  private async receipt(model: Model) {
    const path = `${this.pathFor(model.id)}.receipt.json`;
    await writeFile(
      `${path}.tmp`,
      JSON.stringify({
        sha256: model.file.sha256,
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
      if (!(await validFile(this.pathFor(id), model.file)))
        throw new Error("model_integrity");
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
        await rm(`${this.pathFor(id)}${suffix}`, { force: true });
      for (const name of await readdir(this.storage))
        if (name.startsWith(`${id}.bin.retained-`))
          await rm(join(this.storage, name), { force: true });
      await this.refresh(model);
    } finally {
      this.busy = false;
      this.changed();
    }
  }
}
