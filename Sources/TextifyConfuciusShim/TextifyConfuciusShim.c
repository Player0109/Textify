#include "TextifyConfuciusShim.h"
#include "../../Vendor/audio.cpp/9ba8841/include/audiocpp.h"
#include <dlfcn.h>
#include <stdlib.h>
#include <string.h>

struct TextifyConfuciusContext {
    void *library;
    audiocpp_registry *registry;
    audiocpp_model *model;
    audiocpp_session *offline;
    audiocpp_session *stream;
    int64_t offset;
    char *text;
    __typeof__(&audiocpp_options_create) options_create;
    __typeof__(&audiocpp_options_set) options_set;
    __typeof__(&audiocpp_options_free) options_free;
    __typeof__(&audiocpp_abi_version) abi_version;
    __typeof__(&audiocpp_registry_create) registry_create;
    __typeof__(&audiocpp_registry_free) registry_free;
    __typeof__(&audiocpp_model_load) model_load;
    __typeof__(&audiocpp_model_free) model_free;
    __typeof__(&audiocpp_model_supports) model_supports;
    __typeof__(&audiocpp_session_create) session_create;
    __typeof__(&audiocpp_session_free) session_free;
    __typeof__(&audiocpp_session_run) session_run;
    __typeof__(&audiocpp_request_create) request_create;
    __typeof__(&audiocpp_request_free) request_free;
    __typeof__(&audiocpp_request_set_text) request_set_text;
    __typeof__(&audiocpp_request_set_audio) request_set_audio;
    __typeof__(&audiocpp_result_free) result_free;
    __typeof__(&audiocpp_result_text) result_text;
    __typeof__(&audiocpp_stream_start) stream_start;
    __typeof__(&audiocpp_stream_push) stream_push;
    __typeof__(&audiocpp_stream_finish) stream_finish;
    __typeof__(&audiocpp_stream_reset) stream_reset;
    __typeof__(&audiocpp_event_free) event_free;
    __typeof__(&audiocpp_event_as_result) event_as_result;
};

void TextifyConfuciusDestroy(TextifyConfuciusContext *c) {
    if (!c) return;
    if (c->offline) c->session_free(c->offline);
    if (c->stream) c->session_free(c->stream);
    if (c->model) c->model_free(c->model);
    if (c->registry) c->registry_free(c->registry);
    if (c->library) dlclose(c->library);
    free(c->text);
    free(c);
}

TextifyConfuciusContext *TextifyConfuciusCreate(const char *library, const char *model) {
    if (!library || !model) return NULL;
    TextifyConfuciusContext *c = calloc(1, sizeof(*c));
    if (!c) return NULL;
    c->library = dlopen(library, RTLD_NOW | RTLD_LOCAL);
    if (!c->library) goto fail;
    c->options_create = (__typeof__(c->options_create))dlsym(c->library, "audiocpp_options_create");
    if (!c->options_create) goto fail;
    c->options_set = (__typeof__(c->options_set))dlsym(c->library, "audiocpp_options_set");
    if (!c->options_set) goto fail;
    c->options_free = (__typeof__(c->options_free))dlsym(c->library, "audiocpp_options_free");
    if (!c->options_free) goto fail;
    c->abi_version = (__typeof__(c->abi_version))dlsym(c->library, "audiocpp_abi_version");
    if (!c->abi_version) goto fail;
    c->registry_create = (__typeof__(c->registry_create))dlsym(c->library, "audiocpp_registry_create");
    if (!c->registry_create) goto fail;
    c->registry_free = (__typeof__(c->registry_free))dlsym(c->library, "audiocpp_registry_free");
    if (!c->registry_free) goto fail;
    c->model_load = (__typeof__(c->model_load))dlsym(c->library, "audiocpp_model_load");
    if (!c->model_load) goto fail;
    c->model_free = (__typeof__(c->model_free))dlsym(c->library, "audiocpp_model_free");
    if (!c->model_free) goto fail;
    c->model_supports = (__typeof__(c->model_supports))dlsym(c->library, "audiocpp_model_supports");
    if (!c->model_supports) goto fail;
    c->session_create = (__typeof__(c->session_create))dlsym(c->library, "audiocpp_session_create");
    if (!c->session_create) goto fail;
    c->session_free = (__typeof__(c->session_free))dlsym(c->library, "audiocpp_session_free");
    if (!c->session_free) goto fail;
    c->session_run = (__typeof__(c->session_run))dlsym(c->library, "audiocpp_session_run");
    if (!c->session_run) goto fail;
    c->request_create = (__typeof__(c->request_create))dlsym(c->library, "audiocpp_request_create");
    if (!c->request_create) goto fail;
    c->request_free = (__typeof__(c->request_free))dlsym(c->library, "audiocpp_request_free");
    if (!c->request_free) goto fail;
    c->request_set_text = (__typeof__(c->request_set_text))dlsym(c->library, "audiocpp_request_set_text");
    if (!c->request_set_text) goto fail;
    c->request_set_audio = (__typeof__(c->request_set_audio))dlsym(c->library, "audiocpp_request_set_audio");
    if (!c->request_set_audio) goto fail;
    c->result_free = (__typeof__(c->result_free))dlsym(c->library, "audiocpp_result_free");
    if (!c->result_free) goto fail;
    c->result_text = (__typeof__(c->result_text))dlsym(c->library, "audiocpp_result_text");
    if (!c->result_text) goto fail;
    c->stream_start = (__typeof__(c->stream_start))dlsym(c->library, "audiocpp_stream_start");
    if (!c->stream_start) goto fail;
    c->stream_push = (__typeof__(c->stream_push))dlsym(c->library, "audiocpp_stream_push");
    if (!c->stream_push) goto fail;
    c->stream_finish = (__typeof__(c->stream_finish))dlsym(c->library, "audiocpp_stream_finish");
    if (!c->stream_finish) goto fail;
    c->stream_reset = (__typeof__(c->stream_reset))dlsym(c->library, "audiocpp_stream_reset");
    if (!c->stream_reset) goto fail;
    c->event_free = (__typeof__(c->event_free))dlsym(c->library, "audiocpp_event_free");
    if (!c->event_free) goto fail;
    c->event_as_result = (__typeof__(c->event_as_result))dlsym(c->library, "audiocpp_event_as_result");
    if (!c->event_as_result) goto fail;
    if (c->abi_version() != 0x000200) goto fail;
    if (c->registry_create(NULL, &c->registry) != AUDIOCPP_OK) goto fail;
    audiocpp_model_config config = {.family_hint = "confucius4_r2t2"};
    if (c->model_load(c->registry, model, &config, NULL, &c->model) != AUDIOCPP_OK) goto fail;
    if (!c->model_supports(c->model, "asr", "streaming")) goto fail;
    audiocpp_backend_config backend = {.backend = "metal", .device = 0, .threads = 4};
    if (c->session_create(c->model, "asr", "offline", &backend, NULL, &c->offline) != AUDIOCPP_OK) goto fail;
    audiocpp_options *options = c->options_create();
    if (!options) goto fail;
    int configured =
        c->options_set(options, "confucius4_r2t2.chunk_size_ms", "320") == AUDIOCPP_OK &&
        c->options_set(options, "confucius4_r2t2.unfixed_chunk_num", "0") == AUDIOCPP_OK &&
        c->options_set(options, "confucius4_r2t2.unfixed_token_num", "1") == AUDIOCPP_OK;
    audiocpp_status stream_status = configured
        ? c->session_create(c->model, "asr", "streaming", &backend, options, &c->stream)
        : AUDIOCPP_ERR_INVALID_ARGUMENT;
    c->options_free(options);
    if (stream_status != AUDIOCPP_OK) goto fail;
    return c;
fail:
    TextifyConfuciusDestroy(c);
    return NULL;
}

