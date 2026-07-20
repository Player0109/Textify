#include "TextifyTranscribeCppShim.h"

#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../../Vendor/transcribe.cpp/v0.1.3/include/transcribe.h"

#define TEXTIFY_TRANSCRIBE_CPP_LIBRARY "libtextify-transcribe.0.1.3.dylib"
#define TEXTIFY_TRANSCRIBE_CPP_VERSION "0.1.3"
#define TEXTIFY_TRANSCRIBE_CPP_COMMIT "5a5a496"
#define TEXTIFY_TRANSCRIBE_CPP_CONTEXT_SIZE 4096

typedef const char *(*TextifyTranscribeCppGetStringFunction)(void);
typedef size_t (*TextifyTranscribeCppABISizeFunction)(transcribe_abi_struct which);
typedef void (*TextifyTranscribeCppModelLoadParamsInitFunction)(
    struct transcribe_model_load_params *params);
typedef void (*TextifyTranscribeCppSessionParamsInitFunction)(
    struct transcribe_session_params *params);
typedef void (*TextifyTranscribeCppRunParamsInitFunction)(
    struct transcribe_run_params *params);
typedef transcribe_status (*TextifyTranscribeCppOpenFunction)(
    const char *path,
    const struct transcribe_model_load_params *load_params,
    const struct transcribe_session_params *session_params,
    struct transcribe_session **out_session);
typedef void (*TextifyTranscribeCppCloseFunction)(struct transcribe_session *session);
typedef transcribe_status (*TextifyTranscribeCppRunFunction)(
    struct transcribe_session *session,
    const float *pcm,
    int n_samples,
    const struct transcribe_run_params *params);
typedef const char *(*TextifyTranscribeCppFullTextFunction)(
    const struct transcribe_session *session);
typedef const struct transcribe_model *(*TextifyTranscribeCppGetModelFunction)(
    const struct transcribe_session *session);
typedef void (*TextifyTranscribeCppBackendDeviceInitFunction)(
    struct transcribe_backend_device *device);
typedef transcribe_status (*TextifyTranscribeCppModelGetDeviceFunction)(
    const struct transcribe_model *model,
    struct transcribe_backend_device *device);
typedef bool (*TextifyTranscribeCppModelSupportsFunction)(
    const struct transcribe_model *model,
    transcribe_feature feature);
typedef const char *(*TextifyTranscribeCppStatusStringFunction)(int status);

struct TextifyTranscribeCppContext {
  void *runtime_handle;
  struct transcribe_session *session;
  TextifyTranscribeCppCloseFunction close_session;
  TextifyTranscribeCppRunParamsInitFunction run_params_init;
  TextifyTranscribeCppRunFunction run;
  TextifyTranscribeCppFullTextFunction full_text;
  TextifyTranscribeCppGetModelFunction get_model;
  TextifyTranscribeCppBackendDeviceInitFunction backend_device_init;
  TextifyTranscribeCppModelGetDeviceFunction model_get_device;
  TextifyTranscribeCppModelSupportsFunction model_supports;
  TextifyTranscribeCppStatusStringFunction status_string;
};

static void TextifyTranscribeCppSetError(
    char *destination,
    int32_t capacity,
    const char *message) {
  if (destination == NULL || capacity <= 0) {
    return;
  }
  snprintf(destination, (size_t)capacity, "%s", message == NULL ? "Unknown error." : message);
}

static int TextifyTranscribeCppJoinPath(
    char *destination,
    size_t capacity,
    const char *directory,
    const char *filename) {
  int written = snprintf(destination, capacity, "%s/%s", directory, filename);
  return written >= 0 && (size_t)written < capacity;
}

static void *TextifyTranscribeCppLoadSymbol(
    void *handle,
    const char *name,
    char *error_message,
    int32_t error_message_capacity) {
  dlerror();
  void *symbol = dlsym(handle, name);
  const char *error = dlerror();
  if (error != NULL) {
    TextifyTranscribeCppSetError(error_message, error_message_capacity, error);
    return NULL;
  }
  return symbol;
}

