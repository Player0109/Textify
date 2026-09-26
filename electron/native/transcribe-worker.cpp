#include "model-protocol.h"
#include "transcribe.h"

int main(int argc, char **argv) {
    if (argc != 3 || !textify::configuration()) return 2;
    ggml_log_set(textify::quiet, nullptr);
    transcribe_log_set([](transcribe_log_level, const char *, void *) {}, nullptr);
    textify::gpu_device gpu;
    try { gpu = textify::gpu(); } catch (...) { return textify::failure("gpu_init"); }
    if (!gpu.handle) return textify::failure("gpu_unavailable");
    transcribe_model_load_params load;
    transcribe_model_load_params_init(&load);
    load.backend = textify::metal ? TRANSCRIBE_BACKEND_METAL : TRANSCRIBE_BACKEND_VULKAN;
    transcribe_session_params session;
    transcribe_session_params_init(&session);
    session.n_threads = 4;
    session.n_ctx = 4096;
    transcribe_session *context = nullptr;
    if (transcribe_open(argv[1], &load, &session, &context) != TRANSCRIBE_OK) return textify::failure("gpu_model_load");
    textify::ready(gpu.handle);
    transcribe_run_params params;
    transcribe_run_params_init(&params);
    params.task = TRANSCRIBE_TASK_TRANSCRIBE;
    params.timestamps = TRANSCRIBE_TIMESTAMPS_NONE;
    params.language = std::strcmp(argv[2], "auto") == 0 ? nullptr : argv[2];
    std::vector<float> samples;
    while (textify::audio(samples)) {
        auto status = transcribe_run(context, samples.data(), int(samples.size()), &params);
        std::fill(samples.begin(), samples.end(), 0);
        if (status != TRANSCRIBE_OK) { transcribe_close(context); return textify::failure("gpu_inference"); }
        std::cout << "{\"text\":" << textify::json(transcribe_full_text(context)) << "}\n" << std::flush;
    }
    transcribe_close(context);
}
