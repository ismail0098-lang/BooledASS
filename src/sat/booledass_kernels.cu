/* ════════════════════════════════════════════════════════════════════
 *  BooledASS Tensor Core BCP Pipeline
 *  Target: sm_89 (Ada Lovelace / RTX 4070 Ti SUPER)
 *
 *  Replaces per-thread clause scanning with warp-cooperative WMMA
 *  INT8 GEMM. Two matrix products per BCP iteration:
 *
 *    score[c] = Σ_v  A[c][v] · b[v]     (satisfaction signal)
 *    mask[c]  = Σ_v |A[c][v]|·|b[v]|    (assigned-literal count)
 *
 *  Post-MMA classification:
 *    SATISFIED:   score + mask > 0   (at least one literal true)
 *    CONFLICT:    score == -num_lits  (all assigned, all falsified)
 *    UNIT:        score == -mask  AND  mask == num_lits - 1
 *    UNRESOLVED:  otherwise
 *
 *  Unit clause propagation writes forced assignments directly to
 *  the device-resident assignment vector via word-aligned atomicCAS.
 * ════════════════════════════════════════════════════════════════════ */

#include <cuda_runtime.h>
#include <mma.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

using namespace nvcuda;

struct TileCoord {
    uint32_t m_tile;
    uint32_t k_tile;
};

/* ── Compile-time constants ──────────────────────────────────────── */
#define TC_M           16       /* WMMA tile rows    (clauses)   */
#define TC_N           16       /* WMMA tile columns (broadcast) */
#define TC_K           16       /* WMMA tile depth   (variables) */
#define WARPS_PER_BLK   8       /* 256 threads / 32             */
#define THREADS_PER_BLK (WARPS_PER_BLK * 32)
#define MAX_BCP_ITERS  4096
#define UNIT_QUEUE_CAP 65536    /* max unit propagations/iter   */

/* ── Align helpers ───────────────────────────────────────────────── */
__host__ __device__ __forceinline__
uint32_t align_up(uint32_t v, uint32_t a) { return (v + a - 1) & ~(a - 1); }

/* ════════════════════════════════════════════════════════════════════
 *  KERNEL 1:  tc_gemm_score
 *
 *  Computes  C_score[m] = Σ_k  A[m][k] · b[k]
 *  using WMMA m16n16k16 int8 → int32.
 *
 *  Grid:  1D, one warp per M-tile (16 clauses).
 *  B is broadcast: all N columns of each tile are identical,
 *  constructed in shared memory from the assignment vector.
 * ════════════════════════════════════════════════════════════════════ */
__global__ void __launch_bounds__(THREADS_PER_BLK)
tc_gemm_score(
    const int8_t* __restrict__ A,          /* [M_pad × K_pad] row-major        */
    const int8_t* __restrict__ b_vec,      /* [K_pad]          assignment vec   */
    int32_t*      __restrict__ C_col0,     /* [M_pad]          score output     */
    uint32_t M_pad,
    uint32_t K_pad)
{
    const uint32_t warp_id_global = (blockIdx.x * blockDim.x + threadIdx.x) / 32;
    const uint32_t lane           = threadIdx.x & 31;
    const uint32_t warp_in_block  = threadIdx.x / 32;
    const uint32_t m_tile         = warp_id_global;   /* each warp owns one 16-row tile */

    if (m_tile * TC_M >= M_pad) return;

    /* ── Shared memory: broadcast B tile (K×N = 16×16 bytes) ───── */
    extern __shared__ int8_t smem[];
    int8_t* s_b = smem + warp_in_block * (TC_K * TC_N);   /* 256 B per warp */

    /* ── Accumulator ───────────────────────────────────────────── */
    wmma::fragment<wmma::accumulator, TC_M, TC_N, TC_K, int32_t> acc;
    wmma::fill_fragment(acc, 0);

    /* ── Tile over K dimension ─────────────────────────────────── */
    for (uint32_t k = 0; k < K_pad; k += TC_K) {

        /* Load A tile directly from global (row-major, ld = K_pad) */
        wmma::fragment<wmma::matrix_a, TC_M, TC_N, TC_K, int8_t, wmma::row_major> a_frag;
        const int8_t* a_ptr = A + (uint64_t)m_tile * TC_M * K_pad + k;
        wmma::load_matrix_sync(a_frag, a_ptr, K_pad);

        /* Build broadcast B tile in shared memory (col-major: ld = TC_K)
           Each of the 16 columns is a copy of b_vec[k .. k+15].
           32 threads in the warp fill 256 bytes (8 bytes each). */
        #pragma unroll
        for (int i = lane; i < TC_K * TC_N; i += 32) {
            int row = i % TC_K;          /* variable index within tile */
            s_b[i] = b_vec[k + row];     /* col-major: s_b[row + col*TC_K] */
        }
        __syncwarp();

        wmma::fragment<wmma::matrix_b, TC_M, TC_N, TC_K, int8_t, wmma::col_major> b_frag;
        wmma::load_matrix_sync(b_frag, s_b, TC_K);

        wmma::mma_sync(acc, a_frag, b_frag, acc);
    }

    /* ── Store column 0 of the 16×16 accumulator ───────────────── */
    /* Write full tile to shared, then extract column 0.           */
    int32_t* s_c = (int32_t*)(smem + WARPS_PER_BLK * TC_K * TC_N);
    int32_t* s_tile = s_c + warp_in_block * (TC_M * TC_N);

    wmma::store_matrix_sync(s_tile, acc, TC_N, wmma::mem_row_major);
    __syncwarp();

    /* Column 0 extraction: lane 0..15 each grab one row */
    if (lane < TC_M) {
        uint32_t global_row = m_tile * TC_M + lane;
        if (global_row < M_pad) {
            C_col0[global_row] = s_tile[lane * TC_N]; /* row * stride + col 0 */
        }
    }
}

/* ════════════════════════════════════════════════════════════════════
 *  KERNEL 2:  tc_gemm_mask
 *
 *  Computes  mask[m] = Σ_k |A[m][k]| · |b[k]|
 *  Identical structure to tc_gemm_score, but operates on the
 *  precomputed absolute-value matrix and vector.
 * ════════════════════════════════════════════════════════════════════ */