static void TextifyTranscribeCppReleasePartialContext(
    TextifyTranscribeCppContext *context) {
  if (context == NULL) {
    return;
  }
  if (context->session != NULL && context->close_session != NULL) {
    context->close_session(context->session);
  }
  if (context->runtime_handle != NULL) {
    dlclose(context->runtime_handle);
  }
  free(context);
}

#define TEXTIFY_LOAD_FUNCTION(context, field, type, symbol_name, error, capacity) \
  do {                                                                             \
    void *textify_symbol = TextifyTranscribeCppLoadSymbol(                          \
        (context)->runtime_handle, symbol_name, error, capacity);                   \
    if (textify_symbol == NULL) {                                                   \
      TextifyTranscribeCppReleasePartialContext(context);                           \
      return NULL;                                                                  \
    }                                                                               \
    (context)->field = (type)textify_symbol;                                        \
  } while (0)

TextifyTranscribeCppContext *TextifyTranscribeCppCreate(
    const char *runtime_directory,
    const char *model_path,
    int32_t thread_count,
    char *error_message,
    int32_t error_message_capacity) {
  if (runtime_directory == NULL || runtime_directory[0] == '\0' ||
      model_path == NULL || model_path[0] == '\0' ||
      thread_count < 1 || thread_count > 4) {
    TextifyTranscribeCppSetError(
        error_message,
        error_message_capacity,
        "The transcribe.cpp runtime configuration is invalid.");
    return NULL;
  }

  char runtime_path[TEXTIFY_TRANSCRIBE_CPP_CONTEXT_SIZE];
  if (!TextifyTranscribeCppJoinPath(
          runtime_path,
          sizeof(runtime_path),
          runtime_directory,
          TEXTIFY_TRANSCRIBE_CPP_LIBRARY)) {
    TextifyTranscribeCppSetError(
        error_message,
        error_message_capacity,
        "The transcribe.cpp runtime path is too long.");
    return NULL;
  }

  TextifyTranscribeCppContext *context = calloc(1, sizeof(TextifyTranscribeCppContext));
  if (context == NULL) {
    TextifyTranscribeCppSetError(error_message, error_message_capacity, "Out of memory.");
    return NULL;
  }

  context->runtime_handle = dlopen(runtime_path, RTLD_NOW | RTLD_LOCAL);
  if (context->runtime_handle == NULL) {
    TextifyTranscribeCppSetError(error_message, error_message_capacity, dlerror());
    TextifyTranscribeCppReleasePartialContext(context);
    return NULL;
  }

  TextifyTranscribeCppGetStringFunction get_version =
      (TextifyTranscribeCppGetStringFunction)TextifyTranscribeCppLoadSymbol(
          context->runtime_handle,
          "transcribe_version",
          error_message,
          error_message_capacity);
  TextifyTranscribeCppGetStringFunction get_commit =
      (TextifyTranscribeCppGetStringFunction)TextifyTranscribeCppLoadSymbol(
          context->runtime_handle,
          "transcribe_version_commit",
          error_message,
          error_message_capacity);
  TextifyTranscribeCppABISizeFunction abi_size =
      (TextifyTranscribeCppABISizeFunction)TextifyTranscribeCppLoadSymbol(
          context->runtime_handle,
          "transcribe_abi_struct_size",
          error_message,
          error_message_capacity);
  if (get_version == NULL || get_commit == NULL || abi_size == NULL ||
      strcmp(get_version(), TEXTIFY_TRANSCRIBE_CPP_VERSION) != 0 ||
      strcmp(get_commit(), TEXTIFY_TRANSCRIBE_CPP_COMMIT) != 0 ||
      abi_size(TRANSCRIBE_ABI_MODEL_LOAD_PARAMS) != sizeof(struct transcribe_model_load_params) ||
      abi_size(TRANSCRIBE_ABI_SESSION_PARAMS) != sizeof(struct transcribe_session_params) ||
      abi_size(TRANSCRIBE_ABI_RUN_PARAMS) != sizeof(struct transcribe_run_params)) {
    TextifyTranscribeCppSetError(
        error_message,
        error_message_capacity,
        "The bundled transcribe.cpp runtime version or ABI does not match Textify.");
    TextifyTranscribeCppReleasePartialContext(context);
    return NULL;
  }

  TextifyTranscribeCppModelLoadParamsInitFunction model_load_params_init =
      (TextifyTranscribeCppModelLoadParamsInitFunction)TextifyTranscribeCppLoadSymbol(
          context->runtime_handle,
          "transcribe_model_load_params_init",
          error_message,
          error_message_capacity);
  TextifyTranscribeCppSessionParamsInitFunction session_params_init =
      (TextifyTranscribeCppSessionParamsInitFunction)TextifyTranscribeCppLoadSymbol(
          context->runtime_handle,
          "transcribe_session_params_init",
          error_message,
          error_message_capacity);
  TextifyTranscribeCppOpenFunction open_session =
      (TextifyTranscribeCppOpenFunction)TextifyTranscribeCppLoadSymbol(
          context->runtime_handle,
          "transcribe_open",
          error_message,
          error_message_capacity);
  if (model_load_params_init == NULL || session_params_init == NULL || open_session == NULL) {
    TextifyTranscribeCppReleasePartialContext(context);
    return NULL;
  }

  TEXTIFY_LOAD_FUNCTION(
      context,
      close_session,
      TextifyTranscribeCppCloseFunction,
      "transcribe_close",
      error_message,
      error_message_capacity);
  TEXTIFY_LOAD_FUNCTION(
      context,
      run_params_init,
      TextifyTranscribeCppRunParamsInitFunction,
      "transcribe_run_params_init",
      error_message,
      error_message_capacity);
  TEXTIFY_LOAD_FUNCTION(
      context,
      run,
      TextifyTranscribeCppRunFunction,
      "transcribe_run",
      error_message,
      error_message_capacity);
  TEXTIFY_LOAD_FUNCTION(
      context,
      full_text,
      TextifyTranscribeCppFullTextFunction,
      "transcribe_full_text",
      error_message,
      error_message_capacity);
  TEXTIFY_LOAD_FUNCTION(
      context,
      get_model,
      TextifyTranscribeCppGetModelFunction,
      "transcribe_get_model",
      error_message,
      error_message_capacity);
  TEXTIFY_LOAD_FUNCTION(
      context,
      backend_device_init,
      TextifyTranscribeCppBackendDeviceInitFunction,
      "transcribe_backend_device_init",
      error_message,
      error_message_capacity);
  TEXTIFY_LOAD_FUNCTION(
      context,
      model_get_device,
      TextifyTranscribeCppModelGetDeviceFunction,
      "transcribe_model_get_device",
      error_message,
      error_message_capacity);
  TEXTIFY_LOAD_FUNCTION(
      context,
      model_supports,
      TextifyTranscribeCppModelSupportsFunction,
      "transcribe_model_supports",
      error_message,
      error_message_capacity);
  TEXTIFY_LOAD_FUNCTION(
      context,
      status_string,
      TextifyTranscribeCppStatusStringFunction,
      "transcribe_status_string",
      error_message,
      error_message_capacity);

  struct transcribe_model_load_params load_params;
  model_load_params_init(&load_params);
  load_params.backend = TRANSCRIBE_BACKEND_METAL;

  struct transcribe_session_params session_params;
  session_params_init(&session_params);
  session_params.n_threads = thread_count;
  session_params.n_ctx = 4096;

  transcribe_status status = open_session(
      model_path,
      &load_params,
      &session_params,
      &context->session);
  if (status != TRANSCRIBE_OK || context->session == NULL) {
    TextifyTranscribeCppSetError(
        error_message,
        error_message_capacity,
        context->status_string(status));
    TextifyTranscribeCppReleasePartialContext(context);
    return NULL;
  }

  const struct transcribe_model *model = context->get_model(context->session);
  struct transcribe_backend_device device;
  context->backend_device_init(&device);
  status = context->model_get_device(model, &device);
  if (status != TRANSCRIBE_OK || device.kind == NULL || strcmp(device.kind, "metal") != 0) {
    TextifyTranscribeCppSetError(
        error_message,
        error_message_capacity,
        "The speech model did not load on the required Metal backend.");
    TextifyTranscribeCppReleasePartialContext(context);
    return NULL;
  }

  return context;
}

