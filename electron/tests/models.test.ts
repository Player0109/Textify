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