__global__ void __launch_bounds__(THREADS_PER_BLK)
tc_gemm_mask(
    const int8_t* __restrict__ A_abs,      /* [M_pad × K_pad] |clause matrix| */
    const int8_t* __restrict__ b_abs,      /* [K_pad]         |assignments|   */
    int32_t*      __restrict__ mask_out,   /* [M_pad]                         */
    uint32_t M_pad,
    uint32_t K_pad)
{
    const uint32_t warp_id_global = (blockIdx.x * blockDim.x + threadIdx.x) / 32;
    const uint32_t lane           = threadIdx.x & 31;
    const uint32_t warp_in_block  = threadIdx.x / 32;
    const uint32_t m_tile         = warp_id_global;

    if (m_tile * TC_M >= M_pad) return;

    extern __shared__ int8_t smem[];
    int8_t* s_b = smem + warp_in_block * (TC_K * TC_N);

    wmma::fragment<wmma::accumulator, TC_M, TC_N, TC_K, int32_t> acc;
    wmma::fill_fragment(acc, 0);

    for (uint32_t k = 0; k < K_pad; k += TC_K) {
        wmma::fragment<wmma::matrix_a, TC_M, TC_N, TC_K, int8_t, wmma::row_major> a_frag;
        wmma::load_matrix_sync(a_frag, A_abs + (uint64_t)m_tile * TC_M * K_pad + k, K_pad);

        #pragma unroll
        for (int i = lane; i < TC_K * TC_N; i += 32) {
            s_b[i] = b_abs[k + (i % TC_K)];
        }
        __syncwarp();

        wmma::fragment<wmma::matrix_b, TC_M, TC_N, TC_K, int8_t, wmma::col_major> b_frag;
        wmma::load_matrix_sync(b_frag, s_b, TC_K);

        wmma::mma_sync(acc, a_frag, b_frag, acc);
    }

    int32_t* s_c = (int32_t*)(smem + WARPS_PER_BLK * TC_K * TC_N);
    int32_t* s_tile = s_c + warp_in_block * (TC_M * TC_N);
    wmma::store_matrix_sync(s_tile, acc, TC_N, wmma::mem_row_major);
    __syncwarp();

    if (lane < TC_M) {
        uint32_t row = m_tile * TC_M + lane;
        if (row < M_pad) {
            mask_out[row] = s_tile[lane * TC_N];
        }
    }
}

/* ════════════════════════════════════════════════════════════════════
 *  KERNEL 3:  tc_post_scan
 *
 *  Warp-cooperative post-GEMM pass.  For each clause:
 *    1. Classify: satisfied / conflict / unit / unresolved
 *    2. For unit clauses, scan the clause row to find the single
 *       unassigned literal, push (var_index, polarity) to queue.
 *    3. For conflicts, set a global conflict flag.
 *
 *  Queue push uses warp-level ballot + prefix-sum to coalesce
 *  atomic operations: one atomicAdd per warp, not per thread.
 * ════════════════════════════════════════════════════════════════════ */
struct UnitEntry {
    int32_t var_idx;    /* variable to force          */
    int8_t  polarity;   /* +1 = true, -1 = false      */
    int8_t  _pad[3];
};

__global__ void __launch_bounds__(256)
tc_post_scan(
    const int32_t* __restrict__ scores,     /* [M_pad]              */
    const int32_t* __restrict__ masks,      /* [M_pad]              */
    const uint16_t* __restrict__ num_lits,  /* [M_pad] precomputed  */
    const int8_t*  __restrict__ A,          /* [M_pad × K_pad]      */
    const int8_t*  __restrict__ b_vec,      /* [K_pad] assignments  */
    UnitEntry*     __restrict__ unit_queue,  /* [UNIT_QUEUE_CAP]     */
    uint32_t*      __restrict__ unit_count,  /* atomic counter       */
    int32_t*       __restrict__ conflict_flag,
    uint32_t M_real,                         /* actual clause count  */
    uint32_t K_pad)
{
    uint32_t cid  = blockIdx.x * blockDim.x + threadIdx.x;
    uint32_t lane = threadIdx.x & 31;

    /* ── Per-thread classification ─────────────────────────────── */
    bool is_unit     = false;
    int  unit_var    = -1;
    int8_t unit_pol  = 0;

    if (cid < M_real) {
        int32_t  s = scores[cid];
        int32_t  m = masks[cid];
        uint16_t n = num_lits[cid];

        if (s + m > 0) {
            /* SATISFIED — at least one literal true. Skip. */
        } else {
            /* s == -m  (all assigned literals are falsified) */
            if (m == (int32_t)n) {
                /* CONFLICT: every literal assigned and falsified */
                atomicExch(conflict_flag, 1);
            } else if (m == (int32_t)n - 1) {
                /* UNIT: exactly one unassigned literal, rest falsified.
                   Scan the clause row to find the unassigned variable. */
                is_unit = true;
                const int8_t* row = A + (uint64_t)cid * K_pad;
                for (uint32_t v = 0; v < K_pad; v++) {
                    int8_t lit = row[v];
                    if (lit != 0 && b_vec[v] == 0) {
                        unit_var = (int)v;
                        unit_pol = (lit > 0) ? (int8_t)1 : (int8_t)-1;
                        break;
                    }
                }
                if (unit_var < 0) is_unit = false; /* safety */
            }
            /* else: UNRESOLVED — not enough info for BCP */
        }
    }

    /* ── Warp-coalesced queue push ──────────────────────────────── *
     *  ballot_sync identifies which lanes found unit clauses.       *
     *  One atomicAdd per warp reserves a contiguous queue segment,  *
     *  then each contributing lane writes its entry at its offset.  *
     * ────────────────────────────────────────────────────────────── */
    uint32_t unit_mask = __ballot_sync(0xFFFFFFFF, is_unit);
    uint32_t unit_cnt  = __popc(unit_mask);

    if (unit_cnt > 0) {
        uint32_t warp_base;  /* queue index for this warp's block */
        if (lane == 0) {
            warp_base = atomicAdd(unit_count, unit_cnt);
        }
        warp_base = __shfl_sync(0xFFFFFFFF, warp_base, 0);

        if (is_unit) {
            /* prefix offset within the warp's allocation */
            uint32_t lower_mask = (1u << lane) - 1u;
            uint32_t offset     = __popc(unit_mask & lower_mask);
            uint32_t slot       = warp_base + offset;
            if (slot < UNIT_QUEUE_CAP) {
                unit_queue[slot].var_idx  = unit_var;
                unit_queue[slot].polarity = unit_pol;
            }
        }
    }
}

/* ════════════════════════════════════════════════════════════════════
 *  KERNEL 4:  tc_propagate
 *
 *  Drains the unit queue and writes forced assignments into b_vec.
 *  Uses word-aligned atomicCAS for byte-level conflict detection.
 * ════════════════════════════════════════════════════════════════════ */
__global__ void tc_propagate(
    const UnitEntry* __restrict__ unit_queue,
    uint32_t queue_len,
    int8_t*  __restrict__ b_vec,
    int8_t*  __restrict__ b_abs,
    int32_t* __restrict__ conflict_flag)
{
    uint32_t tid = blockIdx.x * blockDim.x + threadIdx.x;
    if (tid >= queue_len) return;

    int32_t var = unit_queue[tid].var_idx;
    int8_t  pol = unit_queue[tid].polarity;
    if (var < 0 || pol == 0) return;

    /* Word-aligned byte CAS */
    unsigned int* word = (unsigned int*)((size_t)&b_vec[var] & ~3ULL);
    unsigned int byte_off = (unsigned int)((size_t)&b_vec[var] & 3ULL);
    unsigned int shift    = byte_off * 8;
    unsigned int mask     = 0xFFu << shift;

    unsigned int old_w = *word;
    unsigned int old_byte;
    unsigned int new_w;

    do {
        old_byte = (old_w >> shift) & 0xFF;
        if (old_byte != 0) break;
        new_w = (old_w & ~mask) | (((unsigned int)(unsigned char)pol) << shift);
    } while ((old_w = atomicCAS(word, old_w, new_w)) != old_w);

    int8_t prev = (int8_t)(unsigned char)old_byte;
    if (prev == 0) {
        /* Success — also update abs vector */
        b_abs[var] = 1;
    } else if (prev != pol) {
        /* Conflict: forced to opposite value */
        atomicExch(conflict_flag, 1);
    }
}

