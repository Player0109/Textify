#include "TextifyWhisperShim.h"
#include "TextifyWhisperVendor.h"

#include <algorithm>
#include <cmath>
#include <compression.h>
#include <cstddef>
#include <cstring>
#include <exception>
#include <limits>
#include <mutex>
#include <sstream>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

struct TextifyCrisperVocabulary {
    bool enabled = false;
    int32_t vocabularySize = 0;
    whisper_token endOfText = -1;
    whisper_token noSpeech = -1;
    std::vector<whisper_token> decoderPrefix;
    std::unordered_set<int> suppressTokens;
};

struct TextifyWhisperContext {
    whisper_context *context;
    std::string lastText;
    std::string lastError;
    int32_t threadCount;
    float lastNoSpeechProbability;
    float lastAverageLogProbability;
    float lastCompressionRatio;
    TextifyCrisperVocabulary crisper;
};

namespace {

constexpr int32_t kTextifyWhisperSampleRate = 16'000;
constexpr int32_t kTextifyCrisperMaxAudioSamples = 30 * kTextifyWhisperSampleRate;
constexpr int32_t kTextifyCrisperMaxNewTokens = 256;

// Vocabulary-stable portion shared by the pinned Large and Turbo
// generation_config.json suppression policies. Their special-token IDs differ,
// so those are resolved by token text when the model is loaded.
const std::unordered_set<int> kTextifyCrisperBaseSuppressTokens = {
    1, 2, 7, 8, 9, 10, 14, 25, 26, 27, 28, 29, 31, 58, 59, 60, 61, 62,
    63, 90, 91, 92, 93, 359, 503, 522, 542, 873, 893, 902, 918, 922,
    931, 1350, 1853, 1982, 2460, 2627, 3246, 3253, 3268, 3536, 3846,
    3961, 4183, 4667, 6585, 6647, 7273, 9061, 9383, 10428, 10929,
    11938, 12033, 12331, 12562, 13793, 14157, 14635, 15265, 15618,
    16553, 16604, 18362, 18956, 20075, 21675, 22520, 26130, 26161,
    26435, 28279, 29464, 31650, 32302, 32470, 36865, 42863, 47425,
    49870, 50254,
};

// Required vocabulary and Intended prefix ordering follow CrisperWhisper.cpp
// commit 13c7b3efdafd8bd20bd6361e7354ce2aa9bec464.
const char * const kTextifyCrisperControlTokens[] = {
    "[verbatim_1]", "[verbatim_2]", "[verbatim_3]", "[verbatim_4]", "[verbatim_5]",
    "[intended_1]", "[intended_2]", "[intended_3]", "[intended_4]", "[intended_5]",
    "<vtx>", "<evtx>", "<ctx>", "<ectx>", "<htx>", "<ehtx>",
};

} // namespace

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

static void textify_whisper_reset_result(TextifyWhisperContext *context) {
    context->lastText = "";
    context->lastError = "";
    context->lastNoSpeechProbability = 0.0f;
    context->lastAverageLogProbability = 0.0f;
    context->lastCompressionRatio = 0.0f;
}

static int32_t textify_whisper_fail(
    TextifyWhisperContext *context,
    int32_t code,
    const std::string &message
) {
    context->lastText = "";
    context->lastError = message;
    context->lastNoSpeechProbability = 0.0f;
    context->lastAverageLogProbability = 0.0f;
    context->lastCompressionRatio = 0.0f;
    return code;
}

