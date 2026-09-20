#pragma once
#include <stdint.h>

typedef struct TextifyConfuciusContext TextifyConfuciusContext;
TextifyConfuciusContext *TextifyConfuciusCreate(const char *library, const char *model);
void TextifyConfuciusDestroy(TextifyConfuciusContext *context);
// Returned strings belong to the context and must be copied before the next call.
const char *TextifyConfuciusTranscribe(TextifyConfuciusContext *context, const float *samples, int32_t count, const char *language);
int32_t TextifyConfuciusStart(TextifyConfuciusContext *context, const char *language);
const char *TextifyConfuciusPush(TextifyConfuciusContext *context, const float *samples, int32_t count);
const char *TextifyConfuciusFinish(TextifyConfuciusContext *context);
void TextifyConfuciusReset(TextifyConfuciusContext *context);
