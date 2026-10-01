#include "whisper.h"
#include "ggml.h"
#include "ggml-backend.h"
#include "ggml-cpu.h"
#include <algorithm>
#include <cstdint>
#include <cstring>
#include <fstream>
#include <iostream>
#include <iterator>
#include <vector>

// Speech detection runs on the CPU by design; every other scheduler must still refuse CPU graphs.
static double speech(whisper_vad_context *vad, std::vector<float> samples) {
    if (!whisper_vad_detect_speech(vad, samples.data(), int(samples.size()))) return -1;
    int windows = 0;
    for (int i = 0; i < whisper_vad_n_probs(vad); ++i) windows += whisper_vad_probs(vad)[i] >= 0.5f;
    return windows * 512 / 16000.0;
}

int main(int argc, char **argv) {
    if (argc != 3) return 2;
    whisper_log_set([](ggml_log_level, const char *, void *) {}, nullptr);
    auto config = whisper_vad_default_context_params();
    config.n_threads = 1;
    auto vad = whisper_vad_init_from_file_with_params(argv[1], config);
    if (!vad) {
        std::cerr << "The speech model did not load on the CPU\n";
        return 1;
    }
    // whisper.cpp's samples/jfk.wav: 16-bit mono PCM at 16 kHz.
    std::ifstream file(argv[2], std::ios::binary);
    std::vector<char> wav((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());
    std::vector<float> samples;
    for (size_t at = 12; at + 8 <= wav.size();) {
        uint32_t size;
        std::memcpy(&size, &wav[at + 4], 4);
        if (std::memcmp(&wav[at], "data", 4) == 0) {
            for (size_t i = at + 8; i + 2 <= std::min(wav.size(), at + 8 + size); i += 2) {
                int16_t value;
                std::memcpy(&value, &wav[i], 2);
                samples.push_back(value / 32768.0f);
            }
            break;
        }
        at += 8 + size + (size & 1);
    }
    const double heard = speech(vad, samples), silence = speech(vad, std::vector<float>(32000));
    whisper_vad_free(vad);
    if (heard < 5 || silence != 0) {
        std::cerr << "Speech detection failed: " << heard << " s in the sample, " << silence << " s in silence\n";
        return 1;
    }
    // The exception belongs to the speech detector's scheduler only.
    auto cpu = ggml_backend_cpu_init();
    auto ctx = ggml_init({1024 * 1024, nullptr, true});
    auto a = ggml_new_tensor_2d(ctx, GGML_TYPE_F32, 4, 4);
    auto b = ggml_new_tensor_2d(ctx, GGML_TYPE_F32, 4, 4);
    auto graph = ggml_new_graph(ctx);
    ggml_build_forward_expand(graph, ggml_mul_mat(ctx, a, b));
    auto sched = ggml_backend_sched_new(&cpu, nullptr, 1, 128, false, true);
    if (!ggml_backend_sched_alloc_graph(sched, graph)) return 1;
    const auto status = ggml_backend_sched_graph_compute(sched, graph);
    ggml_backend_sched_free(sched);
    ggml_free(ctx);
    ggml_backend_free(cpu);
    if (status != GGML_STATUS_FAILED) {
        std::cerr << "CPU graph execution was not blocked after speech detection\n";
        return 1;
    }
    std::cout << "Speech detected on the CPU (" << heard << " s); other CPU graphs still refused\n";
}
