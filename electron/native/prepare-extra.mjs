import { createHash } from "node:crypto";
import { readFile, writeFile, mkdir, rm } from "node:fs/promises";
import { spawnSync } from "node:child_process";
import { resolve } from "node:path";

export const extraRuntimes = [
  {
    name: "transcribe",
    repo: "handy-computer/transcribe.cpp",
    revision: "5a5a49664a8ea1f0e5b3be1dfc544730d1b62561",
    sha256: "ab31ec19545fbf94fe11898f02946813de33706895898df34df096aa955949b0",
    ggml: "ggml",
  },
  {
    name: "audio",
    repo: "0xShug0/audio.cpp",
    revision: "9ba884179826c3b33dd305185b5f94c79175a03d",
    sha256: "4fbc3a5f784c1035415c7bf8ee3ad74df80940c61e1ecb1cfc246ace9ed123bb",
    ggml: "external/ggml",
  },
];
export async function prepareExtra() {
  if (process.platform !== "darwin") return;
  for (const runtime of extraRuntimes) {
    const root = `.native/${runtime.name}`;
    let archive;
    try {
      archive = await readFile(`${root}.tar.gz`);
    } catch {
      const response = await fetch(
        `https://codeload.github.com/${runtime.repo}/tar.gz/${runtime.revision}`,
      );
      if (!response.ok) throw new Error(`${runtime.name} download failed`);
      archive = Buffer.from(await response.arrayBuffer());
    }
    if (createHash("sha256").update(archive).digest("hex") !== runtime.sha256)
      throw new Error(`${runtime.name} checksum mismatch`);
    await writeFile(`${root}.tar.gz`, archive);
    await rm(root, { recursive: true, force: true });
    await mkdir(root, { recursive: true });
    if (
      spawnSync("tar", [
        "-xzf",
        `${root}.tar.gz`,
        "-C",
        root,
        "--strip-components=1",
      ]).status !== 0
    )
      throw new Error("extract failed");
    async function edit(path, before, after, count = 1) {
      const file = `${root}/${path}`;
      const source = (await readFile(file, "utf8")).replaceAll("\r\n", "\n");
      if (source.split(before).length !== count + 1)
        throw new Error(`Pinned GPU patch mismatch: ${file}`);
      await writeFile(file, source.replaceAll(before, after));
    }
    // This guard also covers direct graph calls, used by Parakeet's decoder.
    await edit(
      `${runtime.ggml}/src/ggml-backend.cpp`,
      "    return backend->iface.graph_compute(backend, cgraph);",
      `    // Textify: never compute model operations on a CPU or host accelerator.
    if (ggml_backend_dev_type(ggml_backend_get_device(backend)) != GGML_BACKEND_DEVICE_TYPE_GPU) {
        for (int n = 0; n < cgraph->n_nodes; ++n) {
            const auto op = cgraph->nodes[n]->op;
            if (op != GGML_OP_NONE && op != GGML_OP_RESHAPE && op != GGML_OP_VIEW &&
                op != GGML_OP_PERMUTE && op != GGML_OP_TRANSPOSE) return GGML_STATUS_FAILED;
        }
    }
    return backend->iface.graph_compute(backend, cgraph);`,
    );
    await edit(
      `${runtime.ggml}/src/ggml-backend.cpp`,
      "    return backend->iface.graph_plan_compute(backend, plan);",
      `    if (ggml_backend_dev_type(ggml_backend_get_device(backend)) != GGML_BACKEND_DEVICE_TYPE_GPU) return GGML_STATUS_FAILED;
    return backend->iface.graph_plan_compute(backend, plan);`,
    );
    if (runtime.name === "transcribe") {
      // Upstream uses ggml graphs for the entire TDT decoder, but explicitly
      // allocates three CPU backends. Keep those same graphs on the Metal GPU.
      await edit(
        "src/arch/parakeet/decoder.cpp",
        "ggml_backend_init_by_type(GGML_BACKEND_DEVICE_TYPE_CPU, nullptr)",
        "ggml_backend_init_by_type(GGML_BACKEND_DEVICE_TYPE_GPU, nullptr)",
        3,
      );
    } else {
      // Keep each ggml copy in its own executable, with no loose dylibs.
      await edit(
        "CMakeLists.txt",
        "add_library(audiocpp SHARED src/capi/audiocpp.cpp)",
        "add_library(audiocpp STATIC src/capi/audiocpp.cpp)",
      );
    }
    await edit(
      "CMakeLists.txt",
      runtime.name === "transcribe"
        ? "\nadd_subdirectory(ggml)\n"
        : 'add_subdirectory("${AUDIOCPP_GGML_SOURCE_DIR}" "${CMAKE_CURRENT_BINARY_DIR}/ggml")',
      "\nenable_language(OBJC OBJCXX)\n" +
        (runtime.name === "transcribe"
          ? "\nadd_subdirectory(ggml)\n"
          : 'add_subdirectory("${AUDIOCPP_GGML_SOURCE_DIR}" "${CMAKE_CURRENT_BINARY_DIR}/ggml")'),
    );
    const target = runtime.name === "transcribe" ? "transcribe" : "audiocpp";
    const native = resolve("native").replaceAll("\\", "/");
    const cmake = `${root}/CMakeLists.txt`;
    await writeFile(
      cmake,
      (await readFile(cmake, "utf8")) +
        `
# Textify isolated GPU worker; source archives are immutable and checksum-pinned.
enable_language(OBJCXX)
add_executable(textify-${runtime.name} "${native}/${runtime.name}-worker.mm")
target_include_directories(textify-${runtime.name} PRIVATE "\${CMAKE_SOURCE_DIR}/include")
target_compile_options(textify-${runtime.name} PRIVATE -fobjc-arc)
target_link_libraries(textify-${runtime.name} PRIVATE ${target} ggml "-framework Metal")
add_executable(textify-gpu-policy-test "${native}/extra-gpu-policy-test.cpp")
target_link_libraries(textify-gpu-policy-test PRIVATE ggml)
enable_testing()
add_test(NAME gpu-required COMMAND textify-gpu-policy-test)
`,
    );
    console.log(
      `Verified and GPU-constrained ${runtime.name} ${runtime.revision}`,
    );
  }
}