/* ════════════════════════════════════════════════════════════════════
 *  KERNEL 5:  build_abs_vector
 *
 *  Computes |b[v]| from the signed assignment vector.
 *  Simple element-wise: 0 → 0, ±1 → 1.
 * ════════════════════════════════════════════════════════════════════ */
__global__ void build_abs_vector(
    const int8_t* __restrict__ b,
    int8_t*       __restrict__ b_abs,
    uint32_t len)
{
    uint32_t i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < len) {
        b_abs[i] = (b[i] != 0) ? (int8_t)1 : (int8_t)0;
    }
}

/* ════════════════════════════════════════════════════════════════════
 *  SPARSE KERNEL 1:  tc_gemm_score_sparse
 *
 *  Computes  C_score[m] = Σ_k  A[m][k] · b[k]
 *  using WMMA m16n16k16 int8 → int32.
 *  Only loops over active tiles.
 * ════════════════════════════════════════════════════════════════════ */
__global__ void __launch_bounds__(THREADS_PER_BLK)
tc_gemm_score_sparse(
    const int8_t* __restrict__ active_tiles_data, /* [num_active_tiles * 256] */
    const int8_t* __restrict__ b_vec,             /* [K_pad] */
    int32_t*      __restrict__ C_col0,            /* [M_pad] */
    const TileCoord* __restrict__ active_tiles,   /* [num_active_tiles] */
    const uint32_t* __restrict__ m_tile_start,     /* [M_pad/16 + 1] */
    uint32_t M_pad)
{
    const uint32_t warp_id_global = (blockIdx.x * blockDim.x + threadIdx.x) / 32;
    const uint32_t lane           = threadIdx.x & 31;
    const uint32_t warp_in_block  = threadIdx.x / 32;
    const uint32_t m_tile         = warp_id_global;

    if (m_tile * TC_M >= M_pad) return;

    extern __shared__ int8_t smem[];
    int8_t* s_b = smem + warp_in_block * (TC_K * TC_N);

    wmma::fragment<wmma::accumulator, TC_M, TC_N, TC_K, int32_t> acc;
    wmma::fill_fragment(acc, 0);

    uint32_t start_idx = m_tile_start[m_tile];
    uint32_t end_idx   = m_tile_start[m_tile + 1];

    for (uint32_t idx = start_idx; idx < end_idx; ++idx) {
        TileCoord tc = active_tiles[idx];
        uint32_t kt = tc.k_tile;
        uint32_t k_base = kt * TC_K;

        wmma::fragment<wmma::matrix_a, TC_M, TC_N, TC_K, int8_t, wmma::row_major> a_frag;
        wmma::load_matrix_sync(a_frag, active_tiles_data + idx * 256, TC_N);

        #pragma unroll
        for (int i = lane; i < TC_K * TC_N; i += 32) {
            s_b[i] = b_vec[k_base + (i % TC_K)];
        }
        __syncwarp();

        wmma::fragment<wmma::matrix_b, TC_M, TC_N, TC_K, int8_t, wmma::col_major> b_frag;
        wmma::load_matrix_sync(b_frag, s_b, TC_K);

        wmma::mma_sync(acc, a_frag, b_frag, acc);
    }

    int32_t* s_c = (int32_t*)(smem + WARPS_PER_BLK * TC_K * TC_N);
    int32_t* s_tile = s_c + warp_in_block * (TC_M * TC_N);

    wmma::store_matrix_sync(s_tile, acc, TC_N, wmma::mem_row_major);
    __syncwarp();

    if (lane < TC_M) {
        uint32_t global_row = m_tile * TC_M + lane;
        if (global_row < M_pad) {
            C_col0[global_row] = s_tile[lane * TC_N];
        }
    }
}

/* ════════════════════════════════════════════════════════════════════
 *  SPARSE KERNEL 2:  tc_gemm_mask_sparse
 *
 *  Computes  mask[m] = Σ_k |A[m][k]| · |b[k]|
 *  Only loops over active tiles.
 * ════════════════════════════════════════════════════════════════════ */
__global__ void __launch_bounds__(THREADS_PER_BLK)
tc_gemm_mask_sparse(
    const int8_t* __restrict__ active_tiles_abs_data,
    const int8_t* __restrict__ b_abs,
    int32_t*      __restrict__ mask_out,
    const TileCoord* __restrict__ active_tiles,
    const uint32_t* __restrict__ m_tile_start,
    uint32_t M_pad)
{
    const uint32_t warp_id_global = (blockIdx.x * blockDim.x + threadIdx.x) / 32;
    const uint32_t lane           = threadIdx.x & 31;
    const uint32_t warp_in_block  = threadIdx.x / 32;
    const uint32_t m_tile         = warp_id_global;

    if (m_tile * TC_M >= M_pad) return;

    extern __shared__ int8_t smem[];
    int8_t* s_b = smem + warp_in_block * (TC_K * TC_N);

    wmma::fragment<wmma::accumulator, TC_M, TC_N, TC_K, int32_t> acc;
    wmma::fill_fragment(acc, 0);

    uint32_t start_idx = m_tile_start[m_tile];
    uint32_t end_idx   = m_tile_start[m_tile + 1];

    for (uint32_t idx = start_idx; idx < end_idx; ++idx) {
        TileCoord tc = active_tiles[idx];
        uint32_t kt = tc.k_tile;
        uint32_t k_base = kt * TC_K;

        wmma::fragment<wmma::matrix_a, TC_M, TC_N, TC_K, int8_t, wmma::row_major> a_frag;
        wmma::load_matrix_sync(a_frag, active_tiles_abs_data + idx * 256, TC_N);

        #pragma unroll
        for (int i = lane; i < TC_K * TC_N; i += 32) {
            s_b[i] = b_abs[k_base + (i % TC_K)];
        }
        __syncwarp();

        wmma::fragment<wmma::matrix_b, TC_M, TC_N, TC_K, int8_t, wmma::col_major> b_frag;
        wmma::load_matrix_sync(b_frag, s_b, TC_K);

        wmma::mma_sync(acc, a_frag, b_frag, acc);
    }

    int32_t* s_c = (int32_t*)(smem + WARPS_PER_BLK * TC_K * TC_N);
    int32_t* s_tile = s_c + warp_in_block * (TC_M * TC_N);
    wmma::store_matrix_sync(s_tile, acc, TC_N, wmma::mem_row_major);
    __syncwarp();

    if (lane < TC_M) {
        uint32_t row = m_tile * TC_M + lane;
        if (row < M_pad) {
            mask_out[row] = s_tile[lane * TC_N];
        }
    }
}

