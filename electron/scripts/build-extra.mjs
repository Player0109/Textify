import { spawnSync } from "node:child_process";
import { cp, mkdir } from "node:fs/promises";
export async function buildExtra() {
  if (process.platform !== "darwin") return;
  const run = (command, args) => {
    if (spawnSync(command, args, { stdio: "inherit" }).status !== 0)
      throw new Error(`${command} failed`);
  };
  await mkdir("resources/licenses", { recursive: true });
  for (const [source, name] of [
    [".native/transcribe/ggml/LICENSE", "transcribe-ggml.txt"],
    [
      ".native/transcribe/src/third_party/miniz/LICENSE",
      "transcribe-miniz.txt",
    ],
  ])
    await cp(source, `resources/licenses/${name}`);
  for (const name of ["transcribe", "audio"]) {
    const flags =
      name === "transcribe"
        ? [
            "-DTRANSCRIBE_BUILD_TESTS=OFF",
            "-DTRANSCRIBE_BUILD_EXAMPLES=OFF",
            "-DTRANSCRIBE_BUILD_TOOLS=OFF",
            "-DTRANSCRIBE_BUILD_SHARED=OFF",
            "-DTRANSCRIBE_METAL=ON",
          ]
        : [
            "-DAUDIOCPP_MODEL_SET=custom",
            "-DAUDIOCPP_MODELS=confucius4_r2t2",
            "-DAUDIOCPP_BUILD_C_API=ON",
            "-DAUDIOCPP_BUILD_NATIVE_MODEL_MANAGER=OFF",
            "-DAUDIOCPP_BUILD_SERVER_FRONTENDS=OFF",
            "-DENGINE_ENABLE_METAL=ON",
            "-DENGINE_ENABLE_OPENMP=OFF",
            "-DENGINE_ENABLE_NATIVE_CPU=OFF",
          ];
    run("cmake", [
      "-S",
      `.native/${name}`,
      "-B",
      `.native/${name}-build`,
      "-DCMAKE_BUILD_TYPE=Release",
      "-DCMAKE_OSX_DEPLOYMENT_TARGET=14.0",
      "-DGGML_NATIVE=OFF",
      "-DGGML_METAL_EMBED_LIBRARY=ON",
      ...flags,
    ]);
    run("cmake", [
      "--build",
      `.native/${name}-build`,
      "--target",
      `textify-${name}`,
      "textify-gpu-policy-test",
      "--parallel",
      "4",
    ]);
    run("ctest", [
      "--test-dir",
      `.native/${name}-build`,
      "--output-on-failure",
      "-R",
      "^gpu-required$",
    ]);
    await cp(
      `.native/${name}-build/bin/textify-${name}`,
      `resources/textify-${name}`,
    );
  }
}
