#include "TextifySherpaShim.h"

#include <dlfcn.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../../../Vendor/sherpa-onnx/v1.13.2/include/sherpa-onnx/c-api/c-api.h"

#define TEXTIFY_SHERPA_VERSION "1.13.2"
#define TEXTIFY_SHERPA_GIT_SHA "13d0ae6c"

typedef const char *(*TextifySherpaGetStringFunction)(void);
typedef const SherpaOnnxOfflineRecognizer *(*TextifySherpaCreateRecognizerFunction)(
    const SherpaOnnxOfflineRecognizerConfig *config);
typedef void (*TextifySherpaDestroyRecognizerFunction)(
    const SherpaOnnxOfflineRecognizer *recognizer);
typedef const SherpaOnnxOfflineStream *(*TextifySherpaCreateStreamFunction)(
    const SherpaOnnxOfflineRecognizer *recognizer);
typedef void (*TextifySherpaDestroyStreamFunction)(
    const SherpaOnnxOfflineStream *stream);
typedef void (*TextifySherpaAcceptWaveformFunction)(
    const SherpaOnnxOfflineStream *stream,
    int32_t sample_rate,
    const float *samples,
    int32_t sample_count);
typedef void (*TextifySherpaDecodeFunction)(
    const SherpaOnnxOfflineRecognizer *recognizer,
    const SherpaOnnxOfflineStream *stream);
typedef const SherpaOnnxOfflineRecognizerResult *(*TextifySherpaGetResultFunction)(
    const SherpaOnnxOfflineStream *stream);
typedef void (*TextifySherpaDestroyResultFunction)(
    const SherpaOnnxOfflineRecognizerResult *result);

struct TextifySherpaContext {
  void *onnx_runtime_handle;
  void *sherpa_handle;
  const SherpaOnnxOfflineRecognizer *recognizer;
  TextifySherpaDestroyRecognizerFunction destroy_recognizer;
  TextifySherpaCreateStreamFunction create_stream;
  TextifySherpaDestroyStreamFunction destroy_stream;
  TextifySherpaAcceptWaveformFunction accept_waveform;
  TextifySherpaDecodeFunction decode;
  TextifySherpaGetResultFunction get_result;
  TextifySherpaDestroyResultFunction destroy_result;
};

static void TextifySherpaSetError(
    char *destination,
    int32_t capacity,
    const char *message) {
  if (destination == NULL || capacity <= 0) {
    return;
  }
  snprintf(destination, (size_t)capacity, "%s", message == NULL ? "Unknown error." : message);
}

static int TextifySherpaJoinPath(
    char *destination,
    size_t capacity,
    const char *directory,
    const char *filename) {
  int written = snprintf(destination, capacity, "%s/%s", directory, filename);
  return written >= 0 && (size_t)written < capacity;
}

static void *TextifySherpaLoadSymbol(
    void *handle,
    const char *name,
    char *error_message,
    int32_t error_message_capacity) {
  dlerror();
  void *symbol = dlsym(handle, name);
  const char *error = dlerror();
  if (error != NULL) {
    TextifySherpaSetError(error_message, error_message_capacity, error);
    return NULL;
  }
  return symbol;
}

static void TextifySherpaReleasePartialContext(TextifySherpaContext *context) {
  if (context == NULL) {
    return;
  }
  if (context->recognizer != NULL && context->destroy_recognizer != NULL) {
    context->destroy_recognizer(context->recognizer);
  }
  if (context->sherpa_handle != NULL) {
    dlclose(context->sherpa_handle);
  }
  if (context->onnx_runtime_handle != NULL) {
    dlclose(context->onnx_runtime_handle);
  }
  free(context);
}

#define TEXTIFY_LOAD_FUNCTION(context, field, type, symbol_name, error, capacity) \
  do {                                                                            \
    void *textify_symbol = TextifySherpaLoadSymbol(                                \
        (context)->sherpa_handle, symbol_name, error, capacity);                   \
    if (textify_symbol == NULL) {                                                   \
      TextifySherpaReleasePartialContext(context);                                 \
      return NULL;                                                                 \
    }                                                                              \
    (context)->field = (type)textify_symbol;                                       \
  } while (0)