/* ════════════════════════════════════════════════════════════════════
 *  SPARSE KERNEL 3:  tc_post_scan_sparse
 *
 *  Post-GEMM pass. Only scans active tile columns for the unit clause.
 * ════════════════════════════════════════════════════════════════════ */
__global__ void __launch_bounds__(256)
tc_post_scan_sparse(
    const int32_t* __restrict__ scores,
    const int32_t* __restrict__ masks,
    const uint16_t* __restrict__ num_lits,
    const int8_t*  __restrict__ active_tiles_data,
    const int8_t*  __restrict__ b_vec,
    const TileCoord* __restrict__ active_tiles,
    const uint32_t* __restrict__ m_tile_start,
    UnitEntry*     __restrict__ unit_queue,
    uint32_t*      __restrict__ unit_count,
    int32_t*       __restrict__ conflict_flag,
    uint32_t M_real,
    uint32_t M_pad)
{
    uint32_t cid  = blockIdx.x * blockDim.x + threadIdx.x;
    uint32_t lane = threadIdx.x & 31;

    bool is_unit     = false;
    int  unit_var    = -1;
    int8_t unit_pol  = 0;

    if (cid < M_real) {
        int32_t  s = scores[cid];
        int32_t  m = masks[cid];
        uint16_t n = num_lits[cid];

        if (s + m > 0) {
            /* SATISFIED */
        } else {
            if (m == (int32_t)n) {
                /* CONFLICT */
                atomicExch(conflict_flag, 1);
            } else if (m == (int32_t)n - 1) {
                /* UNIT */
                is_unit = true;
                uint32_t m_tile = cid / 16;
                uint32_t m_row  = cid % 16;
                uint32_t start_idx = m_tile_start[m_tile];
                uint32_t end_idx   = m_tile_start[m_tile + 1];

                for (uint32_t idx = start_idx; idx < end_idx; ++idx) {
                    TileCoord tc = active_tiles[idx];
                    uint32_t kt = tc.k_tile;
                    const int8_t* tile_row = active_tiles_data + idx * 256 + m_row * 16;

                    for (uint32_t c = 0; c < 16; ++c) {
                        int8_t lit = tile_row[c];
                        uint32_t v = kt * 16 + c;
                        if (lit != 0 && b_vec[v] == 0) {
                            unit_var = (int)v;
                            unit_pol = (lit > 0) ? (int8_t)1 : (int8_t)-1;
                            break;
                        }
                    }
                    if (unit_var >= 0) break;
                }
                if (unit_var < 0) is_unit = false;
            }
        }
    }

    uint32_t unit_mask = __ballot_sync(0xFFFFFFFF, is_unit);
    uint32_t unit_cnt  = __popc(unit_mask);

    uint32_t warp_base;
    if (lane == 0 && unit_cnt > 0) {
        warp_base = atomicAdd(unit_count, unit_cnt);
    }
    warp_base = __shfl_sync(0xFFFFFFFF, warp_base, 0);

    if (is_unit) {
        uint32_t lower_mask = (1u << lane) - 1u;
        uint32_t offset     = __popc(unit_mask & lower_mask);
        uint32_t slot       = warp_base + offset;
        if (slot < UNIT_QUEUE_CAP) {
            unit_queue[slot].var_idx  = unit_var;
            unit_queue[slot].polarity = unit_pol;
        }
    }
}


/* ════════════════════════════════════════════════════════════════════
 *  HOST ENTRY POINT:  gpu_bcp_solve
 *
 *  Allocates device memory with WMMA-aligned layout, runs the
 *  Tensor Core BCP loop, and returns SAT/UNSAT/UNDEF.
 * ════════════════════════════════════════════════════════════════════ */