static bool textify_whisper_configure_crisper_vocabulary(
    TextifyWhisperContext *context,
    std::string &error
) {
    const int32_t vocabulary_size = whisper_model_n_vocab(context->context);
    std::unordered_map<std::string, whisper_token> token_ids;
    token_ids.reserve(static_cast<size_t>(vocabulary_size));
    for (int32_t token_id = 0; token_id < vocabulary_size; ++token_id) {
        const char *token = whisper_token_to_str(context->context, token_id);
        if (token != nullptr) {
            token_ids.emplace(token, token_id);
        }
    }

    size_t crisper_token_count = 0;
    std::vector<std::string> missing_crisper_tokens;
    for (const char *token : kTextifyCrisperControlTokens) {
        if (token_ids.count(token) != 0) {
            ++crisper_token_count;
        } else {
            missing_crisper_tokens.emplace_back(token);
        }
    }

    if (crisper_token_count == 0) {
        return true;
    }

    const size_t required_crisper_token_count =
        sizeof(kTextifyCrisperControlTokens) / sizeof(kTextifyCrisperControlTokens[0]);
    if (crisper_token_count != required_crisper_token_count) {
        std::ostringstream message;
        message << "model vocabulary contains a partial CrisperWhisper control-token set; missing";
        for (const std::string &token : missing_crisper_tokens) {
            message << ' ' << token;
        }
        error = message.str();
        return false;
    }

    const auto require_token = [&token_ids, &error](const char *token, whisper_token &result) {
        const auto found = token_ids.find(token);
        if (found == token_ids.end()) {
            error = "model vocabulary is incompatible with CrisperWhisper Intended mode; missing ";
            error += token;
            return false;
        }
        result = found->second;
        return true;
    };

    TextifyCrisperVocabulary crisper;
    crisper.enabled = true;
    crisper.vocabularySize = vocabulary_size;
    crisper.suppressTokens = kTextifyCrisperBaseSuppressTokens;
    crisper.decoderPrefix.reserve(9);
    for (int index = 1; index <= 5; ++index) {
        const std::string token = "[intended_" + std::to_string(index) + "]";
        crisper.decoderPrefix.push_back(token_ids.at(token));
    }

    whisper_token start_of_transcript = -1;
    whisper_token english = -1;
    whisper_token translate = -1;
    whisper_token transcribe = -1;
    whisper_token start_of_lm = -1;
    whisper_token start_of_previous = -1;
    whisper_token no_timestamps = -1;
    if (!require_token("<|endoftext|>", crisper.endOfText) ||
        !require_token("<|startoftranscript|>", start_of_transcript) ||
        !require_token("<|en|>", english) ||
        !require_token("<|translate|>", translate) ||
        !require_token("<|transcribe|>", transcribe) ||
        !require_token("<|startoflm|>", start_of_lm) ||
        !require_token("<|startofprev|>", start_of_previous) ||
        !require_token("<|notimestamps|>", no_timestamps)) {
        return false;
    }
    const auto no_speech = token_ids.find("<|nospeech|>");
    const auto no_captions = token_ids.find("<|nocaptions|>");
    if (no_speech != token_ids.end()) {
        crisper.noSpeech = no_speech->second;
    } else if (no_captions != token_ids.end()) {
        // Large retains Whisper's historical spelling for the no-speech slot.
        crisper.noSpeech = no_captions->second;
    } else {
        error = "model vocabulary is incompatible with CrisperWhisper Intended mode; missing ";
        error += "<|nospeech|> or <|nocaptions|>";
        return false;
    }

    crisper.suppressTokens.insert(start_of_transcript);
    crisper.suppressTokens.insert(translate);
    crisper.suppressTokens.insert(transcribe);
    crisper.suppressTokens.insert(start_of_lm);
    crisper.suppressTokens.insert(start_of_previous);
    crisper.suppressTokens.insert(crisper.noSpeech);

    // CrisperWhisper was trained with the five mode-strength tags before the
    // standard Whisper task prefix. Do not reorder this sequence.
    crisper.decoderPrefix.push_back(start_of_transcript);
    crisper.decoderPrefix.push_back(english);
    crisper.decoderPrefix.push_back(transcribe);
    crisper.decoderPrefix.push_back(no_timestamps);
    context->crisper = std::move(crisper);
    return true;
}

