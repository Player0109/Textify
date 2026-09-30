#pragma once
#include "ggml-backend.h"
#ifdef TEXTIFY_METAL
#import <Metal/Metal.h>
#endif
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <fcntl.h>
#include <io.h>
#endif
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <string>
#include <vector>

namespace textify {
#ifdef TEXTIFY_METAL
constexpr bool metal = true;
#else
constexpr bool metal = false;
#endif
inline std::string json(const std::string &value) {
    std::string out = "\"";
    for (unsigned char c : value) {
        if (c == '"' || c == '\\') { out += '\\'; out += c; }
        else if (c == '\n') out += "\\n";
        else if (c == '\r') out += "\\r";
        else if (c == '\t') out += "\\t";
        else if (c >= 32) out += c;
    }
    return out + '"';
}
// ggml-vulkan reports a failed device allocation only on std::cerr, after
// trying every memory type. Pass the text through and remember that fact.
class memory_watch : public std::streambuf {
    std::streambuf *out = std::cerr.rdbuf(this);
    std::string line;
  public:
    bool exhausted = false;
  protected:
    int overflow(int c) override {
        if (c == traits_type::eof()) return traits_type::not_eof(c);
        if (c != '\n') { if (line.size() < 256) line += char(c); }
        else { exhausted |= line.find("allocation of size") != std::string::npos; line.clear(); }
        return out->sputc(char(c));
    }
    int sync() override { return out->pubsync(); }
};
inline memory_watch &memory() { static memory_watch watch; return watch; }
inline int failure(const char *code) {
    if (memory().exhausted && (std::strcmp(code, "gpu_model_load") == 0 || std::strcmp(code, "gpu_inference") == 0))
        code = "gpu_memory";
    std::cout << "{\"error\":" << json(code) << "}\n" << std::flush;
    return 1;
}
inline uint32_t count() {
    unsigned char h[4];
    if (!std::cin.read(reinterpret_cast<char *>(h), 4)) return 0;
    return uint32_t(h[0]) | uint32_t(h[1]) << 8 | uint32_t(h[2]) << 16 | uint32_t(h[3]) << 24;
}
inline bool configuration() {
#ifdef _WIN32
    _setmode(_fileno(stdin), _O_BINARY);
    _setmode(_fileno(stdout), _O_BINARY);
#endif
    memory(); // Watch std::cerr before any model code runs.
    const auto n = count();
    if (!std::cin || n > 8192) return false;
    std::string prompt(n, '\0');
    if (n) std::cin.read(prompt.data(), n);
    // These signed artifacts do not support vocabulary prompting.
    return bool(std::cin);
}
struct gpu_device {
    ggml_backend_dev_t handle = nullptr;
    int index = 0; // Position within its backend, as audio.cpp selects devices.
};
// A discrete GPU is preferred over an integrated one, matching transcribe.cpp
// and ggml_backend_init_best(). These ggml copies type integrated GPUs as IGPU.
inline gpu_device gpu() {
#ifdef _WIN32
    if (!LoadLibraryExW(L"vulkan-1.dll", nullptr, LOAD_LIBRARY_SEARCH_SYSTEM32)) return {};
#endif
#ifdef TEXTIFY_METAL
    @autoreleasepool {
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        if (!device || ![device supportsFamily:MTLGPUFamilyApple7]) return {};
    }
    const char *required = "MTL";
#else
    const char *required = "Vulkan";
#endif
    for (auto type : {GGML_BACKEND_DEVICE_TYPE_GPU, GGML_BACKEND_DEVICE_TYPE_IGPU}) {
        for (size_t r = 0; r < ggml_backend_reg_count(); ++r) {
            auto reg = ggml_backend_reg_get(r);
            if (std::strcmp(ggml_backend_reg_name(reg), required) != 0) continue;
            for (size_t i = 0; i < ggml_backend_reg_dev_count(reg); ++i) {
                auto d = ggml_backend_reg_dev_get(reg, i);
                if (ggml_backend_dev_type(d) == type) return {d, int(i)};
            }
        }
    }
    return {};
}
inline void ready(ggml_backend_dev_t device, bool streaming = false) {
    std::cout << "{\"ready\":true,\"gpu\":{\"backend\":\"" << (metal ? "Metal" : "Vulkan") << "\",\"device\":"
              << json(ggml_backend_dev_description(device)) << "},\"streaming\":"
              << (streaming ? "true" : "false") << "}\n" << std::flush;
}
inline bool audio(std::vector<float> &samples, uint32_t n) {
    if (!n || n > 480000) return false;
    samples.resize(n);
    if (!std::cin.read(reinterpret_cast<char *>(samples.data()), n * sizeof(float))) return false;
    return std::all_of(samples.begin(), samples.end(), [](float x) { return std::isfinite(x) && std::abs(x) <= 1; });
}
inline bool audio(std::vector<float> &samples) { return audio(samples, count()); }
inline void quiet(ggml_log_level, const char *, void *) {}
}