extern "C" {

int gpu_bcp_solve(
    const int8_t* host_matrix,   /* [num_clauses × num_vars] row-major, unpadded */
    uint32_t num_vars,
    uint32_t num_clauses)
{
    if (num_clauses == 0) return 1;
    if (num_vars == 0)    return 0;

    int result = -1;  /* UNDEF */

    /* ── 1.  Pad dimensions to WMMA tile boundaries ────────────── */
    uint32_t M_pad = align_up(num_clauses, TC_M);  /* clause dim  */
    uint32_t K_pad = align_up(num_vars,    TC_K);   /* variable dim */

    size_t A_bytes     = (size_t)M_pad * K_pad;
    size_t b_bytes     = K_pad;
    size_t score_bytes = M_pad * sizeof(int32_t);
    size_t lits_bytes  = M_pad * sizeof(uint16_t);
    size_t queue_bytes = UNIT_QUEUE_CAP * sizeof(UnitEntry);

    /* ── 2.  Host: build padded A, |A|, num_lits ───────────────── */
    int8_t*   h_A     = (int8_t*)calloc(A_bytes, 1);
    int8_t*   h_Aabs  = (int8_t*)calloc(A_bytes, 1);
    uint16_t* h_lits  = (uint16_t*)calloc(M_pad, sizeof(uint16_t));

    if (!h_A || !h_Aabs || !h_lits) {
        fprintf(stderr, "[tc-bcp] host allocation failed (requested %llu bytes)\n", (unsigned long long)A_bytes);
        goto cleanup;
    }

    for (uint32_t c = 0; c < num_clauses; c++) {
        uint16_t count = 0;
        for (uint32_t v = 0; v < num_vars; v++) {
            int8_t val = host_matrix[(size_t)c * num_vars + v];
            h_A[(size_t)c * K_pad + v]    = val;
            h_Aabs[(size_t)c * K_pad + v] = (val < 0) ? (int8_t)1 :
                                             (val > 0) ? (int8_t)1 : (int8_t)0;
            if (val != 0) count++;
        }
        h_lits[c] = count;
    }

    /* ── 3.  Device allocation ─────────────────────────────────── */
    int8_t*      d_A       = NULL;
    int8_t*      d_Aabs    = NULL;
    int8_t*      d_b       = NULL;
    int8_t*      d_b_abs   = NULL;
    int32_t*     d_scores  = NULL;
    int32_t*     d_masks   = NULL;
    uint16_t*    d_lits    = NULL;
    UnitEntry*   d_queue   = NULL;
    uint32_t*    d_qcount  = NULL;
    int32_t*     d_conflict= NULL;

    cudaError_t e;
    #define CMALLOC(ptr, sz) do { \
        e = cudaMalloc(&(ptr), (sz)); \
        if (e != cudaSuccess) { \
            fprintf(stderr, "[tc-bcp] cudaMalloc failed: %s\n", cudaGetErrorString(e)); \
            goto cleanup; \
        } \
    } while(0)

    CMALLOC(d_A,        A_bytes);
    CMALLOC(d_Aabs,     A_bytes);
    CMALLOC(d_b,        b_bytes);
    CMALLOC(d_b_abs,    b_bytes);
    CMALLOC(d_scores,   score_bytes);
    CMALLOC(d_masks,    score_bytes);
    CMALLOC(d_lits,     lits_bytes);
    CMALLOC(d_queue,    queue_bytes);
    CMALLOC(d_qcount,   sizeof(uint32_t));
    CMALLOC(d_conflict, sizeof(int32_t));
    #undef CMALLOC

    /* ── 4.  Upload static data ────────────────────────────────── */
    cudaMemcpy(d_A,    h_A,    A_bytes,    cudaMemcpyHostToDevice);
    cudaMemcpy(d_Aabs, h_Aabs, A_bytes,    cudaMemcpyHostToDevice);
    cudaMemcpy(d_lits, h_lits, lits_bytes, cudaMemcpyHostToDevice);
    cudaMemset(d_b,       0, b_bytes);
    cudaMemset(d_b_abs,   0, b_bytes);
    cudaMemset(d_conflict, 0, sizeof(int32_t));

    free(h_A);    h_A    = NULL;
    free(h_Aabs); h_Aabs = NULL;
    free(h_lits); h_lits = NULL;

    /* ── 5.  Kernel launch geometry ────────────────────────────── */
    uint32_t num_m_tiles = M_pad / TC_M;
    uint32_t warps_total = num_m_tiles;
    uint32_t gemm_threads = warps_total * 32;
    uint32_t gemm_blocks  = (gemm_threads + THREADS_PER_BLK - 1) / THREADS_PER_BLK;
    /* shared: B tiles + C tiles for each warp */
    size_t smem_bytes = WARPS_PER_BLK * TC_K * TC_N * sizeof(int8_t)
                      + WARPS_PER_BLK * TC_M * TC_N * sizeof(int32_t);

    uint32_t scan_threads = 256;
    uint32_t scan_blocks  = (num_clauses + scan_threads - 1) / scan_threads;

    uint32_t abs_blocks = (K_pad + 255) / 256;

    /* result is already initialized to -1 (UNDEF) at function entry */

    /* ── 6.  BCP iteration loop ────────────────────────────────── */
    for (int iter = 0; iter < MAX_BCP_ITERS; iter++) {

        /* 6a. Build |b| from b */
        build_abs_vector<<<abs_blocks, 256>>>(d_b, d_b_abs, K_pad);

        /* 6b. Score GEMM:  score[c] = Σ A[c][v] · b[v] */
        tc_gemm_score<<<gemm_blocks, THREADS_PER_BLK, smem_bytes>>>(
            d_A, d_b, d_scores, M_pad, K_pad);

        /* 6c. Mask GEMM:   mask[c] = Σ |A[c][v]| · |b[v]| */
        tc_gemm_mask<<<gemm_blocks, THREADS_PER_BLK, smem_bytes>>>(
            d_Aabs, d_b_abs, d_masks, M_pad, K_pad);

        /* 6d. Post-scan: classify clauses, detect conflicts/units */
        cudaMemset(d_qcount, 0, sizeof(uint32_t));
        tc_post_scan<<<scan_blocks, scan_threads>>>(
            d_scores, d_masks, d_lits,
            d_A, d_b,
            d_queue, d_qcount, d_conflict,
            num_clauses, K_pad);

        cudaDeviceSynchronize();

        /* 6e. Check conflict */
        int32_t h_conflict;
        cudaMemcpy(&h_conflict, d_conflict, sizeof(int32_t), cudaMemcpyDeviceToHost);
        if (h_conflict) { result = 0; break; }   /* UNSAT */

        /* 6f. Check unit queue */
        uint32_t h_qcount;
        cudaMemcpy(&h_qcount, d_qcount, sizeof(uint32_t), cudaMemcpyDeviceToHost);

        if (h_qcount == 0) {
            /* No unit propagation possible — check if all satisfied */
            int32_t* h_scores = (int32_t*)malloc(score_bytes);
            int32_t* h_masks  = (int32_t*)malloc(score_bytes);
            cudaMemcpy(h_scores, d_scores, score_bytes, cudaMemcpyDeviceToHost);
            cudaMemcpy(h_masks,  d_masks,  score_bytes, cudaMemcpyDeviceToHost);

            bool all_sat = true;
            for (uint32_t c = 0; c < num_clauses; c++) {
                if (h_scores[c] + h_masks[c] <= 0) {
                    all_sat = false;
                    break;
                }
            }
            free(h_scores);
            free(h_masks);

            result = all_sat ? 1 : -1;
            break;
        }

        if (h_qcount > UNIT_QUEUE_CAP) h_qcount = UNIT_QUEUE_CAP;

        /* 6g. Propagate unit clauses */
        uint32_t prop_blocks = (h_qcount + 255) / 256;
        tc_propagate<<<prop_blocks, 256>>>(
            d_queue, h_qcount, d_b, d_b_abs, d_conflict);

        cudaDeviceSynchronize();

        /* 6h. Re-check conflict after propagation */
        cudaMemcpy(&h_conflict, d_conflict, sizeof(int32_t), cudaMemcpyDeviceToHost);
        if (h_conflict) { result = 0; break; }
    }

cleanup:
    cudaFree(d_A);
    cudaFree(d_Aabs);
    cudaFree(d_b);
    cudaFree(d_b_abs);
    cudaFree(d_scores);
    cudaFree(d_masks);
    cudaFree(d_lits);
    cudaFree(d_queue);
    cudaFree(d_qcount);
    cudaFree(d_conflict);
    free(h_A);
    free(h_Aabs);
    free(h_lits);

    return result;
}