static bool textify_whisper_is_control_token_text(const std::string &token) {
    if (token.size() >= 4 && token.rfind("<|", 0) == 0 &&
        token.compare(token.size() - 2, 2, "|>") == 0) {
        return true;
    }
    if (token.rfind("[verbatim_", 0) == 0 || token.rfind("[intended_", 0) == 0) {
        return true;
    }
    static const std::unordered_set<std::string> markers = {
        "<vtx>", "<evtx>", "<ctx>", "<ectx>", "<htx>", "<ehtx>",
    };
    return markers.count(token) != 0;
}

static std::string textify_whisper_decode_crisper_text(
    whisper_context *context,
    const std::vector<whisper_token> &tokens
) {
    std::string text;
    for (whisper_token token_id : tokens) {
        const char *raw_token = whisper_token_to_str(context, token_id);
        if (raw_token == nullptr) {
            continue;
        }
        const std::string token(raw_token);
        if (!textify_whisper_is_control_token_text(token)) {
            text += token;
        }
    }

    std::istringstream words(text);
    std::ostringstream normalized;
    std::string word;
    bool first = true;
    while (words >> word) {
        if (!first) {
            normalized << ' ';
        }
        normalized << word;
        first = false;
    }
    return normalized.str();
}

static double textify_whisper_logsumexp(
    const float *logits,
    int32_t vocabulary_size,
    const std::unordered_set<int> *suppress_tokens
) {
    float maximum = -std::numeric_limits<float>::infinity();
    for (int32_t token_id = 0; token_id < vocabulary_size; ++token_id) {
        if (suppress_tokens != nullptr && suppress_tokens->count(token_id) != 0) {
            continue;
        }
        const float logit = logits[token_id];
        if (std::isfinite(logit)) {
            maximum = std::max(maximum, logit);
        }
    }
    if (!std::isfinite(maximum)) {
        return -std::numeric_limits<double>::infinity();
    }

    double sum = 0.0;
    for (int32_t token_id = 0; token_id < vocabulary_size; ++token_id) {
        if (suppress_tokens != nullptr && suppress_tokens->count(token_id) != 0) {
            continue;
        }
        const float logit = logits[token_id];
        if (std::isfinite(logit)) {
            sum += std::exp(static_cast<double>(logit - maximum));
        }
    }
    return static_cast<double>(maximum) + std::log(sum);
}

static float textify_whisper_token_probability(
    const float *logits,
    int32_t vocabulary_size,
    whisper_token token_id
) {
    if (token_id < 0 || token_id >= vocabulary_size || !std::isfinite(logits[token_id])) {
        return 0.0f;
    }
    const double normalizer = textify_whisper_logsumexp(logits, vocabulary_size, nullptr);
    if (!std::isfinite(normalizer)) {
        return 0.0f;
    }
    return static_cast<float>(std::clamp(
        std::exp(static_cast<double>(logits[token_id]) - normalizer),
        0.0,
        1.0
    ));
}

static whisper_token textify_whisper_crisper_greedy_token(
    const float *logits,
    int32_t vocabulary_size,
    const std::unordered_set<int> &suppress_tokens
) {
    whisper_token best_token = -1;
    float best_logit = -std::numeric_limits<float>::infinity();
    for (int32_t token_id = 0; token_id < vocabulary_size; ++token_id) {
        if (suppress_tokens.count(token_id) != 0) {
            continue;
        }
        const float logit = logits[token_id];
        if (std::isfinite(logit) && logit > best_logit) {
            best_logit = logit;
            best_token = token_id;
        }
    }
    return best_token;
}

