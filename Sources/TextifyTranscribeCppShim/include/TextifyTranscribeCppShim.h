#ifndef TEXTIFY_TRANSCRIBE_CPP_SHIM_H
#define TEXTIFY_TRANSCRIBE_CPP_SHIM_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct TextifyTranscribeCppContext TextifyTranscribeCppContext;

typedef enum TextifyTranscribeCppStatus {
  TextifyTranscribeCppStatusOK = 0,
  TextifyTranscribeCppStatusInvalidArgument = 1,
  TextifyTranscribeCppStatusRuntimeLoadFailed = 2,
  TextifyTranscribeCppStatusIncompatibleRuntime = 3,
  TextifyTranscribeCppStatusModelLoadFailed = 4,
  TextifyTranscribeCppStatusMetalUnavailable = 5,
  TextifyTranscribeCppStatusTranscriptionFailed = 6
} TextifyTranscribeCppStatus;

TextifyTranscribeCppContext *TextifyTranscribeCppCreate(
    const char *runtime_directory,
    const char *model_path,
    int32_t thread_count,
    char *error_message,
    int32_t error_message_capacity);

TextifyTranscribeCppStatus TextifyTranscribeCppTranscribe(
    TextifyTranscribeCppContext *context,
    const float *samples,
    int32_t sample_count,
    int32_t sample_rate,
    const char *language,
    char **text,
    char *error_message,
    int32_t error_message_capacity);

TextifyTranscribeCppStatus TextifyTranscribeCppCopyBackend(
    const TextifyTranscribeCppContext *context,
    char *backend,
    int32_t backend_capacity);

void TextifyTranscribeCppFreeText(char *text);
void TextifyTranscribeCppDestroy(TextifyTranscribeCppContext *context);

#ifdef __cplusplus
}
#endif

#endif
