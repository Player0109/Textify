import { createHash } from "node:crypto";
import { readFile, writeFile, rename } from "node:fs/promises";
import { verifyCatalog } from "./trust";

type Digest = {
  algorithm: "sha256";
  value: string;
  scope:
    | { type: "single_file_payload" }
    | { type: "canonical_layout"; version: 1 }
    | { type: "managed_file"; relativePath: string };
};
type Target = { exactArtifactID: string | null; contentDigest: Digest | null };
type RecordEntry = Target & { recordID: string };
type Restoration = Target & {
  restorationID: string;
  revocationRecordID: string;
};
export type Policy = {
  revocationVersion: 1 | 2;
  generatedAt: string;
  records: RecordEntry[];
  restorations: Restoration[];
};
type Envelope = { bytes: string; signature: string };
type Alias = { aliasArtifactID: string; canonicalArtifactID: string };
const equal = (a: unknown, b: unknown) =>
  JSON.stringify(a) === JSON.stringify(b);
const identifier = (value: unknown): value is string =>
  typeof value === "string" && /^[a-zA-Z0-9._-]{1,240}$/.test(value);
function keys(value: any, expected: string[]) {
  if (
    !value ||
    typeof value !== "object" ||
    Object.keys(value).sort().join() !== expected.sort().join()
  )
    throw new Error("revocation_schema");
}
function target(value: any): Target {
  const id = value.exactArtifactID ?? null,
    raw = value.contentDigest ?? null;
  if (id !== null && !identifier(id)) throw new Error("revocation_target");
  let digest: Digest | null = null;
  if (raw !== null) {
    keys(raw, ["algorithm", "value", "scope"]);
    if (raw.algorithm !== "sha256" || !/^[a-f0-9]{64}$/.test(raw.value))
      throw new Error("revocation_digest");
    const scope = raw.scope;
    if (scope?.type === "single_file_payload") keys(scope, ["type"]);
    else if (scope?.type === "canonical_layout" && scope.version === 1)
      keys(scope, ["type", "version"]);
    else if (
      scope?.type === "managed_file" &&
      typeof scope.relativePath === "string" &&
      scope.relativePath
        .split("/")
        .every(
          (part: string) =>
            /^[a-zA-Z0-9._-]+$/.test(part) && ![".", ".."].includes(part),
        )
    )
      keys(scope, ["type", "relativePath"]);
    else throw new Error("revocation_scope");
    digest = {
      algorithm: "sha256",
      value: raw.value,
      scope:
        scope.type === "single_file_payload"
          ? { type: scope.type }
          : scope.type === "canonical_layout"
            ? { type: scope.type, version: 1 }
            : { type: scope.type, relativePath: scope.relativePath },
    };
  }
  if (id === null && digest === null) throw new Error("revocation_target");
  return { exactArtifactID: id, contentDigest: digest };
}
export function validatePolicy(raw: any): Policy {
  keys(raw, [
    "revocationVersion",
    "generatedAt",
    "records",
    ...(raw.revocationVersion === 2 ? ["restorations"] : []),
  ]);
  if (
    ![1, 2].includes(raw.revocationVersion) ||
    !/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$/.test(raw.generatedAt) ||
    !Number.isFinite(Date.parse(raw.generatedAt)) ||
    !Array.isArray(raw.records) ||
    (raw.revocationVersion === 2 && !Array.isArray(raw.restorations))
  )
    throw new Error("revocation_schema");
  const seen = new Set<string>();
  const records = raw.records.map((record: any) => {
    keys(record, ["recordID", "exactArtifactID", "contentDigest"]);
    if (!identifier(record.recordID) || seen.has(record.recordID))
      throw new Error("revocation_record");
    seen.add(record.recordID);
    return { recordID: record.recordID, ...target(record) };
  });
  seen.clear();
  const restorations = (raw.restorations ?? []).map((entry: any) => {
    keys(entry, [
      "restorationID",
      "revocationRecordID",
      "exactArtifactID",
      "contentDigest",
    ]);
    if (
      !identifier(entry.restorationID) ||
      !identifier(entry.revocationRecordID) ||
      seen.has(entry.restorationID)
    )
      throw new Error("revocation_restoration");
    seen.add(entry.restorationID);
    return {
      restorationID: entry.restorationID,
      revocationRecordID: entry.revocationRecordID,
      ...target(entry),
    };
  });
  return {
    revocationVersion: raw.revocationVersion,
    generatedAt: raw.generatedAt,
    records,
    restorations,
  };
}