static int32_t textify_whisper_transcribe_crisper(
    TextifyWhisperContext *context,
    const float *samples,
    int32_t sample_count,
    const char *language,
    int32_t translate,
    float temperature,
    int32_t no_context,
    const char *initial_prompt
) {
    const char *effective_language = textify_whisper_effective_language(language);
    if (std::strcmp(effective_language, "en") != 0) {
        return textify_whisper_fail(context, -3, "CrisperWhisper supports English Intended mode only");
    }
    if (translate != 0) {
        return textify_whisper_fail(context, -3, "CrisperWhisper translation is unsupported");
    }
    if (!std::isfinite(temperature) || temperature != 0.0f) {
        return textify_whisper_fail(context, -3, "CrisperWhisper requires deterministic temperature 0 decoding");
    }
    if (no_context == 0) {
        return textify_whisper_fail(context, -3, "CrisperWhisper previous-context decoding is unsupported");
    }
    if (initial_prompt != nullptr && std::strlen(initial_prompt) != 0) {
        return textify_whisper_fail(context, -3, "CrisperWhisper initial prompts are unsupported");
    }
    if (sample_count > kTextifyCrisperMaxAudioSamples) {
        return textify_whisper_fail(context, -4, "CrisperWhisper audio cannot exceed 30 seconds");
    }

    const int32_t threads = textify_whisper_effective_thread_count(context->threadCount);
    if (whisper_pcm_to_mel(context->context, samples, sample_count, threads) != 0) {
        return textify_whisper_fail(context, -6, "failed to compute CrisperWhisper log-mel spectrogram");
    }
    if (whisper_encode(context->context, 0, threads) != 0) {
        return textify_whisper_fail(context, -7, "failed to run CrisperWhisper audio encoder");
    }

    const int32_t text_context = whisper_model_n_text_ctx(context->context);
    const std::vector<whisper_token> &prefix = context->crisper.decoderPrefix;
    if (prefix.empty() || static_cast<int32_t>(prefix.size()) >= text_context) {
        return textify_whisper_fail(context, -8, "CrisperWhisper decoder prefix exceeds model context");
    }
    if (whisper_decode(
            context->context,
            prefix.data(),
            static_cast<int32_t>(prefix.size()),
            0,
            threads
        ) != 0) {
        return textify_whisper_fail(context, -9, "failed to evaluate CrisperWhisper decoder prefix");
    }

    std::vector<whisper_token> generated;
    generated.reserve(kTextifyCrisperMaxNewTokens);
    int32_t past_token_count = static_cast<int32_t>(prefix.size());
    double log_probability_sum = 0.0;
    int32_t log_probability_count = 0;
    float no_speech_probability = 0.0f;

    for (int32_t step = 0;
         step < kTextifyCrisperMaxNewTokens && past_token_count < text_context;
         ++step) {
        const float *all_logits = whisper_get_logits(context->context);
        if (all_logits == nullptr) {
            return textify_whisper_fail(context, -10, "CrisperWhisper decoder returned no logits");
        }

        const int32_t row = step == 0 ? static_cast<int32_t>(prefix.size()) - 1 : 0;
        const float *logits = all_logits +
            static_cast<std::ptrdiff_t>(row) * context->crisper.vocabularySize;
        if (step == 0) {
            no_speech_probability = textify_whisper_token_probability(
                logits,
                context->crisper.vocabularySize,
                context->crisper.noSpeech
            );
        }

        const whisper_token token = textify_whisper_crisper_greedy_token(
            logits,
            context->crisper.vocabularySize,
            context->crisper.suppressTokens
        );
        if (token < 0) {
            return textify_whisper_fail(context, -11, "CrisperWhisper decoder produced no usable token");
        }

        const double normalizer = textify_whisper_logsumexp(
            logits,
            context->crisper.vocabularySize,
            &context->crisper.suppressTokens
        );
        if (std::isfinite(normalizer) && std::isfinite(logits[token])) {
            log_probability_sum += static_cast<double>(logits[token]) - normalizer;
            ++log_probability_count;
        }

        if (token == context->crisper.endOfText) {
            break;
        }
        generated.push_back(token);
        if (step + 1 >= kTextifyCrisperMaxNewTokens || past_token_count + 1 >= text_context) {
            break;
        }
        if (whisper_decode(
                context->context,
                &token,
                1,
                past_token_count,
                threads
            ) != 0) {
            return textify_whisper_fail(context, -12, "failed during CrisperWhisper autoregressive decode");
        }
        ++past_token_count;
    }

    context->lastText = textify_whisper_decode_crisper_text(context->context, generated);
    context->lastError = "";
    context->lastNoSpeechProbability = no_speech_probability;
    context->lastAverageLogProbability = log_probability_count > 0
        ? static_cast<float>(log_probability_sum / log_probability_count)
        : 0.0f;
    context->lastCompressionRatio = textify_whisper_compression_ratio(context->lastText);
    return 0;
}

