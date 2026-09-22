#include "model-protocol.h"
#include "audiocpp.h"

int main(int argc, char **argv) {
    if (argc != 3 || !textify::configuration()) return 2;
    const std::string language = argv[2];
    if (language != "en" && language != "zh") return 2;
    ggml_log_set(textify::quiet, nullptr);
    auto device = textify::metal();
    if (!device) return textify::failure("gpu_unavailable");
    audiocpp_registry *registry = nullptr;
    audiocpp_model *model = nullptr;
    audiocpp_session *session = nullptr;
    auto cleanup = [&] {
        if (session) audiocpp_session_free(session);
        if (model) audiocpp_model_free(model);
        if (registry) audiocpp_registry_free(registry);
    };
    audiocpp_model_config config = {};
    config.family_hint = "confucius4_r2t2";
    audiocpp_backend_config backend = {};
    backend.backend = "metal";
    backend.threads = 4;
    if (audiocpp_registry_create(nullptr, &registry) != AUDIOCPP_OK ||
        audiocpp_model_load(registry, argv[1], &config, nullptr, &model) != AUDIOCPP_OK ||
        audiocpp_session_create(model, "asr", "offline", &backend, nullptr, &session) != AUDIOCPP_OK) {
        cleanup(); return textify::failure("gpu_model_load");
    }
    textify::ready(device);
    std::vector<float> samples;
    while (textify::audio(samples)) {
        auto request = audiocpp_request_create();
        audiocpp_result *result = nullptr;
        bool ok = request &&
            audiocpp_request_set_text(request, "", language == "en" ? "English" : "Chinese") == AUDIOCPP_OK &&
            audiocpp_request_set_audio(request, samples.data(), samples.size(), 16000, 1) == AUDIOCPP_OK &&
            audiocpp_session_run(session, request, &result) == AUDIOCPP_OK;
        std::fill(samples.begin(), samples.end(), 0);
        if (request) audiocpp_request_free(request);
        const char *text = nullptr;
        if (ok && result) {
            const auto status = audiocpp_result_text(result, &text, nullptr);
            ok = status == AUDIOCPP_OK || status == AUDIOCPP_ERR_NOT_AVAILABLE;
        } else ok = false;
        if (ok) std::cout << "{\"text\":" << textify::json(text ? text : "") << "}\n" << std::flush;
        if (result) audiocpp_result_free(result);
        if (!ok) { cleanup(); return textify::failure("gpu_inference"); }
    }
    cleanup();
}
