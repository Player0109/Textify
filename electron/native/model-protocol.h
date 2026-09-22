#pragma once
#include "ggml-backend.h"
#import <Metal/Metal.h>
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <string>
#include <vector>

namespace textify {
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
inline int failure(const char *code) {
    std::cout << "{\"error\":" << json(code) << "}\n" << std::flush;
    return 1;
}
inline uint32_t count() {
    unsigned char h[4];
    if (!std::cin.read(reinterpret_cast<char *>(h), 4)) return 0;
    return uint32_t(h[0]) | uint32_t(h[1]) << 8 | uint32_t(h[2]) << 16 | uint32_t(h[3]) << 24;
}
inline bool configuration() {
    const auto n = count();
    if (!std::cin || n > 8192) return false;
    std::string prompt(n, '\0');
    if (n) std::cin.read(prompt.data(), n);
    // These signed artifacts do not support vocabulary prompting.
    return bool(std::cin);
}
inline ggml_backend_dev_t metal() {
    @autoreleasepool {
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        if (!device || ![device supportsFamily:MTLGPUFamilyApple7]) return nullptr;
    }
    for (size_t i = 0; i < ggml_backend_dev_count(); ++i) {
        auto d = ggml_backend_dev_get(i);
        if (ggml_backend_dev_type(d) == GGML_BACKEND_DEVICE_TYPE_GPU &&
            std::strcmp(ggml_backend_reg_name(ggml_backend_dev_backend_reg(d)), "MTL") == 0) return d;
    }
    return nullptr;
}
inline void ready(ggml_backend_dev_t device) {
    std::cout << "{\"ready\":true,\"gpu\":{\"backend\":\"Metal\",\"device\":"
              << json(ggml_backend_dev_description(device)) << "}}\n" << std::flush;
}
inline bool audio(std::vector<float> &samples) {
    const auto n = count();
    if (!n || n > 480000) return false;
    samples.resize(n);
    if (!std::cin.read(reinterpret_cast<char *>(samples.data()), n * sizeof(float))) return false;
    return std::all_of(samples.begin(), samples.end(), [](float x) { return std::isfinite(x) && std::abs(x) <= 1; });
}
inline void quiet(ggml_log_level, const char *, void *) {}
}
