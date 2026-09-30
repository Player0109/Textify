const { readFile, access } = require("node:fs/promises");
const { join } = require("node:path");
module.exports = async (context) => {
  const resources = join(context.packager.projectDir, "resources");
  const native = JSON.parse(
    await readFile(join(resources, "native-build.json"), "utf8"),
  );
  const architecture = {
    0: "ia32",
    1: "x64",
    2: "arm",
    3: "arm64",
    4: "universal",
  }[context.arch];
  if (
    native.platform !== context.electronPlatformName ||
    native.arch !== architecture ||
    native.gpuRequired !== true ||
    native.backend !== (native.platform === "darwin" ? "Metal" : "Vulkan")
  )
    throw new Error(
      "Build native helpers on the target OS/architecture before packaging. Cross-packaging host binaries is prohibited.",
    );
  if (native.extraWorkers !== true)
    throw new Error("Rebuild the additional GPU workers before packaging.");
  const suffix = native.platform === "win32" ? ".exe" : "";
  await access(join(resources, `textify-transcribe${suffix}`));
  await access(join(resources, `textify-audio${suffix}`));
  await access(join(resources, `textify-whisper${suffix}`));
  await access(join(resources, `textify-platform${suffix}`));
};
