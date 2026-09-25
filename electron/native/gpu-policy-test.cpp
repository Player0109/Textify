#include "ggml.h"
#include "ggml-backend.h"
#include "ggml-cpu.h"
#include <iostream>

int main() {
    auto cpu = ggml_backend_cpu_init();
    if (!cpu) return 1;
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
        std::cerr << "CPU graph execution was not blocked\n";
        return 1;
    }
    std::cout << "CPU model graph refused before computation\n";
}