int gpu_bcp_solve_sparse(
    uint32_t num_vars,
    uint32_t num_clauses,
    uint32_t M_pad,
    uint32_t K_pad,
    uint32_t num_active_tiles,
    const int8_t* active_tiles_data,
    const int8_t* active_tiles_abs_data,
    const uint16_t* h_lits,
    const TileCoord* active_tiles_coords,
    const uint32_t* m_tile_start
)
{
    if (num_clauses == 0) return 1;
    if (num_vars == 0)    return 0;

    int result = -1;  /* UNDEF */

    size_t active_bytes = (size_t)num_active_tiles * 256;
    size_t b_bytes      = K_pad;
    size_t score_bytes  = M_pad * sizeof(int32_t);
    size_t lits_bytes   = M_pad * sizeof(uint16_t);
    size_t coords_bytes = num_active_tiles * sizeof(TileCoord);
    size_t m_tile_start_bytes = ((M_pad / 16) + 1) * sizeof(uint32_t);
    size_t queue_bytes  = UNIT_QUEUE_CAP * sizeof(UnitEntry);

    /* ── Device allocation ─────────────────────────────────── */
    int8_t*      d_A            = NULL;
    int8_t*      d_Aabs         = NULL;
    int8_t*      d_b            = NULL;
    int8_t*      d_b_abs        = NULL;
    int32_t*     d_scores       = NULL;
    int32_t*     d_masks        = NULL;
    uint16_t*    d_lits         = NULL;
    TileCoord*   d_active_tiles = NULL;
    uint32_t*    d_m_tile_start = NULL;
    UnitEntry*   d_queue        = NULL;
    uint32_t*    d_qcount       = NULL;
    int32_t*     d_conflict     = NULL;

    cudaError_t e;
    #define CMALLOC(ptr, sz) do { \
        e = cudaMalloc(&(ptr), (sz)); \
        if (e != cudaSuccess) { \
            fprintf(stderr, "[tc-bcp-sparse] cudaMalloc failed: %s\n", cudaGetErrorString(e)); \
            goto cleanup; \
        } \
    } while(0)

    CMALLOC(d_A,            active_bytes);
    CMALLOC(d_Aabs,         active_bytes);
    CMALLOC(d_b,            b_bytes);
    CMALLOC(d_b_abs,        b_bytes);
    CMALLOC(d_scores,       score_bytes);
    CMALLOC(d_masks,        score_bytes);
    CMALLOC(d_lits,         lits_bytes);
    CMALLOC(d_active_tiles, coords_bytes);
    CMALLOC(d_m_tile_start, m_tile_start_bytes);
    CMALLOC(d_queue,        queue_bytes);
    CMALLOC(d_qcount,       sizeof(uint32_t));
    CMALLOC(d_conflict,     sizeof(int32_t));
    #undef CMALLOC

    /* ── Upload static data ────────────────────────────────── */
    cudaMemcpy(d_A,            active_tiles_data,     active_bytes,        cudaMemcpyHostToDevice);
    cudaMemcpy(d_Aabs,         active_tiles_abs_data, active_bytes,        cudaMemcpyHostToDevice);
    cudaMemcpy(d_lits,         h_lits,                lits_bytes,          cudaMemcpyHostToDevice);
    cudaMemcpy(d_active_tiles, active_tiles_coords,   coords_bytes,        cudaMemcpyHostToDevice);
    cudaMemcpy(d_m_tile_start, m_tile_start,          m_tile_start_bytes,  cudaMemcpyHostToDevice);
    cudaMemset(d_b,            0,                     b_bytes);
    cudaMemset(d_b_abs,        0,                     b_bytes);
    cudaMemset(d_conflict,     0,                     sizeof(int32_t));

    /* ── Kernel launch geometry ────────────────────────────── */
    uint32_t num_m_tiles = M_pad / TC_M;
    uint32_t warps_total = num_m_tiles;
    uint32_t gemm_threads = warps_total * 32;
    uint32_t gemm_blocks  = (gemm_threads + THREADS_PER_BLK - 1) / THREADS_PER_BLK;
    /* shared: B tiles + C tiles for each warp */
    size_t smem_bytes = WARPS_PER_BLK * TC_K * TC_N * sizeof(int8_t)
                      + WARPS_PER_BLK * TC_M * TC_N * sizeof(int32_t);

    uint32_t scan_threads = 256;
    uint32_t scan_blocks  = (num_clauses + scan_threads - 1) / scan_threads;

    uint32_t abs_blocks = (K_pad + 255) / 256;

    /* ── BCP iteration loop ────────────────────────────────── */
    for (int iter = 0; iter < MAX_BCP_ITERS; iter++) {

        /* Build |b| from b */
        build_abs_vector<<<abs_blocks, 256>>>(d_b, d_b_abs, K_pad);

        /* Score GEMM */
        tc_gemm_score_sparse<<<gemm_blocks, THREADS_PER_BLK, smem_bytes>>>(
            d_A, d_b, d_scores, d_active_tiles, d_m_tile_start, M_pad);

        /* Mask GEMM */
        tc_gemm_mask_sparse<<<gemm_blocks, THREADS_PER_BLK, smem_bytes>>>(
            d_Aabs, d_b_abs, d_masks, d_active_tiles, d_m_tile_start, M_pad);

        /* Post-scan: classify clauses, detect conflicts/units */
        cudaMemset(d_qcount, 0, sizeof(uint32_t));
        tc_post_scan_sparse<<<scan_blocks, scan_threads>>>(
            d_scores, d_masks, d_lits,
            d_A, d_b, d_active_tiles, d_m_tile_start,
            d_queue, d_qcount, d_conflict,
            num_clauses, M_pad);

        cudaDeviceSynchronize();

        /* Check conflict */
        int32_t h_conflict;
        cudaMemcpy(&h_conflict, d_conflict, sizeof(int32_t), cudaMemcpyDeviceToHost);
        if (h_conflict) { result = 0; break; }   /* UNSAT */

        /* Check unit queue */
        uint32_t h_qcount;
        cudaMemcpy(&h_qcount, d_qcount, sizeof(uint32_t), cudaMemcpyDeviceToHost);

        if (h_qcount == 0) {
            /* No unit propagation possible — check if all satisfied */
            int32_t* h_scores = (int32_t*)malloc(score_bytes);
            int32_t* h_masks  = (int32_t*)malloc(score_bytes);
            cudaMemcpy(h_scores, d_scores, score_bytes, cudaMemcpyDeviceToHost);
            cudaMemcpy(h_masks,  d_masks,  score_bytes, cudaMemcpyDeviceToHost);

            bool all_sat = true;
            for (uint32_t c = 0; c < num_clauses; c++) {
                if (h_scores[c] + h_masks[c] <= 0) {
                    all_sat = false;
                    break;
                }
            }
            free(h_scores);
            free(h_masks);

            result = all_sat ? 1 : -1;
            break;
        }

        if (h_qcount > UNIT_QUEUE_CAP) h_qcount = UNIT_QUEUE_CAP;

        /* Propagate unit clauses */
        uint32_t prop_blocks = (h_qcount + 255) / 256;
        tc_propagate<<<prop_blocks, 256>>>(
            d_queue, h_qcount, d_b, d_b_abs, d_conflict);

        cudaDeviceSynchronize();

        /* Re-check conflict after propagation */
        cudaMemcpy(&h_conflict, d_conflict, sizeof(int32_t), cudaMemcpyDeviceToHost);
        if (h_conflict) { result = 0; break; }
    }

cleanup:
    if (d_A)            cudaFree(d_A);
    if (d_Aabs)         cudaFree(d_Aabs);
    if (d_b)            cudaFree(d_b);
    if (d_b_abs)        cudaFree(d_b_abs);
    if (d_scores)       cudaFree(d_scores);
    if (d_masks)        cudaFree(d_masks);
    if (d_lits)         cudaFree(d_lits);
    if (d_active_tiles) cudaFree(d_active_tiles);
    if (d_m_tile_start) cudaFree(d_m_tile_start);
    if (d_queue)        cudaFree(d_queue);
    if (d_qcount)       cudaFree(d_qcount);
    if (d_conflict)     cudaFree(d_conflict);

    return result;
}

} /* extern "C" */

/* ════════════════════════════════════════════════════════════════════
 *  PERSISTENT GPU STATE for CDCL-integrated BCP
 *
 *  Instead of allocating/freeing GPU memory on each call,
 *  we keep the clause matrix resident and only update the
 *  assignment vector on each propagation round.
 * ════════════════════════════════════════════════════════════════════ */

struct GpuBcpPersistentState {
    /* Device pointers — clause matrix (static, uploaded once) */
    int8_t*      d_A;
    int8_t*      d_Aabs;
    uint16_t*    d_lits;
    TileCoord*   d_active_tiles;
    uint32_t*    d_m_tile_start;

