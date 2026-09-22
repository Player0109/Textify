#include "ggml.h"
#include "ggml-backend.h"
#include "ggml-alloc.h"
#include "ggml-cpu.h"
#include <iostream>

int main() {
    auto cpu = ggml_backend_cpu_init();
    auto ctx = ggml_init({1024 * 1024, nullptr, true});
    if (!cpu || !ctx) return 1;
    auto a = ggml_new_tensor_2d(ctx, GGML_TYPE_F32, 4, 4);
    auto b = ggml_new_tensor_2d(ctx, GGML_TYPE_F32, 4, 4);
    auto graph = ggml_new_graph(ctx);
    ggml_build_forward_expand(graph, ggml_mul_mat(ctx, a, b));
    auto buffer = ggml_backend_alloc_ctx_tensors(ctx, cpu);
    if (!buffer) return 1;
    auto direct = ggml_backend_graph_compute(cpu, graph);
    auto plan = ggml_backend_graph_plan_create(cpu, graph);
    if (!plan) return 1;
    auto planned = ggml_backend_graph_plan_compute(cpu, plan);
    ggml_backend_graph_plan_free(cpu, plan);
    auto sched = ggml_backend_sched_new(&cpu, nullptr, 1, 128, false, true);
    auto scheduled = ggml_backend_sched_graph_compute(sched, graph);
    ggml_backend_sched_free(sched);
    ggml_backend_buffer_free(buffer);
    ggml_free(ctx);
    ggml_backend_free(cpu);
    if (direct != GGML_STATUS_FAILED || planned != GGML_STATUS_FAILED || scheduled != GGML_STATUS_FAILED) return 1;
    std::cout << "Direct, planned and scheduled CPU model computation refused\n";
}