static const char *copy_text(TextifyConfuciusContext *c, const audiocpp_result *result) {
    const char *text = NULL;
    audiocpp_status status = c->result_text(result, &text, NULL);
    if (status != AUDIOCPP_OK && status != AUDIOCPP_ERR_NOT_AVAILABLE) return NULL;
    free(c->text);
    c->text = strdup(text ? text : "");
    return c->text;
}

static audiocpp_request *request(TextifyConfuciusContext *c, const char *language,
                                 const float *samples, int32_t count) {
    audiocpp_request *r = c->request_create();
    if (!r) return NULL;
    if (c->request_set_text(r, "", language) != AUDIOCPP_OK ||
        c->request_set_audio(r, samples, (size_t)count, 16000, 1) != AUDIOCPP_OK) {
        c->request_free(r);
        return NULL;
    }
    return r;
}

const char *TextifyConfuciusTranscribe(TextifyConfuciusContext *c, const float *samples,
                                     int32_t count, const char *language) {
    if (!c || !samples || count <= 0) return NULL;
    audiocpp_request *r = request(c, language, samples, count);
    if (!r) return NULL;
    audiocpp_result *result = NULL;
    audiocpp_status status = c->session_run(c->offline, r, &result);
    c->request_free(r);
    const char *text = status == AUDIOCPP_OK && result ? copy_text(c, result) : NULL;
    c->result_free(result);
    return text;
}

int32_t TextifyConfuciusStart(TextifyConfuciusContext *c, const char *language) {
    if (!c) return 0;
    audiocpp_request *r = request(c, language, NULL, 0);
    if (!r) return 0;
    audiocpp_status status = c->stream_start(c->stream, r);
    c->request_free(r);
    c->offset = 0;
    return status == AUDIOCPP_OK;
}

const char *TextifyConfuciusPush(TextifyConfuciusContext *c, const float *samples, int32_t count) {
    if (!c || !samples || count <= 0) return NULL;
    audiocpp_event *event = NULL;
    audiocpp_status status = c->stream_push(c->stream, samples, (size_t)count, 16000, 1, c->offset, &event);
    c->offset += count;
    if (status != AUDIOCPP_OK) { c->event_free(event); return NULL; }
    const char *text = event ? copy_text(c, c->event_as_result(event)) : "";
    c->event_free(event);
    return text;
}

const char *TextifyConfuciusFinish(TextifyConfuciusContext *c) {
    if (!c) return NULL;
    audiocpp_result *result = NULL;
    audiocpp_status status = c->stream_finish(c->stream, &result);
    const char *text = status == AUDIOCPP_OK && result ? copy_text(c, result) : NULL;
    c->result_free(result);
    return text;
}

void TextifyConfuciusReset(TextifyConfuciusContext *c) {
    if (c) c->stream_reset(c->stream);
}