export class RevocationState {
  private records = new Map<string, RecordEntry>();
  private restorations = new Map<string, Restoration>();
  private revision = "";
  private current?: Policy;
  private aliases: Alias[] = [];
  addAliases(entries: unknown) {
    if (entries === undefined) return;
    if (!Array.isArray(entries)) throw new Error("catalog_aliases");
    for (const alias of entries) {
      keys(alias, ["aliasArtifactID", "canonicalArtifactID"]);
      if (
        !identifier(alias.aliasArtifactID) ||
        !identifier(alias.canonicalArtifactID)
      )
        throw new Error("catalog_aliases");
      this.aliases.push(alias);
    }
  }
  accept(raw: unknown): boolean {
    const policy = validatePolicy(raw);
    if (policy.generatedAt < this.revision) return false; // Keep newer accepted protection on downgrade.
    if (policy.generatedAt === this.revision) {
      if (!equal(policy, this.current))
        throw new Error("revocation_revision_conflict");
      return false;
    }
    for (const record of policy.records) {
      const prior = this.records.get(record.recordID);
      if (prior && !equal(prior, record))
        throw new Error("revocation_record_conflict");
    }
    for (const restoration of policy.restorations) {
      const prior = this.restorations.get(restoration.restorationID);
      if (prior && !equal(prior, restoration))
        throw new Error("revocation_restoration_conflict");
      if (prior) continue;
      const record = this.records.get(restoration.revocationRecordID);
      if (
        !record ||
        (restoration.exactArtifactID !== null &&
          restoration.exactArtifactID !== record.exactArtifactID) ||
        (restoration.contentDigest !== null &&
          !equal(restoration.contentDigest, record.contentDigest))
      )
        throw new Error("revocation_restoration_target");
    }
    for (const record of policy.records)
      this.records.set(record.recordID, record);
    for (const entry of policy.restorations)
      this.restorations.set(entry.restorationID, entry);
    this.revision = policy.generatedAt;
    this.current = policy;
    return true;
  }
  status(
    id: string,
    input:
      | { filename: string; sha256: string; sizeBytes: number }
      | { filename: string; sha256: string; sizeBytes: number }[],
  ) {
    const files = Array.isArray(input) ? input : [input];
    const identities = new Set([id]);
    let changed = true;
    while (changed) {
      changed = false;
      for (const alias of this.aliases)
        if (
          identities.has(alias.aliasArtifactID) ||
          identities.has(alias.canonicalArtifactID)
        ) {
          const count = identities.size;
          identities.add(alias.aliasArtifactID);
          identities.add(alias.canonicalArtifactID);
          changed ||= count !== identities.size;
        }
    }
    const layout = createHash("sha256")
      .update(
        [...files]
          .sort((a, b) =>
            a.filename < b.filename ? -1 : a.filename > b.filename ? 1 : 0,
          )
          .map(
            (file) => `${file.filename}\t${file.sha256}\t${file.sizeBytes}\n`,
          )
          .join(""),
      )
      .digest("hex");
    const matches = (entry: Target) =>
      (entry.exactArtifactID !== null &&
        identities.has(entry.exactArtifactID)) ||
      (entry.contentDigest !== null &&
        (entry.contentDigest.scope.type === "canonical_layout"
          ? entry.contentDigest.value === layout
          : files.some(
              (file) =>
                entry.contentDigest!.value === file.sha256 &&
                (entry.contentDigest!.scope.type === "single_file_payload"
                  ? files.length === 1
                  : entry.contentDigest!.scope.type === "managed_file" &&
                    entry.contentDigest!.scope.relativePath === file.filename),
            )));
    let revoked = false;
    const acknowledged = new Set<string>();
    for (const record of this.records.values()) {
      const remaining: Target = {
        exactArtifactID: record.exactArtifactID,
        contentDigest: record.contentDigest,
      };
      for (const restoration of this.restorations.values())
        if (restoration.revocationRecordID === record.recordID) {
          if (restoration.exactArtifactID !== null)
            remaining.exactArtifactID = null;
          if (restoration.contentDigest !== null)
            remaining.contentDigest = null;
          if (matches(restoration)) acknowledged.add(restoration.restorationID);
        }
      revoked ||= Boolean(matches(remaining));
    }
    return { revoked, restorations: [...acknowledged].sort() };
  }
}

export class Revocations extends RevocationState {
  private history: Envelope[] = [];
  private catalogs: Envelope[] = [];
  constructor(private path: string) {
    super();
  }
  async load(
    catalog: Buffer,
    catalogSignature: Buffer,
    bytes: Buffer,
    signature: Buffer,
  ) {
    let saved: any;
    try {
      saved = JSON.parse(await readFile(this.path, "utf8"));
    } catch (error: any) {
      if (error.code !== "ENOENT") throw new Error("revocation_cache_corrupt");
    }
    const decode = (entry: Envelope, policy: boolean) => {
      keys(entry, ["bytes", "signature"]);
      if (
        typeof entry.bytes !== "string" ||
        typeof entry.signature !== "string"
      )
        throw new Error("revocation_cache_corrupt");
      return verifyCatalog(
        Buffer.from(entry.bytes, "base64"),
        Buffer.from(entry.signature, "base64"),
        policy,
      );
    };
    if (saved) {
      keys(saved, ["history", "catalogs"]);
      if (!Array.isArray(saved.history) || !Array.isArray(saved.catalogs))
        throw new Error("revocation_cache_corrupt");
      for (const entry of saved.history) {
        if (!this.accept(decode(entry, true)))
          throw new Error("revocation_cache_order");
      }
      for (const entry of saved.catalogs)
        this.addAliases(decode(entry, false).artifactAliases);
      this.history = saved.history;
      this.catalogs = saved.catalogs;
    }
    const incoming = verifyCatalog(catalog, catalogSignature);
    this.addAliases(incoming.artifactAliases);
    const envelope = (value: Buffer, sig: Buffer) => ({
      bytes: value.toString("base64"),
      signature: sig.toString("base64"),
    });
    if (
      incoming.artifactAliases?.length &&
      !this.catalogs.some((entry) => entry.bytes === catalog.toString("base64"))
    )
      this.catalogs.push(envelope(catalog, catalogSignature));
    if (this.accept(verifyCatalog(bytes, signature, true)))
      this.history.push(envelope(bytes, signature));
    await writeFile(
      `${this.path}.tmp`,
      JSON.stringify({ history: this.history, catalogs: this.catalogs }),
      { mode: 0o600 },
    );
    await rename(`${this.path}.tmp`, this.path);
  }
}