static TextifySherpaContext *TextifySherpaCreateRecognizer(
    const char *runtime_directory,
    const SherpaOnnxOfflineRecognizerConfig *config,
    char *error_message,
    int32_t error_message_capacity) {
  if (runtime_directory == NULL || config == NULL) {
    TextifySherpaSetError(
        error_message,
        error_message_capacity,
        "The sherpa-onnx recognizer configuration is invalid.");
    return NULL;
  }

  char onnx_runtime_path[4096];
  char sherpa_path[4096];
  if (!TextifySherpaJoinPath(
          onnx_runtime_path,
          sizeof(onnx_runtime_path),
          runtime_directory,
          "libonnxruntime.1.24.4.dylib") ||
      !TextifySherpaJoinPath(
          sherpa_path,
          sizeof(sherpa_path),
          runtime_directory,
          "libsherpa-onnx-c-api.dylib")) {
    TextifySherpaSetError(
        error_message,
        error_message_capacity,
        "The sherpa-onnx runtime path is too long.");
    return NULL;
  }

  TextifySherpaContext *context = calloc(1, sizeof(TextifySherpaContext));
  if (context == NULL) {
    TextifySherpaSetError(error_message, error_message_capacity, "Out of memory.");
    return NULL;
  }

  context->onnx_runtime_handle = dlopen(onnx_runtime_path, RTLD_NOW | RTLD_GLOBAL);
  if (context->onnx_runtime_handle == NULL) {
    TextifySherpaSetError(error_message, error_message_capacity, dlerror());
    TextifySherpaReleasePartialContext(context);
    return NULL;
  }
  context->sherpa_handle = dlopen(sherpa_path, RTLD_NOW | RTLD_LOCAL);
  if (context->sherpa_handle == NULL) {
    TextifySherpaSetError(error_message, error_message_capacity, dlerror());
    TextifySherpaReleasePartialContext(context);
    return NULL;
  }

  TextifySherpaGetStringFunction get_version =
      (TextifySherpaGetStringFunction)TextifySherpaLoadSymbol(
          context->sherpa_handle,
          "SherpaOnnxGetVersionStr",
          error_message,
          error_message_capacity);
  TextifySherpaGetStringFunction get_git_sha =
      (TextifySherpaGetStringFunction)TextifySherpaLoadSymbol(
          context->sherpa_handle,
          "SherpaOnnxGetGitSha1",
          error_message,
          error_message_capacity);
  const char *runtime_version = get_version == NULL ? NULL : get_version();
  const char *runtime_git_sha = get_git_sha == NULL ? NULL : get_git_sha();
  if (runtime_version == NULL || runtime_git_sha == NULL ||
      strcmp(runtime_version, TEXTIFY_SHERPA_VERSION) != 0 ||
      strcmp(runtime_git_sha, TEXTIFY_SHERPA_GIT_SHA) != 0) {
    TextifySherpaSetError(
        error_message,
        error_message_capacity,
        "The bundled sherpa-onnx runtime version does not match Textify.");
    TextifySherpaReleasePartialContext(context);
    return NULL;
  }

  TextifySherpaCreateRecognizerFunction create_recognizer =
      (TextifySherpaCreateRecognizerFunction)TextifySherpaLoadSymbol(
          context->sherpa_handle,
          "SherpaOnnxCreateOfflineRecognizer",
          error_message,
          error_message_capacity);
  if (create_recognizer == NULL) {
    TextifySherpaReleasePartialContext(context);
    return NULL;
  }
  TEXTIFY_LOAD_FUNCTION(
      context,
      destroy_recognizer,
      TextifySherpaDestroyRecognizerFunction,
      "SherpaOnnxDestroyOfflineRecognizer",
      error_message,
      error_message_capacity);
  TEXTIFY_LOAD_FUNCTION(
      context,
      create_stream,
      TextifySherpaCreateStreamFunction,
      "SherpaOnnxCreateOfflineStream",
      error_message,
      error_message_capacity);
  TEXTIFY_LOAD_FUNCTION(
      context,
      destroy_stream,
      TextifySherpaDestroyStreamFunction,
      "SherpaOnnxDestroyOfflineStream",
      error_message,
      error_message_capacity);
  TEXTIFY_LOAD_FUNCTION(
      context,
      accept_waveform,
      TextifySherpaAcceptWaveformFunction,
      "SherpaOnnxAcceptWaveformOffline",
      error_message,
      error_message_capacity);
  TEXTIFY_LOAD_FUNCTION(
      context,
      decode,
      TextifySherpaDecodeFunction,
      "SherpaOnnxDecodeOfflineStream",
      error_message,
      error_message_capacity);
  TEXTIFY_LOAD_FUNCTION(
      context,
      get_result,
      TextifySherpaGetResultFunction,
      "SherpaOnnxGetOfflineStreamResult",
      error_message,
      error_message_capacity);
  TEXTIFY_LOAD_FUNCTION(
      context,
      destroy_result,
      TextifySherpaDestroyResultFunction,
      "SherpaOnnxDestroyOfflineRecognizerResult",
      error_message,
      error_message_capacity);

  context->recognizer = create_recognizer(config);
  if (context->recognizer == NULL) {
    TextifySherpaSetError(
        error_message,
        error_message_capacity,
        "sherpa-onnx could not create the offline recognizer.");
    TextifySherpaReleasePartialContext(context);
    return NULL;
  }

  return context;
}

