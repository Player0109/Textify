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
    audiocpp_session *stream = nullptr;
    auto cleanup = [&] {
        if (stream) audiocpp_session_free(stream);
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
    auto options = audiocpp_options_create();
    bool configured = options &&
        audiocpp_model_supports(model, "asr", "streaming") &&
        audiocpp_options_set(options, "confucius4_r2t2.chunk_size_ms", "320") == AUDIOCPP_OK &&
        audiocpp_options_set(options, "confucius4_r2t2.unfixed_chunk_num", "0") == AUDIOCPP_OK &&
        audiocpp_options_set(options, "confucius4_r2t2.unfixed_token_num", "1") == AUDIOCPP_OK &&
        audiocpp_session_create(model, "asr", "streaming", &backend, options, &stream) == AUDIOCPP_OK;
    if (options) audiocpp_options_free(options);
    if (!configured) { cleanup(); return textify::failure("gpu_model_load"); }
    textify::ready(device, true);
    // Commands occupy values outside the valid PCM frame-count range. Streaming
    // audio has the high bit set; ordinary counts retain the offline protocol.
    constexpr uint32_t start = 0xffffffff, reset = 0xfffffffe, finish = 0xfffffffd, push = 0x80000000;
    bool streaming = false;
    size_t offset = 0;
    std::vector<float> samples;
    while (const auto command = textify::count()) {
        if (command == finish) {
            audiocpp_result *result = nullptr;
            const char *text = nullptr;
            bool ok = streaming && audiocpp_stream_finish(stream, &result) == AUDIOCPP_OK && result;
            if (ok) {
                const auto status = audiocpp_result_text(result, &text, nullptr);
                ok = status == AUDIOCPP_OK || status == AUDIOCPP_ERR_NOT_AVAILABLE;
            }
            if (ok) std::cout << "{\"text\":" << textify::json(text ? text : "") << "}\n" << std::flush;
            if (result) audiocpp_result_free(result);
            if (!ok) { cleanup(); return textify::failure("gpu_inference"); }
            continue;
        }
        if (command == reset) {
            if (audiocpp_stream_reset(stream) != AUDIOCPP_OK) {
                cleanup(); return textify::failure("gpu_inference");
            }
            streaming = false; offset = 0;
            std::cout << "{\"stream\":\"reset\"}\n" << std::flush;
            continue;
        }
        if (command == start) {
            auto request = audiocpp_request_create();
            bool ok = !streaming && request &&
                audiocpp_request_set_text(request, "", language == "en" ? "English" : "Chinese") == AUDIOCPP_OK &&
                audiocpp_request_set_audio(request, nullptr, 0, 16000, 1) == AUDIOCPP_OK &&
                audiocpp_stream_start(stream, request) == AUDIOCPP_OK;
            if (request) audiocpp_request_free(request);
            if (!ok) { cleanup(); return textify::failure("gpu_inference"); }
            streaming = true; offset = 0;
            std::cout << "{\"stream\":\"started\"}\n" << std::flush;
            continue;
        }
        const bool preview = (command & push) != 0;
        const auto n = command & ~push;
        // A preview window is bounded to 25 seconds, as in the native app.
        if (!textify::audio(samples, n) || (preview && (!streaming || offset + n > 400000)) ||
            (!preview && streaming)) {
            cleanup(); return textify::failure("worker_protocol");
        }
        if (preview) {
            audiocpp_event *event = nullptr;
            bool ok = audiocpp_stream_push(stream, samples.data(), samples.size(), 16000, 1, offset, &event) == AUDIOCPP_OK;
            offset += samples.size();
            std::fill(samples.begin(), samples.end(), 0);
            const char *text = nullptr;
            if (ok && event) {
                const auto result = audiocpp_event_as_result(event);
                const auto status = result ? audiocpp_result_text(result, &text, nullptr) : AUDIOCPP_ERR_NOT_AVAILABLE;
                ok = status == AUDIOCPP_OK || status == AUDIOCPP_ERR_NOT_AVAILABLE;
            }
            if (ok) std::cout << "{\"text\":" << textify::json(text ? text : "") << "}\n" << std::flush;
            if (event) audiocpp_event_free(event);
            if (!ok) { cleanup(); return textify::failure("gpu_inference"); }
            continue;
        }
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
