#include <stdint.h>
#include <stdbool.h>

struct GpuBcpPersistentState {};

extern "C" {
GpuBcpPersistentState* gpu_bcp_init_persistent(
    const int32_t* h_clause_starts,
    const int32_t* h_clause_lengths,
    const int32_t* h_literals,
    uint32_t num_vars,
    uint32_t num_clauses,
    uint32_t total_literals
) {
    return nullptr;
}

int gpu_bcp_launch_async(GpuBcpPersistentState* state, const int8_t* h_assignment) {
    return 0;
}

bool gpu_bcp_poll_status(GpuBcpPersistentState* state) {
    return false;
}

bool gpu_bcp_is_async_in_flight(GpuBcpPersistentState* state) {
    return false;
}

int8_t* gpu_bcp_get_assignment_buffer(GpuBcpPersistentState* state) {
    return nullptr;
}

int gpu_bcp_retrieve_results(
    GpuBcpPersistentState* state,
    int32_t* h_trail,
    int32_t* h_trail_lim,
    uint32_t* h_qhead,
    int32_t* h_conflicting_clause_idx
) {
    return -1;
}

void gpu_bcp_cleanup_persistent(GpuBcpPersistentState* state) {}

int gpu_bcp_solve_sparse(
    const int32_t* h_clause_starts,
    const int32_t* h_clause_lengths,
    const int32_t* h_literals,
    const int8_t* h_assignment,
    uint32_t num_vars,
    uint32_t num_clauses,
    uint32_t total_literals
) {
    return -1;
}

int gpu_bcp_solve(const int8_t* host_matrix, uint32_t num_vars, uint32_t num_clauses) {
    return -1;
}
}