TextifySherpaContext *TextifySherpaCreateTransducer(
    const char *runtime_directory,
    const char *encoder_path,
    const char *decoder_path,
    const char *joiner_path,
    const char *tokens_path,
    int32_t thread_count,
    char *error_message,
    int32_t error_message_capacity) {
  if (encoder_path == NULL || decoder_path == NULL || joiner_path == NULL ||
      tokens_path == NULL || thread_count <= 0) {
    TextifySherpaSetError(
        error_message,
        error_message_capacity,
        "The sherpa-onnx transducer configuration is invalid.");
    return NULL;
  }

  SherpaOnnxOfflineRecognizerConfig config;
  memset(&config, 0, sizeof(config));
  config.feat_config.sample_rate = 16000;
  config.feat_config.feature_dim = 80;
  config.model_config.transducer.encoder = encoder_path;
  config.model_config.transducer.decoder = decoder_path;
  config.model_config.transducer.joiner = joiner_path;
  config.model_config.tokens = tokens_path;
  config.model_config.num_threads = thread_count;
  config.model_config.provider = "cpu";
  config.model_config.model_type = "transducer";
  config.decoding_method = "greedy_search";
  return TextifySherpaCreateRecognizer(
      runtime_directory, &config, error_message, error_message_capacity);
}

TextifySherpaContext *TextifySherpaCreateQwen3ASR(
    const char *runtime_directory,
    const char *conv_frontend_path,
    const char *encoder_path,
    const char *decoder_path,
    const char *tokenizer_directory,
    const char *provider,
    int32_t thread_count,
    char *error_message,
    int32_t error_message_capacity) {
  if (conv_frontend_path == NULL || encoder_path == NULL || decoder_path == NULL ||
      tokenizer_directory == NULL || provider == NULL || thread_count <= 0 ||
      (strcmp(provider, "cpu") != 0 && strcmp(provider, "coreml") != 0)) {
    TextifySherpaSetError(
        error_message,
        error_message_capacity,
        "The sherpa-onnx Qwen3-ASR configuration is invalid.");
    return NULL;
  }

  SherpaOnnxOfflineRecognizerConfig config;
  memset(&config, 0, sizeof(config));
  config.feat_config.sample_rate = 16000;
  config.feat_config.feature_dim = 128;
  config.model_config.qwen3_asr.conv_frontend = conv_frontend_path;
  config.model_config.qwen3_asr.encoder = encoder_path;
  config.model_config.qwen3_asr.decoder = decoder_path;
  config.model_config.qwen3_asr.tokenizer = tokenizer_directory;
  config.model_config.qwen3_asr.max_total_len = 512;
  config.model_config.qwen3_asr.max_new_tokens = 512;
  config.model_config.qwen3_asr.temperature = 0.000001f;
  config.model_config.qwen3_asr.top_p = 0.8f;
  config.model_config.qwen3_asr.seed = 42;
  config.model_config.num_threads = thread_count;
  config.model_config.provider = provider;
  config.model_config.model_type = "qwen3_asr";
  config.decoding_method = "greedy_search";
  return TextifySherpaCreateRecognizer(
      runtime_directory, &config, error_message, error_message_capacity);
}

TextifySherpaContext *TextifySherpaCreateOmnilingualASR(
    const char *runtime_directory,
    const char *model_path,
    const char *tokens_path,
    const char *provider,
    int32_t thread_count,
    char *error_message,
    int32_t error_message_capacity) {
  if (model_path == NULL || tokens_path == NULL || provider == NULL ||
      thread_count <= 0 ||
      (strcmp(provider, "cpu") != 0 && strcmp(provider, "coreml") != 0)) {
    TextifySherpaSetError(
        error_message,
        error_message_capacity,
        "The sherpa-onnx Omnilingual ASR configuration is invalid.");
    return NULL;
  }

  SherpaOnnxOfflineRecognizerConfig config;
  memset(&config, 0, sizeof(config));
  config.feat_config.sample_rate = 16000;
  config.feat_config.feature_dim = 80;
  config.model_config.omnilingual.model = model_path;
  config.model_config.tokens = tokens_path;
  config.model_config.num_threads = thread_count;
  config.model_config.provider = provider;
  config.model_config.model_type = "omnilingual";
  config.decoding_method = "greedy_search";
  return TextifySherpaCreateRecognizer(
      runtime_directory, &config, error_message, error_message_capacity);
}

