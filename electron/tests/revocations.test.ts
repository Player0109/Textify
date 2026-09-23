import { describe, expect, it } from "vitest";
import {
  RevocationState,
  validatePolicy,
  Revocations,
} from "../src/main/revocations";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { createHash } from "node:crypto";
const file = { filename: "model.bin", sha256: "a".repeat(64), sizeBytes: 100 };
const digest = {
  algorithm: "sha256",
  value: file.sha256,
  scope: { type: "single_file_payload" },
};
const record = {
  recordID: "advisory",
  exactArtifactID: "model",
  contentDigest: digest,
};
const policy = (
  day: number,
  records: unknown[] = [],
  restorations: unknown[] = [],
) => ({
  revocationVersion: 2,
  generatedAt: `2026-09-${String(day).padStart(2, "0")}T00:00:00Z`,
  records,
  restorations,
});
const restoration = {
  restorationID: "restore",
  revocationRecordID: "advisory",
  exactArtifactID: "model",
  contentDigest: null,
};
describe("sticky model revocations", () => {
  it("matches a whole directory layout and each managed file without confusing payload digests", () => {
    const files = [
      file,
      { ...file, filename: "config.json", sha256: "b".repeat(64) },
    ];
    const layout = createHash("sha256")
      .update(
        `config.json\t${"b".repeat(64)}\t100\nmodel.bin\t${file.sha256}\t100\n`,
      )
      .digest("hex");
    for (const contentDigest of [
      {
        algorithm: "sha256",
        value: layout,
        scope: { type: "canonical_layout", version: 1 },
      },
      {
        algorithm: "sha256",
        value: files[1].sha256,
        scope: { type: "managed_file", relativePath: "config.json" },
      },
    ]) {
      const state = new RevocationState();
      state.accept(
        policy(2, [
          { recordID: "directory", exactArtifactID: null, contentDigest },
        ]),
      );
      expect(state.status("other-id", files).revoked).toBe(true);
    }
    const state = new RevocationState();
    state.accept(policy(2, [{ ...record, exactArtifactID: null }]));
    expect(state.status("other-id", files).revoked).toBe(false);
  });
  it("retains protection across omission and older bundled releases", () => {
    const state = new RevocationState();
    state.accept(policy(2, [record]));
    state.accept(policy(3));
    state.accept(policy(1));
    expect(state.status("model", file).revoked).toBe(true);
    expect(state.status("custom-import", file).revoked).toBe(true);
  });
  it("rejects mutated records and conflicting signed timestamps", () => {
    const state = new RevocationState();
    state.accept(policy(2, [record]));
    expect(() =>
      state.accept(policy(3, [{ ...record, exactArtifactID: "other" }])),
    ).toThrow("record_conflict");
    expect(() => state.accept(policy(2))).toThrow("revision_conflict");
  });
  it("restores only repeated predicates and retains an overlapping revocation", () => {
    const state = new RevocationState();
    state.accept(policy(2, [record]));
    state.accept(policy(3, [], [restoration]));
    expect(state.status("model", file).revoked).toBe(true); // Digest predicate still applies.
    state.accept(
      policy(
        4,
        [],
        [
          {
            ...restoration,
            restorationID: "restore-digest",
            exactArtifactID: null,
            contentDigest: digest,
          },
        ],
      ),
    );
    expect(state.status("model", file)).toEqual({
      revoked: false,
      restorations: ["restore", "restore-digest"],
    });
    state.accept(policy(5, [{ ...record, recordID: "second-advisory" }]));
    expect(state.status("model", file).revoked).toBe(true);
  });
  it("rejects restorations of a same-revision record and wrong targets", () => {
    const state = new RevocationState();
    expect(() => state.accept(policy(2, [record], [restoration]))).toThrow(
      "restoration_target",
    );
    state.accept(policy(2, [record]));
    expect(() =>
      state.accept(
        policy(3, [], [{ ...restoration, exactArtifactID: "different" }]),
      ),
    ).toThrow("restoration_target");
  });
  it("preserves signed aliases and typed digest matching", () => {
    const state = new RevocationState();
    state.addAliases([
      { aliasArtifactID: "legacy", canonicalArtifactID: "model" },
    ]);
    state.accept(
      policy(2, [
        {
          recordID: "alias-ban",
          exactArtifactID: "legacy",
          contentDigest: null,
        },
      ]),
    );
    expect(
      state.status("model", { ...file, sha256: "b".repeat(64) }).revoked,
    ).toBe(true);
  });
  it("fails closed on unsafe paths, unknown scopes, and duplicate IDs", () => {
    expect(() => validatePolicy(policy(2, [record, record]))).toThrow();
    for (const scope of [
      { type: "managed_file", relativePath: "../model.bin" },
      { type: "canonical_layout", version: 2 },
      { type: "unknown" },
    ])
      expect(() =>
        validatePolicy(
          policy(2, [{ ...record, contentDigest: { ...digest, scope } }]),
        ),
      ).toThrow();
  });
  it("re-verifies exact signed envelopes on relaunch and rejects a corrupt cache", async () => {
    const directory = await mkdtemp(join(tmpdir(), "textify-revocations-"));
    const path = join(directory, "trust.json");
    try {
      const args = await Promise.all(
        [
          "manifest.json",
          "manifest.json.sig",
          "revocations.json",
          "revocations.json.sig",
        ].map((name) => readFile(`../models/${name}`)),
      );
      await new Revocations(path).load(args[0], args[1], args[2], args[3]);
      await new Revocations(path).load(args[0], args[1], args[2], args[3]);
      const cache = JSON.parse(await readFile(path, "utf8"));
      cache.history[0].bytes = Buffer.from("{}").toString("base64");
      await writeFile(path, JSON.stringify(cache));
      await expect(
        new Revocations(path).load(args[0], args[1], args[2], args[3]),
      ).rejects.toThrow();
    } finally {
      await rm(directory, { recursive: true, force: true });
    }
  });
});
