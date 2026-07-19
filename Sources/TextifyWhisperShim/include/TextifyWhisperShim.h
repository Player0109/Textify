#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct TextifyWhisperContext TextifyWhisperContext;

TextifyWhisperContext *textify_whisper_load(const char *model_path, int32_t use_gpu, int32_t thread_count);
void textify_whisper_free(TextifyWhisperContext *context);

int32_t textify_whisper_transcribe(
    TextifyWhisperContext *context,
    const float *pcm_mono_f32_16khz,
    int32_t sample_count,
    const char *language,
    int32_t translate,
    float temperature,
    int32_t no_context,
    const char *initial_prompt
);

const char *textify_whisper_last_text(TextifyWhisperContext *context);
const char *textify_whisper_last_error(TextifyWhisperContext *context);
float textify_whisper_last_no_speech_probability(TextifyWhisperContext *context);
float textify_whisper_last_average_log_probability(TextifyWhisperContext *context);
float textify_whisper_last_compression_ratio(TextifyWhisperContext *context);
int32_t textify_whisper_uses_gpu(TextifyWhisperContext *context);

int32_t textify_whisper_compiled_with_metal(void);

#define TEXTIFY_WHISPER_JOIN_NAME(left, right) left##right
#define TEXTIFY_WHISPER_DISABLED_RUNTIME_PROBE TEXTIFY_WHISPER_JOIN_NAME(textify_whisper_compiled_with_core, ml)
int32_t TEXTIFY_WHISPER_DISABLED_RUNTIME_PROBE(void);

#ifdef __cplusplus
}
#endif