TextifySherpaContext *TextifySherpaCreateDolphin(
    const char *runtime_directory,
    const char *model_path,
    const char *tokens_path,
    const char *provider,
    int32_t thread_count,
    char *error_message,
    int32_t error_message_capacity) {
  if (model_path == NULL || tokens_path == NULL || provider == NULL ||
      thread_count <= 0 ||
      (strcmp(provider, "cpu") != 0 && strcmp(provider, "coreml") != 0)) {
    TextifySherpaSetError(
        error_message,
        error_message_capacity,
        "The sherpa-onnx Dolphin configuration is invalid.");
    return NULL;
  }

  SherpaOnnxOfflineRecognizerConfig config;
  memset(&config, 0, sizeof(config));
  config.feat_config.sample_rate = 16000;
  config.feat_config.feature_dim = 80;
  config.model_config.dolphin.model = model_path;
  config.model_config.tokens = tokens_path;
  config.model_config.num_threads = thread_count;
  config.model_config.provider = provider;
  config.model_config.modeling_unit = "cjkchar";
  config.decoding_method = "greedy_search";
  return TextifySherpaCreateRecognizer(
      runtime_directory, &config, error_message, error_message_capacity);
}

TextifySherpaContext *TextifySherpaCreateSenseVoice(
    const char *runtime_directory,
    const char *model_path,
    const char *tokens_path,
    const char *language,
    const char *provider,
    int32_t thread_count,
    char *error_message,
    int32_t error_message_capacity) {
  if (model_path == NULL || tokens_path == NULL || language == NULL ||
      provider == NULL || thread_count <= 0 ||
      (strcmp(provider, "cpu") != 0 && strcmp(provider, "coreml") != 0)) {
    TextifySherpaSetError(
        error_message,
        error_message_capacity,
        "The sherpa-onnx SenseVoice configuration is invalid.");
    return NULL;
  }

  SherpaOnnxOfflineRecognizerConfig config;
  memset(&config, 0, sizeof(config));
  config.feat_config.sample_rate = 16000;
  config.feat_config.feature_dim = 80;
  config.model_config.sense_voice.model = model_path;
  config.model_config.sense_voice.language = language;
  config.model_config.sense_voice.use_itn = 1;
  config.model_config.tokens = tokens_path;
  config.model_config.num_threads = thread_count;
  config.model_config.provider = provider;
  config.decoding_method = "greedy_search";
  return TextifySherpaCreateRecognizer(
      runtime_directory, &config, error_message, error_message_capacity);
}

TextifySherpaStatus TextifySherpaTranscribe(
    TextifySherpaContext *context,
    const float *samples,
    int32_t sample_count,
    int32_t sample_rate,
    char **text,
    float *average_log_probability,
    char *error_message,
    int32_t error_message_capacity) {
  if (context == NULL || samples == NULL || sample_count <= 0 || sample_rate <= 0 ||
      text == NULL || average_log_probability == NULL) {
    TextifySherpaSetError(
        error_message,
        error_message_capacity,
        "The sherpa-onnx transcription input is invalid.");
    return TextifySherpaStatusInvalidArgument;
  }

  *text = NULL;
  *average_log_probability = -10.0f;
  const SherpaOnnxOfflineStream *stream = context->create_stream(context->recognizer);
  if (stream == NULL) {
    TextifySherpaSetError(
        error_message,
        error_message_capacity,
        "sherpa-onnx could not create an offline stream.");
    return TextifySherpaStatusStreamCreationFailed;
  }

  context->accept_waveform(stream, sample_rate, samples, sample_count);
  context->decode(context->recognizer, stream);
  const SherpaOnnxOfflineRecognizerResult *result = context->get_result(stream);
  if (result == NULL || result->text == NULL) {
    if (result != NULL) {
      context->destroy_result(result);
    }
    context->destroy_stream(stream);
    TextifySherpaSetError(
        error_message,
        error_message_capacity,
        "sherpa-onnx returned no transcription result.");
    return TextifySherpaStatusTranscriptionFailed;
  }

  char *copied_text = strdup(result->text);
  if (copied_text == NULL) {
    context->destroy_result(result);
    context->destroy_stream(stream);
    TextifySherpaSetError(error_message, error_message_capacity, "Out of memory.");
    return TextifySherpaStatusTranscriptionFailed;
  }

  if (result->ys_log_probs != NULL && result->count > 0) {
    double total = 0;
    int32_t valid_count = 0;
    for (int32_t index = 0; index < result->count; ++index) {
      float value = result->ys_log_probs[index];
      if (isfinite(value)) {
        total += value;
        valid_count += 1;
      }
    }
    if (valid_count > 0) {
      *average_log_probability = (float)(total / valid_count);
    }
  } else if (copied_text[0] != '\0') {
    *average_log_probability = 0;
  }

  context->destroy_result(result);
  context->destroy_stream(stream);
  *text = copied_text;
  return TextifySherpaStatusOK;
}

void TextifySherpaFreeText(char *text) {
  free(text);
}

void TextifySherpaDestroy(TextifySherpaContext *context) {
  TextifySherpaReleasePartialContext(context);
}
