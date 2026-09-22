import { readFile } from "node:fs/promises";
import { describe, expect, it } from "vitest";
import { verifyCatalog } from "../src/main/models";
const bytes = await readFile("../models/manifest.json");
const signature = await readFile("../models/manifest.json.sig");
describe("catalog trust", () => {
  it("verifies the actual signed catalog without a network request", () =>
    expect(verifyCatalog(bytes, signature).models.length).toBeGreaterThan(0));
  it("rejects changed content even when it is valid JSON", () =>
    expect(() =>
      verifyCatalog(
        Buffer.from(bytes.toString().replace("Balanced", "Modified")),
        signature,
      ),
    ).toThrow());
  it("rejects an attacker-updated content hash without a new signature", async () => {
    const { createHash } = await import("node:crypto");
    const changed = Buffer.from(
      bytes.toString().replace("Balanced", "Modified"),
    );
    const sig = JSON.parse(signature.toString());
    sig.contentSHA256 = createHash("sha256").update(changed).digest("hex");
    expect(() =>
      verifyCatalog(changed, Buffer.from(JSON.stringify(sig))),
    ).toThrow();
  });
  it.each(["keyId", "signatureType", "contentType", "manifestFile"])(
    "rejects invalid %s",
    (key) => {
      const sig = JSON.parse(signature.toString());
      sig[key] = "invalid";
      expect(() =>
        verifyCatalog(bytes, Buffer.from(JSON.stringify(sig))),
      ).toThrow();
    },
  );
  it("rejects extra signature envelope fields", () => {
    const sig = { ...JSON.parse(signature.toString()), extra: true };
    expect(() =>
      verifyCatalog(bytes, Buffer.from(JSON.stringify(sig))),
    ).toThrow();
  });
  it("verifies the bundled empty revocation policy", async () => {
    expect(
      verifyCatalog(
        await readFile("../models/revocations.json"),
        await readFile("../models/revocations.json.sig"),
        true,
      ).records,
    ).toEqual([]);
  });
});

describe("runtime admission", () => {
  it("admits the four new GGUF checkpoint families on Apple Silicon", async () => {
    const { catalogModels } = await import("../src/main/models");
    const models = catalogModels(
      verifyCatalog(bytes, signature),
      "darwin",
      "arm64",
    );
    expect(models).toHaveLength(15);
    expect(new Set(models.map((m) => m.checkpointID)).size).toBe(8);
    const qwen = models.find((m) => m.id === "qwen3-asr-1.7b-bf16")!;
    expect(qwen).toMatchObject({
      engine: "transcribe_cpp",
      provider: "Qwen",
      variant: "GGUF BF16",
      vocabulary: false,
    });
    expect(qwen.languages).toContain("hi");
    expect(qwen.languages).toContain("auto");
    const confucius = models.find((m) => m.id === "confucius4-r2t2-f16")!;
    expect(confucius.languages).toEqual(["en", "zh"]);
    expect(confucius.license).toContain("NetEase");
    expect(models.some((m) => /mlx|coreml/.test(m.id))).toBe(false);
  });
  it.each([
    ["win32", "x64"],
    ["linux", "x64"],
    ["darwin", "x64"],
  ] as const)(
    "keeps unavailable engines out of %s/%s",
    async (platform, arch) => {
      const { catalogModels } = await import("../src/main/models");
      expect(
        catalogModels(verifyCatalog(bytes, signature), platform, arch).map(
          (m) => m.engine,
        ),
      ).toEqual(Array(4).fill("whisper_cpp"));
    },
  );
  it("rejects engine mismatches and unsafe GGUF paths", async () => {
    const { catalogModels } = await import("../src/main/models");
    const catalog = verifyCatalog(bytes, signature);
    const model = catalog.models.find(
      (m: any) => m.id === "qwen3-asr-0.6b-q8-0",
    );
    model.runtime.engine = "audio_cpp";
    expect(() => catalogModels(catalog, "darwin", "arm64")).toThrow(
      "catalog_model",
    );
    model.runtime.engine = "transcribe_cpp";
    model.files[0].filename = "../outside.gguf";
    expect(() => catalogModels(catalog, "darwin", "arm64")).toThrow(
      "catalog_artifact",
    );
  });
});
