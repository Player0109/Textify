import { createHash } from "node:crypto";
import { readFile, writeFile, mkdir, rm } from "node:fs/promises";
import { spawnSync } from "node:child_process";
import { resolve } from "node:path";
import { vulkanDevicePolicy } from "./require-gpu.mjs";

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
    // Unlike whisper's ggml, these copies give integrated GPUs their own type.
    const notGPU = `const auto type = ggml_backend_dev_type(ggml_backend_get_device(backend));
        type != GGML_BACKEND_DEVICE_TYPE_GPU && type != GGML_BACKEND_DEVICE_TYPE_IGPU`;
    // This guard also covers direct graph calls, used by Parakeet's decoder.
    await edit(
      `${runtime.ggml}/src/ggml-backend.cpp`,
      "    return backend->iface.graph_compute(backend, cgraph);",
      `    // Textify: never compute model operations on a CPU or host accelerator.
    if (${notGPU}) {
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
      `    if (${notGPU}) return GGML_STATUS_FAILED;
    return backend->iface.graph_plan_compute(backend, plan);`,
    );
    await edit(
      `${runtime.ggml}/src/ggml-vulkan/ggml-vulkan.cpp`,
      ...vulkanDevicePolicy,
    );
    if (runtime.name === "transcribe") {
      // Direct depthwise convolution is not supported by this pinned Metal
      // backend. Use its existing im2col/matmul graphs, including inside blocks.
      // This also avoids the upstream Metal-name check missing the name "MTL".
      await edit(
        "src/arch/parakeet/encoder.cpp",
        'return conf::resolve_conv_direct("TRANSCRIBE_CONV_DIRECT_DW", "TRANSCRIBE_CONV_NO_DIRECT_DW",\n                                     /*backend_default=*/true);',
        "return false; // Textify: keep depthwise convolution on the GPU.",
      );
      await edit(
        "src/arch/parakeet/encoder.cpp",
        `    const bool is_metal =
        backend != nullptr && (std::strstr(backend, "Metal") != nullptr || std::strstr(backend, "metal") != nullptr);
    return conf::resolve_conv_direct("TRANSCRIBE_CONV_DIRECT_DW", "TRANSCRIBE_CONV_NO_DIRECT_DW",
                                     /*backend_default=*/!is_metal);`,
        "    (void) backend;\n    return false; // Textify: keep depthwise convolution on the GPU.",
      );
      // Upstream uses ggml graphs for the entire TDT decoder, but explicitly
      // allocates three CPU backends. Keep those same graphs on the GPU the
      // encoder uses: a discrete GPU first, then an integrated one.
      await edit(
        "src/arch/parakeet/decoder.cpp",
        "ggml_backend_init_by_type(GGML_BACKEND_DEVICE_TYPE_CPU, nullptr)",
        "ggml_backend_init_best()",
        3,
      );
    } else {
      // Keep each ggml copy in its own executable, with no loose dylibs.
      await edit(
        "CMakeLists.txt",
        "add_library(audiocpp SHARED src/capi/audiocpp.cpp)",
        "add_library(audiocpp STATIC src/capi/audiocpp.cpp)",
      );
      // Linked statically, so the worker must not import these functions from
      // a DLL on Windows.
      await edit(
        "CMakeLists.txt",
        `        # Anything linking this gets __declspec(dllimport) on Windows without
        # having to know to ask for it. No effect elsewhere.
        INTERFACE
            AUDIOCPP_USE_DLL
`,
        "",
      );
    }
    const ggml =
      runtime.name === "transcribe"
        ? "\nadd_subdirectory(ggml)\n"
        : 'add_subdirectory("${AUDIOCPP_GGML_SOURCE_DIR}" "${CMAKE_CURRENT_BINARY_DIR}/ggml")';
    await edit(
      "CMakeLists.txt",
      ggml,
      "\nif(GGML_METAL)\n  enable_language(OBJC OBJCXX)\nendif()\n" + ggml,
    );
    const target = runtime.name === "transcribe" ? "transcribe" : "audiocpp";
    const native = resolve("native").replaceAll("\\", "/");
    const cmake = `${root}/CMakeLists.txt`;
    await writeFile(
      cmake,
      (await readFile(cmake, "utf8")) +
        `
# Textify isolated GPU worker; source archives are immutable and checksum-pinned.
add_executable(textify-${runtime.name} "${native}/${runtime.name}-worker.cpp")
target_include_directories(textify-${runtime.name} PRIVATE "\${CMAKE_SOURCE_DIR}/include")
target_link_libraries(textify-${runtime.name} PRIVATE ${target} ggml)
add_executable(textify-gpu-policy-test "${native}/extra-gpu-policy-test.cpp")
target_link_libraries(textify-gpu-policy-test PRIVATE ggml)
if(GGML_METAL)
  set_source_files_properties("${native}/${runtime.name}-worker.cpp" PROPERTIES LANGUAGE OBJCXX)
  target_compile_definitions(textify-${runtime.name} PRIVATE TEXTIFY_METAL)
  target_compile_options(textify-${runtime.name} PRIVATE -fobjc-arc)
  target_link_libraries(textify-${runtime.name} PRIVATE "-framework Metal")
endif()
if(WIN32)
  # Check the system driver loader before using Vulkan; a missing DLL must
  # produce a structured GPU error, not a Windows startup-error dialog.
  foreach(exe textify-${runtime.name} textify-gpu-policy-test)
    target_link_libraries(\${exe} PRIVATE delayimp)
    target_link_options(\${exe} PRIVATE "/DELAYLOAD:vulkan-1.dll")
  endforeach()
  # A UTF-8 process code page lets both libraries open non-ASCII model paths.
  target_sources(textify-${runtime.name} PRIVATE "${native}/utf8.manifest")
endif()
enable_testing()
add_test(NAME gpu-required COMMAND textify-gpu-policy-test)
`,
    );
    console.log(
      `Verified and GPU-constrained ${runtime.name} ${runtime.revision}`,
    );
  }
}
