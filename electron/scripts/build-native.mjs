import { spawnSync } from "node:child_process";
import { cp, mkdir, writeFile } from "node:fs/promises";
const run = (args) => {
  const result = spawnSync("cmake", args, { stdio: "inherit", shell: false });
  if (result.status !== 0) process.exit(result.status ?? 1);
};
run([
  "-S",
  "native",
  "-B",
  ".native/build",
  "-DCMAKE_BUILD_TYPE=Release",
  "-DBUILD_SHARED_LIBS=OFF",
  "-DGGML_NATIVE=OFF",
  ...(process.platform === "darwin"
    ? ["-DCMAKE_OSX_DEPLOYMENT_TARGET=14.0"]
    : []),
]);
run(["--build", ".native/build", "--config", "Release", "--parallel", "4"]);
await mkdir("resources", { recursive: true });
const suffix = process.platform === "win32" ? ".exe" : "";
const subdir = process.platform === "win32" ? "Release/" : "";
for (const name of ["textify-whisper", "textify-platform"]) {
  await cp(
    `.native/build/${subdir}${name}${suffix}`,
    `resources/${name}${suffix}`,
  );
}
await writeFile(
  "resources/native-build.json",
  JSON.stringify({
    platform: process.platform,
    arch: process.arch,
    whisperRevision: "a8d002cfd879315632a579e73f0148d06959de36",
  }),
);
