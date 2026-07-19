#ifndef TEXTIFY_SHERPA_SHIM_H
#define TEXTIFY_SHERPA_SHIM_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct TextifySherpaContext TextifySherpaContext;

typedef enum TextifySherpaStatus {
  TextifySherpaStatusOK = 0,
  TextifySherpaStatusInvalidArgument = 1,
  TextifySherpaStatusRuntimeLoadFailed = 2,
  TextifySherpaStatusIncompatibleRuntime = 3,
  TextifySherpaStatusRecognizerCreationFailed = 4,
  TextifySherpaStatusStreamCreationFailed = 5,
  TextifySherpaStatusTranscriptionFailed = 6
} TextifySherpaStatus;

TextifySherpaContext *TextifySherpaCreateTransducer(
    const char *runtime_directory,
    const char *encoder_path,
    const char *decoder_path,
    const char *joiner_path,
    const char *tokens_path,
    int32_t thread_count,
    char *error_message,
    int32_t error_message_capacity);

TextifySherpaContext *TextifySherpaCreateQwen3ASR(
    const char *runtime_directory,
    const char *conv_frontend_path,
    const char *encoder_path,
    const char *decoder_path,
    const char *tokenizer_directory,
    const char *provider,
    int32_t thread_count,
    char *error_message,
    int32_t error_message_capacity);

TextifySherpaContext *TextifySherpaCreateOmnilingualASR(
    const char *runtime_directory,
    const char *model_path,
    const char *tokens_path,
    const char *provider,
    int32_t thread_count,
    char *error_message,
    int32_t error_message_capacity);

TextifySherpaContext *TextifySherpaCreateDolphin(
    const char *runtime_directory,
    const char *model_path,
    const char *tokens_path,
    const char *provider,
    int32_t thread_count,
    char *error_message,
    int32_t error_message_capacity);

TextifySherpaContext *TextifySherpaCreateSenseVoice(
    const char *runtime_directory,
    const char *model_path,
    const char *tokens_path,
    const char *language,
    const char *provider,
    int32_t thread_count,
    char *error_message,
    int32_t error_message_capacity);

TextifySherpaStatus TextifySherpaTranscribe(
    TextifySherpaContext *context,
    const float *samples,
    int32_t sample_count,
    int32_t sample_rate,
    char **text,
    float *average_log_probability,
    char *error_message,
    int32_t error_message_capacity);

void TextifySherpaFreeText(char *text);
void TextifySherpaDestroy(TextifySherpaContext *context);

#ifdef __cplusplus
}
#endif

#endif
