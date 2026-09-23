import { build } from "esbuild";
import { build as viteBuild } from "vite";
import { cp, mkdir, access } from "node:fs/promises";
import { resolve } from "node:path";

await mkdir("resources", { recursive: true });
await cp("models", "resources/extra-models", { recursive: true });
for (const name of [
  "manifest.json",
  "manifest.json.sig",
  "revocations.json",
  "revocations.json.sig",
]) {
  await cp(`../models/${name}`, `resources/${name}`);
}
await cp("../LICENSE", "resources/LICENSE");
await cp("../Vendor/whisper.cpp/LICENSE", "resources/WHISPER-LICENSE");
await mkdir("resources/licenses", { recursive: true });
await cp("THIRD_PARTY_NOTICES.md", "resources/THIRD_PARTY_NOTICES.md");
await cp("licenses", "resources/licenses", { recursive: true });
for (const name of [
  "OpenAI-Whisper.txt",
  "ggml-small.en-q5_1.LICENSES.txt",
  "transcribe.cpp.txt",
  "audio.cpp.txt",
  "Confucius4-R2T2.txt",
]) {
  await cp(`../THIRD_PARTY_LICENSES/${name}`, `resources/licenses/${name}`);
}
for (const name of [
  "react",
  "react-dom",
  "uiohook-napi",
  "@deltachat/dbus-next",
]) {
  await cp(
    `node_modules/${name}/LICENSE`,
    `resources/licenses/${name.replaceAll("/", "-")}.txt`,
  );
}
// Ship the exact installed hook sources so its native module can be rebuilt.
for (const name of ["src", "libuiohook", "binding.gyp", "package.json"]) {
  await cp(
    `node_modules/uiohook-napi/${name}`,
    `resources/native-source/uiohook-napi/${name}`,
    { recursive: true },
  );
}
await cp(
  "assets/textify-icon.png",
  "resources/icon.png",
);
await Promise.all([
  build({
    entryPoints: ["src/main/index.ts"],
    bundle: true,
    platform: "node",
    format: "cjs",
    target: "node22",
    external: ["electron", "uiohook-napi", "@deltachat/dbus-next"],
    outfile: "dist/main.cjs",
  }),
  build({
    entryPoints: ["src/main/preload.ts"],
    bundle: true,
    platform: "node",
    format: "cjs",
    target: "node22",
    external: ["electron"],
    outfile: "dist/preload.cjs",
  }),
  viteBuild({
    root: resolve("src/renderer"),
    base: "./",
    build: {
      outDir: resolve("dist/renderer"),
      emptyOutDir: true,
      assetsInlineLimit: 0,
    },
  }),
]);
await access("resources/icon.png");