    /* Device pointers — per-call working buffers */
    int8_t*      d_b;
    int8_t*      d_b_abs;
    int32_t*     d_scores;
    int32_t*     d_masks;
    UnitEntry*   d_queue;
    uint32_t*    d_qcount;
    int32_t*     d_conflict;

    /* Host-pinned pointers for asynchronous I/O */
    int8_t*      h_b;
    int32_t*     h_conflict;
    uint32_t*    h_qcount;
    UnitEntry*   h_queue;

    /* CUDA Stream and Event */
    cudaStream_t stream;
    cudaEvent_t  event;
    bool         async_in_flight;

    /* Dimensions */
    uint32_t     num_vars;
    uint32_t     num_clauses;
    uint32_t     M_pad;
    uint32_t     K_pad;
    uint32_t     num_active_tiles;

    /* Launch geometry (precomputed) */
    uint32_t     gemm_blocks;
    uint32_t     scan_blocks;
    uint32_t     abs_blocks;
    size_t       smem_bytes;

    bool         initialized;
};

extern "C" {

/* Forward declaration for error-path cleanup in init */
void gpu_bcp_cleanup_persistent(GpuBcpPersistentState* state);

/* ── Allocate persistent GPU state and upload clause matrix ────── */
GpuBcpPersistentState* gpu_bcp_init_persistent(
    uint32_t num_vars,
    uint32_t num_clauses,
    uint32_t M_pad,
    uint32_t K_pad,
    uint32_t num_active_tiles,
    const int8_t* active_tiles_data,
    const int8_t* active_tiles_abs_data,
    const uint16_t* h_lits,
    const TileCoord* active_tiles_coords,
    const uint32_t* m_tile_start)
{
    GpuBcpPersistentState* state = (GpuBcpPersistentState*)calloc(1, sizeof(GpuBcpPersistentState));
    if (!state) return NULL;

    state->num_vars         = num_vars;
    state->num_clauses      = num_clauses;
    state->M_pad            = M_pad;
    state->K_pad            = K_pad;
    state->num_active_tiles = num_active_tiles;

    size_t active_bytes     = (size_t)num_active_tiles * 256;
    size_t b_bytes          = K_pad;
    size_t score_bytes      = M_pad * sizeof(int32_t);
    size_t lits_bytes       = M_pad * sizeof(uint16_t);
    size_t coords_bytes     = num_active_tiles * sizeof(TileCoord);
    size_t m_tile_start_bytes = ((M_pad / 16) + 1) * sizeof(uint32_t);
    size_t queue_bytes      = UNIT_QUEUE_CAP * sizeof(UnitEntry);

    cudaError_t e;
    #define CMALLOC_P(ptr, sz) do { \
        e = cudaMalloc(&(ptr), (sz)); \
        if (e != cudaSuccess) { \
            fprintf(stderr, "[gpu-persistent] cudaMalloc failed: %s\n", cudaGetErrorString(e)); \
            gpu_bcp_cleanup_persistent(state); \
            return NULL; \
        } \
    } while(0)

    CMALLOC_P(state->d_A,            active_bytes);
    CMALLOC_P(state->d_Aabs,         active_bytes);
    CMALLOC_P(state->d_b,            b_bytes);
    CMALLOC_P(state->d_b_abs,        b_bytes);
    CMALLOC_P(state->d_scores,       score_bytes);
    CMALLOC_P(state->d_masks,        score_bytes);
    CMALLOC_P(state->d_lits,         lits_bytes);
    CMALLOC_P(state->d_active_tiles, coords_bytes);
    CMALLOC_P(state->d_m_tile_start, m_tile_start_bytes);
    CMALLOC_P(state->d_queue,        queue_bytes);
    CMALLOC_P(state->d_qcount,       sizeof(uint32_t));
    CMALLOC_P(state->d_conflict,     sizeof(int32_t));
    #undef CMALLOC_P

    /* Allocate host-pinned pointers */
    e = cudaMallocHost(&(state->h_b), K_pad);
    if (e != cudaSuccess) {
        fprintf(stderr, "[gpu-persistent] cudaMallocHost(h_b) failed: %s\n", cudaGetErrorString(e));
        gpu_bcp_cleanup_persistent(state);
        return NULL;
    }
    e = cudaMallocHost(&(state->h_conflict), sizeof(int32_t));
    if (e != cudaSuccess) {
        fprintf(stderr, "[gpu-persistent] cudaMallocHost(h_conflict) failed: %s\n", cudaGetErrorString(e));
        gpu_bcp_cleanup_persistent(state);
        return NULL;
    }
    e = cudaMallocHost(&(state->h_qcount), sizeof(uint32_t));
    if (e != cudaSuccess) {
        fprintf(stderr, "[gpu-persistent] cudaMallocHost(h_qcount) failed: %s\n", cudaGetErrorString(e));
        gpu_bcp_cleanup_persistent(state);
        return NULL;
    }
    e = cudaMallocHost(&(state->h_queue), UNIT_QUEUE_CAP * sizeof(UnitEntry));
    if (e != cudaSuccess) {
        fprintf(stderr, "[gpu-persistent] cudaMallocHost(h_queue) failed: %s\n", cudaGetErrorString(e));
        gpu_bcp_cleanup_persistent(state);
        return NULL;
    }

    /* Create CUDA stream and event */
    e = cudaStreamCreate(&(state->stream));
    if (e != cudaSuccess) {
        fprintf(stderr, "[gpu-persistent] cudaStreamCreate failed: %s\n", cudaGetErrorString(e));
        gpu_bcp_cleanup_persistent(state);
        return NULL;
    }
    e = cudaEventCreateWithFlags(&(state->event), cudaEventDisableTiming);
    if (e != cudaSuccess) {
        fprintf(stderr, "[gpu-persistent] cudaEventCreateWithFlags failed: %s\n", cudaGetErrorString(e));
        gpu_bcp_cleanup_persistent(state);
        return NULL;
    }

    state->async_in_flight = false;

    /* Upload static clause data (done once) */
    cudaMemcpy(state->d_A,            active_tiles_data,     active_bytes,        cudaMemcpyHostToDevice);
    cudaMemcpy(state->d_Aabs,         active_tiles_abs_data, active_bytes,        cudaMemcpyHostToDevice);
    cudaMemcpy(state->d_lits,         h_lits,                lits_bytes,          cudaMemcpyHostToDevice);
    cudaMemcpy(state->d_active_tiles, active_tiles_coords,   coords_bytes,        cudaMemcpyHostToDevice);
    cudaMemcpy(state->d_m_tile_start, m_tile_start,          m_tile_start_bytes,  cudaMemcpyHostToDevice);

    /* Precompute launch geometry */
    uint32_t num_m_tiles  = M_pad / TC_M;
    uint32_t warps_total  = num_m_tiles;
    uint32_t gemm_threads = warps_total * 32;
    state->gemm_blocks    = (gemm_threads + THREADS_PER_BLK - 1) / THREADS_PER_BLK;
    state->scan_blocks    = (num_clauses + 255) / 256;
    state->abs_blocks     = (K_pad + 255) / 256;
    state->smem_bytes     = WARPS_PER_BLK * TC_K * TC_N * sizeof(int8_t)
                          + WARPS_PER_BLK * TC_M * TC_N * sizeof(int32_t);

    state->initialized = true;
    return state;
}

