#include "whisper.h"
#include "ggml-backend.h"
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <iostream>
#include <string>
#include <thread>
#include <vector>
#include <cstring>
#ifdef __APPLE__
#import <Metal/Metal.h>
#endif
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <fcntl.h>
#include <io.h>
#endif

// PCM enters through stdin and results leave through stdout. Neither is logged.
static void quiet(ggml_log_level, const char *, void *) {}
static std::string json_string(const std::string &value) {
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
static int failure(const char *code) {
    std::cout << "{\"error\":" << json_string(code) << "}\n" << std::flush;
    return 1;
}
static ggml_backend_dev_t gpu() {
#ifdef _WIN32
    if (!LoadLibraryExW(L"vulkan-1.dll", nullptr, LOAD_LIBRARY_SEARCH_SYSTEM32)) return nullptr;
#endif
#ifdef __APPLE__
    // The pinned kernels need Apple7 SIMD-group support (M1 or newer).
    // A paravirtual Metal device can exist without these compute features.
    @autoreleasepool {
        id<MTLDevice> metal = MTLCreateSystemDefaultDevice();
        if (!metal || ![metal supportsFamily:MTLGPUFamilyApple7]) return nullptr;
    }
    const char *required = "Metal";
#else
    const char *required = "Vulkan";
#endif
    for (size_t i = 0; i < ggml_backend_dev_count(); ++i) {
        auto dev = ggml_backend_dev_get(i);
        if (ggml_backend_dev_type(dev) == GGML_BACKEND_DEVICE_TYPE_GPU &&
            std::strcmp(ggml_backend_reg_name(ggml_backend_dev_backend_reg(dev)), required) == 0) return dev;
    }
    return nullptr;
}
static int run(const std::string &model_path, const std::string &language, bool configured) {
#ifdef _WIN32
    _setmode(_fileno(stdin), _O_BINARY);
    _setmode(_fileno(stdout), _O_BINARY);
#endif
    std::string prompt;
    if (configured) {
        unsigned char header[4];
        if (!std::cin.read(reinterpret_cast<char *>(header), 4)) return 2;
        const uint32_t size = uint32_t(header[0]) | uint32_t(header[1]) << 8 | uint32_t(header[2]) << 16 | uint32_t(header[3]) << 24;
        if (size > 8192) return 2;
        prompt.resize(size);
        if (size && !std::cin.read(prompt.data(), size)) return 2;
    }
    if (whisper_lang_id(language.c_str()) < 0) return 2;
    whisper_log_set(quiet, nullptr);
    ggml_log_set(quiet, nullptr);
    ggml_backend_dev_t device;
    try { device = gpu(); } catch (...) { return failure("gpu_init"); }
    if (!device) return failure("gpu_unavailable");
    const std::string info = "{\"backend\":" + json_string(ggml_backend_reg_name(ggml_backend_dev_backend_reg(device))) +
        ",\"device\":" + json_string(ggml_backend_dev_description(device)) + "}";
    auto config = whisper_context_default_params();
    config.use_gpu = true;
    whisper_context *context;
    try { context = whisper_init_from_file_with_params(model_path.c_str(), config); }
    catch (...) { return failure("gpu_model_load"); }
    if (!context) return failure("gpu_model_load");
    if (language != "en" && !whisper_is_multilingual(context)) { whisper_free(context); std::cout << "{\"error\":\"model_language\"}\n" << std::flush; return 1; }
    std::cout << "{\"ready\":true,\"gpu\":" << info << "}\n" << std::flush;
    unsigned char header[4];
    while (std::cin.read(reinterpret_cast<char *>(header), 4)) {
        const uint32_t count = uint32_t(header[0]) | uint32_t(header[1]) << 8 |
            uint32_t(header[2]) << 16 | uint32_t(header[3]) << 24;
        if (count == 0 || count > 30 * 16000) break;
        std::vector<float> samples(count);
        if (!std::cin.read(reinterpret_cast<char *>(samples.data()), count * sizeof(float))) break;
        bool valid = std::all_of(samples.begin(), samples.end(), [](float x) { return std::isfinite(x) && std::abs(x) <= 1.0f; });
        if (!valid) break;
        auto params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
        params.n_threads = std::max(1u, std::min(8u, std::thread::hardware_concurrency()));
        params.language = language.c_str();
        params.initial_prompt = prompt.empty() ? nullptr : prompt.c_str();
        params.translate = false;
        params.no_context = true;
        params.temperature = 0.0f;
        params.temperature_inc = 0.0f;
        params.print_progress = params.print_realtime = params.print_timestamps = params.print_special = false;
        if (whisper_full(context, params, samples.data(), int(count)) != 0) {
            std::fill(samples.begin(), samples.end(), 0);
            whisper_free(context);
            return failure("gpu_inference");
        }
        std::string text;
        double log_probability = 0, no_speech = 0;
        int token_count = 0;
        const int segments = whisper_full_n_segments(context);
        for (int s = 0; s < segments; ++s) {
            text += whisper_full_get_segment_text(context, s);
            no_speech = std::max(no_speech, double(whisper_full_get_segment_no_speech_prob(context, s)));
            for (int t = 0; t < whisper_full_n_tokens(context, s); ++t) {
                const auto token = whisper_full_get_token_data(context, s, t);
                if (token.id < whisper_token_eot(context)) { log_probability += token.plog; ++token_count; }
            }
        }
        std::fill(samples.begin(), samples.end(), 0);
        std::cout << "{\"text\":" << json_string(text)
            << ",\"noSpeechProbability\":" << no_speech
            << ",\"averageLogProbability\":" << (token_count ? log_probability / token_count : -100)
            << "}\n" << std::flush;
    }
    whisper_free(context);
    return 0;
}
#ifdef _WIN32
int wmain(int argc, wchar_t **argv) {
    if (argc != 2 && argc != 3) return 2;
    int size = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, argv[1], -1, nullptr, 0, nullptr, nullptr);
    if (size <= 1) return 2;
    std::string path(size, '\0');
    WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, argv[1], -1, path.data(), size, nullptr, nullptr);
    path.pop_back();
    std::string language = "en";
    if (argc == 3) { language.clear(); for (const wchar_t *ch = argv[2]; *ch; ++ch) { if (*ch < 'a' || *ch > 'z') return 2; language += char(*ch); } }
    return run(path, language, argc == 3);
}
#else
int main(int argc, char **argv) { return (argc == 2 || argc == 3) ? run(argv[1], argc == 3 ? argv[2] : "en", argc == 3) : 2; }
#endif