static TextifyWhisperContext *textify_whisper_load_impl(
    const char *model_path,
    int32_t use_gpu,
    int32_t thread_count
) {
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

    TextifyWhisperContext *context = nullptr;
    try {
        context = new TextifyWhisperContext;
        context->context = native_context;
        context->threadCount = textify_whisper_effective_thread_count(thread_count);
        textify_whisper_reset_result(context);

        std::string vocabulary_error;
        if (!textify_whisper_configure_crisper_vocabulary(context, vocabulary_error)) {
            whisper_free(native_context);
            delete context;
            textify_whisper_set_global_error(vocabulary_error);
            return nullptr;
        }
    } catch (const std::exception &exception) {
        whisper_free(native_context);
        delete context;
        std::string message = "failed to inspect model vocabulary: ";
        message += exception.what();
        textify_whisper_set_global_error(message);
        return nullptr;
    } catch (...) {
        whisper_free(native_context);
        delete context;
        textify_whisper_set_global_error("failed to inspect model vocabulary");
        return nullptr;
    }

    textify_whisper_set_global_error("");
    return context;
}

TextifyWhisperContext *textify_whisper_load(
    const char *model_path,
    int32_t use_gpu,
    int32_t thread_count
) {
    try {
        return textify_whisper_load_impl(model_path, use_gpu, thread_count);
    } catch (const std::exception &exception) {
        try {
            std::string message = "native model load failed: ";
            message += exception.what();
            textify_whisper_set_global_error(message);
        } catch (...) {
        }
        return nullptr;
    } catch (...) {
        try {
            textify_whisper_set_global_error("native model load failed");
        } catch (...) {
        }
        return nullptr;
    }
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

static int32_t textify_whisper_transcribe_impl(
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
        return textify_whisper_fail(context, -2, "audio buffer is empty");
    }

    textify_whisper_reset_result(context);
    if (context->crisper.enabled) {
        try {
            return textify_whisper_transcribe_crisper(
                context,
                pcm_mono_f32_16khz,
                sample_count,
                language,
                translate,
                temperature,
                no_context,
                initial_prompt
            );
        } catch (const std::exception &exception) {
            std::string message = "CrisperWhisper decoding failed: ";
            message += exception.what();
            return textify_whisper_fail(context, -13, message);
        } catch (...) {
            return textify_whisper_fail(context, -13, "CrisperWhisper decoding failed");
        }
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
    try {
        return textify_whisper_transcribe_impl(
            context,
            pcm_mono_f32_16khz,
            sample_count,
            language,
            translate,
            temperature,
            no_context,
            initial_prompt
        );
    } catch (...) {
        if (context != nullptr) {
            try {
                textify_whisper_fail(context, -14, "native transcription failed unexpectedly");
            } catch (...) {
            }
        } else {
            try {
                textify_whisper_set_global_error("native transcription failed unexpectedly");
            } catch (...) {
            }
        }
        return -14;
    }
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

int32_t textify_whisper_is_crisper_model(TextifyWhisperContext *context) {
    return context != nullptr && context->crisper.enabled ? 1 : 0;
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