/* ── Launch one round of GPU BCP asynchronously ────────────────── *
 *  h_assignment: [K_pad] int8_t array, +1=true, -1=false, 0=undef  *
 *  Returns: 1 if launch succeeded, 0 otherwise                       *
 * ─────────────────────────────────────────────────────────────────── */
int gpu_bcp_launch_async(GpuBcpPersistentState* state, const int8_t* h_assignment)
{
    if (!state || !state->initialized) return 0;
    if (state->async_in_flight) return 0;

    /* Copy host assignment to host-pinned buffer if non-NULL */
    if (h_assignment) {
        memcpy(state->h_b, h_assignment, state->K_pad);
    }

    /* Upload current assignment vector asynchronously */
    cudaMemcpyAsync(state->d_b, state->h_b, state->K_pad, cudaMemcpyHostToDevice, state->stream);

    /* Build |b| */
    build_abs_vector<<<state->abs_blocks, 256, 0, state->stream>>>(state->d_b, state->d_b_abs, state->K_pad);

    /* Score GEMM: score[c] = Σ A[c][v] · b[v] */
    tc_gemm_score_sparse<<<state->gemm_blocks, THREADS_PER_BLK, state->smem_bytes, state->stream>>>(
        state->d_A, state->d_b, state->d_scores,
        state->d_active_tiles, state->d_m_tile_start, state->M_pad);

    /* Mask GEMM: mask[c] = Σ |A[c][v]| · |b[v]| */
    tc_gemm_mask_sparse<<<state->gemm_blocks, THREADS_PER_BLK, state->smem_bytes, state->stream>>>(
        state->d_Aabs, state->d_b_abs, state->d_masks,
        state->d_active_tiles, state->d_m_tile_start, state->M_pad);

    /* Reset counters */
    cudaMemsetAsync(state->d_qcount,   0, sizeof(uint32_t), state->stream);
    cudaMemsetAsync(state->d_conflict, 0, sizeof(int32_t),  state->stream);

    /* Post-scan: classify clauses, find units, detect conflicts */
    tc_post_scan_sparse<<<state->scan_blocks, 256, 0, state->stream>>>(
        state->d_scores, state->d_masks, state->d_lits,
        state->d_A, state->d_b,
        state->d_active_tiles, state->d_m_tile_start,
        state->d_queue, state->d_qcount, state->d_conflict,
        state->num_clauses, state->M_pad);

    /* Copy results back to host-pinned memory asynchronously */
    cudaMemcpyAsync(state->h_conflict, state->d_conflict, sizeof(int32_t), cudaMemcpyDeviceToHost, state->stream);
    cudaMemcpyAsync(state->h_qcount,   state->d_qcount,   sizeof(uint32_t), cudaMemcpyDeviceToHost, state->stream);
    cudaMemcpyAsync(state->h_queue,    state->d_queue,    UNIT_QUEUE_CAP * sizeof(UnitEntry), cudaMemcpyDeviceToHost, state->stream);

    /* Record the event to track asynchronous completion */
    cudaEventRecord(state->event, state->stream);

    state->async_in_flight = true;
    return 1;
}

/* ── Poll status of asynchronous GPU BCP execution ──────────────── */
bool gpu_bcp_poll_status(GpuBcpPersistentState* state)
{
    if (!state || !state->initialized || !state->async_in_flight) return false;

    cudaError_t err = cudaEventQuery(state->event);
    if (err == cudaSuccess) {
        state->async_in_flight = false;
        return true;
    }
    return false;
}

/* ── Check if an asynchronous execution is in flight ────────────── */
bool gpu_bcp_is_async_in_flight(GpuBcpPersistentState* state)
{
    return state && state->initialized && state->async_in_flight;
}

/* ── Get host assignment buffer pointer ─────────────────────────── */
int8_t* gpu_bcp_get_assignment_buffer(GpuBcpPersistentState* state)
{
    return state ? state->h_b : nullptr;
}

/* ── Retrieve results of completed GPU BCP execution ───────────── *
 *  out_unit_vars: [UNIT_QUEUE_CAP] pre-allocated host buffer        *
 *  out_unit_pols: [UNIT_QUEUE_CAP] pre-allocated host buffer        *
 *  out_count:     number of discovered unit propagations            *
 *  Returns: 0 = no conflict, 1 = conflict detected                  *
 * ─────────────────────────────────────────────────────────────────── */
int gpu_bcp_retrieve_results(
    GpuBcpPersistentState* state,
    int32_t* out_unit_vars,
    int8_t*  out_unit_pols,
    uint32_t* out_count)
{
    if (!state || !state->initialized) {
        *out_count = 0;
        return 0;
    }

    *out_count = 0;

    int32_t h_conflict = *(state->h_conflict);
    if (h_conflict) return 1;

    uint32_t h_qcount = *(state->h_qcount);
    if (h_qcount > 0) {
        if (h_qcount > UNIT_QUEUE_CAP) h_qcount = UNIT_QUEUE_CAP;

        /* Unpack from the host-pinned queue buffer directly */
        uint32_t valid = 0;
        for (uint32_t i = 0; i < h_qcount && valid < UNIT_QUEUE_CAP; ++i) {
            if (state->h_queue[i].var_idx >= 0 && state->h_queue[i].polarity != 0) {
                out_unit_vars[valid] = state->h_queue[i].var_idx;
                out_unit_pols[valid] = state->h_queue[i].polarity;
                valid++;
            }
        }
        *out_count = valid;
    }

    return 0;
}

/* ── Free persistent GPU state ─────────────────────────────────── */
void gpu_bcp_cleanup_persistent(GpuBcpPersistentState* state)
{
    if (!state) return;
    if (state->d_A)            cudaFree(state->d_A);
    if (state->d_Aabs)         cudaFree(state->d_Aabs);
    if (state->d_b)            cudaFree(state->d_b);
    if (state->d_b_abs)        cudaFree(state->d_b_abs);
    if (state->d_scores)       cudaFree(state->d_scores);
    if (state->d_masks)        cudaFree(state->d_masks);
    if (state->d_lits)         cudaFree(state->d_lits);
    if (state->d_active_tiles) cudaFree(state->d_active_tiles);
    if (state->d_m_tile_start) cudaFree(state->d_m_tile_start);
    if (state->d_queue)        cudaFree(state->d_queue);
    if (state->d_qcount)       cudaFree(state->d_qcount);
    if (state->d_conflict)     cudaFree(state->d_conflict);

    /* Free host-pinned pointers */
    if (state->h_b)            cudaFreeHost(state->h_b);
    if (state->h_conflict)     cudaFreeHost(state->h_conflict);
    if (state->h_qcount)       cudaFreeHost(state->h_qcount);
    if (state->h_queue)        cudaFreeHost(state->h_queue);

    /* Destroy CUDA stream and event */
    if (state->stream)         cudaStreamDestroy(state->stream);
    if (state->event)          cudaEventDestroy(state->event);

    free(state);
}

} /* extern "C" */
