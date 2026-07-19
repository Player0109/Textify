#include "TextifyWhisperShim.h"
#include "TextifyWhisperVendor.h"

#include <algorithm>
#include <cmath>
#include <compression.h>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>

struct TextifyWhisperContext {
    whisper_context *context;
    std::string lastText;
    std::string lastError;
    int32_t threadCount;
    float lastNoSpeechProbability;
    float lastAverageLogProbability;
    float lastCompressionRatio;
};

static std::mutex textify_whisper_global_error_mutex;
static std::string textify_whisper_global_error;

static const char *textify_whisper_set_global_error(const std::string &message) {
    std::lock_guard<std::mutex> lock(textify_whisper_global_error_mutex);
    textify_whisper_global_error = message;
    return textify_whisper_global_error.c_str();
}

static const char *textify_whisper_get_global_error(void) {
    std::lock_guard<std::mutex> lock(textify_whisper_global_error_mutex);
    return textify_whisper_global_error.c_str();
}

static int32_t textify_whisper_effective_thread_count(int32_t thread_count) {
    return std::max<int32_t>(1, thread_count);
}

static const char *textify_whisper_effective_language(const char *language) {
    if (language == nullptr || std::strlen(language) == 0) {
        return "en";
    }

    return language;
}

static float textify_whisper_compression_ratio(const std::string &text) {
    if (text.empty()) {
        return 0.0f;
    }

    std::vector<uint8_t> compressed(text.size() + 64);
    const size_t compressed_size = compression_encode_buffer(
        compressed.data(),
        compressed.size(),
        reinterpret_cast<const uint8_t *>(text.data()),
        text.size(),
        nullptr,
        COMPRESSION_ZLIB
    );
    if (compressed_size == 0) {
        return 0.0f;
    }

    return static_cast<float>(text.size()) / static_cast<float>(compressed_size);
}

TextifyWhisperContext *textify_whisper_load(const char *model_path, int32_t use_gpu, int32_t thread_count) {
    if (model_path == nullptr || std::strlen(model_path) == 0) {
        textify_whisper_set_global_error("model path is empty");
        return nullptr;
    }

    whisper_context_params params = whisper_context_default_params();
    params.use_gpu = use_gpu != 0;
    params.flash_attn = false;
    params.gpu_device = 0;

    whisper_context *native_context = whisper_init_from_file_with_params(model_path, params);
    if (native_context == nullptr) {
        std::string message = "failed to load model at ";
        message += model_path;
        textify_whisper_set_global_error(message);
        return nullptr;
    }

    TextifyWhisperContext *context = new TextifyWhisperContext;
    context->context = native_context;
    context->lastText = "";
    context->lastError = "";
    context->threadCount = textify_whisper_effective_thread_count(thread_count);
    context->lastNoSpeechProbability = 0.0f;
    context->lastAverageLogProbability = 0.0f;
    context->lastCompressionRatio = 0.0f;
    textify_whisper_set_global_error("");
    return context;
}

void textify_whisper_free(TextifyWhisperContext *context) {
    if (context == nullptr) {
        return;
    }

    if (context->context != nullptr) {
        whisper_free(context->context);
        context->context = nullptr;
    }

    delete context;
}

int32_t textify_whisper_transcribe(
    TextifyWhisperContext *context,
    const float *pcm_mono_f32_16khz,
    int32_t sample_count,
    const char *language,
    int32_t translate,
    float temperature,
    int32_t no_context,
    const char *initial_prompt
) {
    if (context == nullptr || context->context == nullptr) {
        textify_whisper_set_global_error("native context is not loaded");
        return -1;
    }

    if (pcm_mono_f32_16khz == nullptr || sample_count <= 0) {
        context->lastText = "";
        context->lastError = "audio buffer is empty";
        return -2;
    }

    whisper_full_params params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    params.n_threads = textify_whisper_effective_thread_count(context->threadCount);
    params.translate = translate != 0;
    params.no_context = no_context != 0;
    params.no_timestamps = true;
    params.single_segment = false;
    params.print_special = false;
    params.print_progress = false;
    params.print_realtime = false;
    params.print_timestamps = false;
    params.token_timestamps = false;
    params.language = textify_whisper_effective_language(language);
    params.detect_language = false;
    params.temperature = temperature;
    params.temperature_inc = 0.0f;
    params.initial_prompt = initial_prompt;
    params.greedy.best_of = 1;
    params.beam_search.beam_size = 1;

    const int result = whisper_full(context->context, params, pcm_mono_f32_16khz, sample_count);
    if (result != 0) {
        context->lastText = "";
        context->lastError = "transcription failed";
        return result;
    }

    std::string transcript;
    const int segment_count = whisper_full_n_segments(context->context);
    float no_speech_probability = segment_count == 0 ? 1.0f : 0.0f;
    double log_probability_sum = 0.0;
    int log_probability_count = 0;
    for (int index = 0; index < segment_count; ++index) {
        const char *segment = whisper_full_get_segment_text(context->context, index);
        if (segment != nullptr) {
            transcript += segment;
        }

        no_speech_probability = std::max(
            no_speech_probability,
            whisper_full_get_segment_no_speech_prob(context->context, index)
        );
        const int token_count = whisper_full_n_tokens(context->context, index);
        for (int token_index = 0; token_index < token_count; ++token_index) {
            const whisper_token_data token = whisper_full_get_token_data(
                context->context,
                index,
                token_index
            );
            if (std::isfinite(token.plog)) {
                log_probability_sum += token.plog;
                ++log_probability_count;
            }
        }
    }

    context->lastText = transcript;
    context->lastError = "";
    context->lastNoSpeechProbability = no_speech_probability;
    context->lastAverageLogProbability = log_probability_count > 0
        ? static_cast<float>(log_probability_sum / log_probability_count)
        : 0.0f;
    context->lastCompressionRatio = textify_whisper_compression_ratio(transcript);
    return 0;
}

const char *textify_whisper_last_text(TextifyWhisperContext *context) {
    if (context == nullptr) {
        return "";
    }

    return context->lastText.c_str();
}

const char *textify_whisper_last_error(TextifyWhisperContext *context) {
    if (context == nullptr) {
        return textify_whisper_get_global_error();
    }

    return context->lastError.c_str();
}

float textify_whisper_last_no_speech_probability(TextifyWhisperContext *context) {
    return context == nullptr ? 0.0f : context->lastNoSpeechProbability;
}

float textify_whisper_last_average_log_probability(TextifyWhisperContext *context) {
    return context == nullptr ? 0.0f : context->lastAverageLogProbability;
}

float textify_whisper_last_compression_ratio(TextifyWhisperContext *context) {
    return context == nullptr ? 0.0f : context->lastCompressionRatio;
}

int32_t textify_whisper_uses_gpu(TextifyWhisperContext *context) {
    if (context == nullptr || context->context == nullptr) {
        return 0;
    }
    return whisper_uses_gpu(context->context);
}

int32_t textify_whisper_compiled_with_metal(void) {
#ifdef GGML_USE_METAL
    return 1;
#else
    return 0;
#endif
}

int32_t TEXTIFY_WHISPER_DISABLED_RUNTIME_PROBE(void) {
    return 0;
}
