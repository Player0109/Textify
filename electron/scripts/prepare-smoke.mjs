import { build } from "esbuild";
import { createRequire } from "node:module";
import { appendFile } from "node:fs/promises";
import { resolve } from "node:path";

await build({
  entryPoints: ["src/main/models.ts"],
  outfile: ".native/smoke-models.cjs",
  bundle: true,
  platform: "node",
  format: "cjs",
});
const { Models } = createRequire(import.meta.url)(
  resolve(".native/smoke-models.cjs"),
);
const model = new Models(
  resolve("resources"),
  resolve(".native/smoke-model"),
  () => {},
);
await model.init();
if (!model.installed) await model.install();
if (process.env.GITHUB_ENV)
  await appendFile(
    process.env.GITHUB_ENV,
    `TEXTIFY_MODEL_FIXTURE=${model.path}\n`,
  );
console.log("Verified public speech-test model:", model.path);