TextifyTranscribeCppStatus TextifyTranscribeCppTranscribe(
    TextifyTranscribeCppContext *context,
    const float *samples,
    int32_t sample_count,
    int32_t sample_rate,
    const char *language,
    char **text,
    char *error_message,
    int32_t error_message_capacity) {
  if (text != NULL) {
    *text = NULL;
  }
  if (context == NULL || context->session == NULL || samples == NULL ||
      sample_count <= 0 || sample_rate != 16000 || language == NULL ||
      language[0] == '\0' || text == NULL) {
    TextifyTranscribeCppSetError(
        error_message,
        error_message_capacity,
        "The speech model requires non-empty 16 kHz mono audio and a language policy.");
    return TextifyTranscribeCppStatusInvalidArgument;
  }

  struct transcribe_run_params run_params;
  context->run_params_init(&run_params);
  run_params.task = TRANSCRIBE_TASK_TRANSCRIBE;
  run_params.timestamps = TRANSCRIBE_TIMESTAMPS_NONE;
  const struct transcribe_model *model = context->get_model(context->session);
  run_params.itn = context->model_supports(model, TRANSCRIBE_FEATURE_ITN)
      ? TRANSCRIBE_ITN_MODE_ON
      : TRANSCRIBE_ITN_MODE_DEFAULT;
  run_params.language = strcmp(language, "auto") == 0 ? NULL : language;

  transcribe_status status = context->run(
      context->session,
      samples,
      sample_count,
      &run_params);
  if (status != TRANSCRIBE_OK) {
    TextifyTranscribeCppSetError(
        error_message,
        error_message_capacity,
        context->status_string(status));
    return TextifyTranscribeCppStatusTranscriptionFailed;
  }

  const char *borrowed_text = context->full_text(context->session);
  if (borrowed_text == NULL) {
    TextifyTranscribeCppSetError(
        error_message,
        error_message_capacity,
        "The transcribe.cpp runtime returned no transcript.");
    return TextifyTranscribeCppStatusTranscriptionFailed;
  }
  *text = strdup(borrowed_text);
  if (*text == NULL) {
    TextifyTranscribeCppSetError(error_message, error_message_capacity, "Out of memory.");
    return TextifyTranscribeCppStatusTranscriptionFailed;
  }
  return TextifyTranscribeCppStatusOK;
}

TextifyTranscribeCppStatus TextifyTranscribeCppCopyBackend(
    const TextifyTranscribeCppContext *context,
    char *backend,
    int32_t backend_capacity) {
  if (context == NULL || context->session == NULL || backend == NULL || backend_capacity <= 0) {
    return TextifyTranscribeCppStatusInvalidArgument;
  }
  const struct transcribe_model *model = context->get_model(context->session);
  struct transcribe_backend_device device;
  context->backend_device_init(&device);
  transcribe_status status = context->model_get_device(model, &device);
  if (status != TRANSCRIBE_OK || device.kind == NULL || device.kind[0] == '\0') {
    return TextifyTranscribeCppStatusMetalUnavailable;
  }
  snprintf(backend, (size_t)backend_capacity, "%s", device.kind);
  return TextifyTranscribeCppStatusOK;
}

void TextifyTranscribeCppFreeText(char *text) {
  free(text);
}

void TextifyTranscribeCppDestroy(TextifyTranscribeCppContext *context) {
  TextifyTranscribeCppReleasePartialContext(context);
}
