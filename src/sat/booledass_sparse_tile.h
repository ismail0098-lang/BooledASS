/* ════════════════════════════════════════════════════════════════════
 *  BooledASS Sparse Tile Compression — Host-side C++ header
 *
 *  Variable Density Chunking for Tensor Core BCP:
 *  1. Co-occurrence graph construction from Z3 clause vectors
 *  2. BFS/spectral-bandwidth variable reordering to maximize
 *     non-zero density inside 16×16 WMMA tiles
 *  3. Compressed Blocked Tile (CBT) serialization with active
 *     tile index array for GPU dispatch
 * ════════════════════════════════════════════════════════════════════ */

#ifndef BOOLEDASS_SPARSE_TILE_H
#define BOOLEDASS_SPARSE_TILE_H

#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <vector>
#include <algorithm>
#include <numeric>
#include <queue>
#include <utility>
#include <chrono>


namespace sat {

/* ── Tile coordinate for sparse dispatch ─────────────────────────── */
struct TileCoord {
    uint32_t m_tile;   /* clause-row tile index (0..M_pad/16-1) */
    uint32_t k_tile;   /* variable-col tile index (0..K_pad/16-1) */
};

/* ── Compressed Blocked Tile layout output ───────────────────────── */
struct CompressedTileLayout {
    /* Contiguous active tile data (num_active_tiles * 256 bytes) */
    int8_t*   A;
    int8_t*   A_abs;
    uint16_t* num_lits;    /* per-clause literal counts           */

    /* Active tile index: only tiles with ≥1 non-zero element     */
    TileCoord* active_tiles;
    uint32_t   num_active_tiles;

    /* Per M-tile: range into active_tiles for its K-stripe tiles */
    uint32_t*  m_tile_start;   /* [M_pad/16 + 1] prefix-sum index */

    /* Variable permutation: original_var = var_perm[permuted_var] */
    uint32_t*  var_perm;
    /* Inverse permutation: permuted_var = var_inv[original_var]  */
    uint32_t*  var_inv;

    uint32_t M_pad;
    uint32_t K_pad;
    uint32_t M_real;
    uint32_t K_real;
};

/* ── Cleanup ─────────────────────────────────────────────────────── */
static void free_compressed_tile_layout(CompressedTileLayout& ctl) {
    if (ctl.A) { free(ctl.A); ctl.A = nullptr; }
    if (ctl.A_abs) { free(ctl.A_abs); ctl.A_abs = nullptr; }
    if (ctl.num_lits) { free(ctl.num_lits); ctl.num_lits = nullptr; }
    if (ctl.active_tiles) { free(ctl.active_tiles); ctl.active_tiles = nullptr; }
    if (ctl.m_tile_start) { free(ctl.m_tile_start); ctl.m_tile_start = nullptr; }
    if (ctl.var_perm) { free(ctl.var_perm); ctl.var_perm = nullptr; }
    if (ctl.var_inv) { free(ctl.var_inv); ctl.var_inv = nullptr; }
}

/* ─────────────────────────────────────────────────────────────────── *
 *  build_compressed_tile_layout_direct                                *
 *                                                                     *
 *  Takes Z3 clause vectors and constructs the sparse tile layout      *
 *  directly, avoiding dense matrix allocation and serialization.      *
 * ─────────────────────────────────────────────────────────────────── */
static CompressedTileLayout build_compressed_tile_layout_direct(
    unsigned num_vars,
    svector<std::pair<literal, literal>> const& bins,
    clause_vector const& m_clauses,
    clause_vector const& m_learned)
{
    auto start_total = std::chrono::high_resolution_clock::now();
    const uint32_t TILE = 16;
    CompressedTileLayout ctl;
    memset(&ctl, 0, sizeof(ctl));

    ctl.M_real = bins.size();
    for (clause* c : m_clauses) {
        if (!c->was_removed()) ctl.M_real++;
    }
    for (clause* c : m_learned) {
        if (!c->was_removed()) ctl.M_real++;
    }
    
    ctl.K_real = num_vars;
    ctl.M_pad  = ((ctl.M_real + TILE - 1) / TILE) * TILE;
    ctl.K_pad  = ((num_vars    + TILE - 1) / TILE) * TILE;

    uint32_t num_m_tiles = ctl.M_pad / TILE;
    uint32_t num_k_tiles = ctl.K_pad / TILE;

    IF_VERBOSE(0, verbose_stream() << "[MatrixBuild] M_real: " << ctl.M_real << ", K_real: " << ctl.K_real << "\n";);

    // 1. Build adjacency lists for RCM Graph
    auto start_adj = std::chrono::high_resolution_clock::now();
    std::vector<std::vector<uint32_t>> adj(num_vars);
    std::vector<uint32_t> degree(num_vars, 0);

    auto add_clause_edges = [&](const std::vector<uint32_t>& vars) {
        if (vars.size() <= 128) {
            for (size_t i = 0; i < vars.size(); i++) {
                for (size_t j = i + 1; j < vars.size(); j++) {
                    adj[vars[i]].push_back(vars[j]);
                    adj[vars[j]].push_back(vars[i]);
                }
            }
        }
    };

    std::vector<uint32_t> vars;
    vars.reserve(32);

    for (auto const& bin : bins) {
        vars.clear();
        if (bin.first.var() < num_vars) vars.push_back(bin.first.var());
        if (bin.second.var() < num_vars) vars.push_back(bin.second.var());
        add_clause_edges(vars);
    }

    for (clause* c : m_clauses) {
        if (c->was_removed()) continue;
        vars.clear();
        for (unsigned i = 0; i < c->size(); ++i) {
            if ((*c)[i].var() < num_vars) {
                vars.push_back((*c)[i].var());
            }
        }
        add_clause_edges(vars);
    }

    for (clause* c : m_learned) {
        if (c->was_removed()) continue;
        vars.clear();
        for (unsigned i = 0; i < c->size(); ++i) {
            if ((*c)[i].var() < num_vars) {
                vars.push_back((*c)[i].var());
            }
        }
        add_clause_edges(vars);
    }

    // Deduplicate and compute degrees
    for (uint32_t v = 0; v < num_vars; v++) {
        std::sort(adj[v].begin(), adj[v].end());
        adj[v].erase(std::unique(adj[v].begin(), adj[v].end()), adj[v].end());
        degree[v] = (uint32_t)adj[v].size();
    }
    auto end_adj = std::chrono::high_resolution_clock::now();
    double adj_sec = std::chrono::duration<double>(end_adj - start_adj).count();
    IF_VERBOSE(0, verbose_stream() << "[MatrixBuild] Step 1 (Adjacency Graph): " << adj_sec << "s\n";);

    // 2. RCM Variable Ordering
    auto start_rcm = std::chrono::high_resolution_clock::now();
    std::vector<uint32_t> perm;
    perm.reserve(num_vars);
    std::vector<bool> visited(num_vars, false);

    uint32_t last_search_idx = 0;
    while (perm.size() < num_vars) {
        while (last_search_idx < num_vars && visited[last_search_idx]) {
            last_search_idx++;
        }
        if (last_search_idx >= num_vars) break;
        uint32_t seed = last_search_idx;

        std::queue<uint32_t> bfs;
        bfs.push(seed);
        visited[seed] = true;

        while (!bfs.empty()) {
            uint32_t u = bfs.front(); bfs.pop();
            perm.push_back(u);

            std::vector<uint32_t>& nbrs = adj[u];
            if (nbrs.size() <= 256) {
                std::sort(nbrs.begin(), nbrs.end(),
                    [&](uint32_t a, uint32_t b) { return degree[a] < degree[b]; });
            }

            for (uint32_t w : nbrs) {
                if (!visited[w]) {
                    visited[w] = true;
                    bfs.push(w);
                }
            }
        }
        // Advance last_search_idx past visited prefix
        while (last_search_idx < num_vars && visited[last_search_idx]) {
            last_search_idx++;
        }
    }
    std::reverse(perm.begin(), perm.end());
    auto end_rcm = std::chrono::high_resolution_clock::now();
    double rcm_sec = std::chrono::duration<double>(end_rcm - start_rcm).count();
    IF_VERBOSE(0, verbose_stream() << "[MatrixBuild] Step 2 (RCM Ordering): " << rcm_sec << "s\n";);

    // Build permutations
    ctl.var_perm = (uint32_t*)calloc(ctl.K_pad, sizeof(uint32_t));
    ctl.var_inv  = (uint32_t*)calloc(ctl.K_pad, sizeof(uint32_t));
    for (uint32_t i = 0; i < num_vars; i++) {
        ctl.var_perm[i] = perm[i];
        ctl.var_inv[perm[i]] = i;
    }
    for (uint32_t i = num_vars; i < ctl.K_pad; i++) {
        ctl.var_perm[i] = i;
        ctl.var_inv[i]  = i;
    }

    // 3. Mark active 16x16 tiles (optimized to avoid 2D active_tiles_map and tile_index)
    auto start_tiles = std::chrono::high_resolution_clock::now();
    ctl.num_lits = (uint16_t*)calloc(ctl.M_pad, sizeof(uint16_t));

    std::vector<TileCoord> temp_coords;
    temp_coords.reserve(bins.size() * 2 + (m_clauses.size() + m_learned.size()) * 4);

    auto process_clause_lits = [&](uint32_t c_idx, const std::vector<std::pair<uint32_t, int8_t>>& cl_lits) {
        uint32_t mt = c_idx / TILE;
        ctl.num_lits[c_idx] = (uint16_t)cl_lits.size();
        for (auto const& lit : cl_lits) {
            uint32_t v_perm = ctl.var_inv[lit.first];
            uint32_t kt = v_perm / TILE;
            TileCoord tc;
            tc.m_tile = mt;
            tc.k_tile = kt;
            temp_coords.push_back(tc);
        }
    };

    uint32_t clause_idx = 0;
    std::vector<std::pair<uint32_t, int8_t>> cl_lits;

    for (auto const& bin : bins) {
        cl_lits.clear();
        if (bin.first.var() < num_vars) cl_lits.push_back({bin.first.var(), bin.first.sign() ? -1 : 1});
        if (bin.second.var() < num_vars) cl_lits.push_back({bin.second.var(), bin.second.sign() ? -1 : 1});
        process_clause_lits(clause_idx++, cl_lits);
    }

    for (clause* c : m_clauses) {
        if (c->was_removed()) continue;
        cl_lits.clear();
        for (unsigned i = 0; i < c->size(); ++i) {
            literal l = (*c)[i];
            if (l.var() < num_vars) cl_lits.push_back({l.var(), l.sign() ? -1 : 1});
        }
        process_clause_lits(clause_idx++, cl_lits);
    }

    for (clause* c : m_learned) {
        if (c->was_removed()) continue;
        cl_lits.clear();
        for (unsigned i = 0; i < c->size(); ++i) {
            literal l = (*c)[i];
            if (l.var() < num_vars) cl_lits.push_back({l.var(), l.sign() ? -1 : 1});
        }
        process_clause_lits(clause_idx++, cl_lits);
    }

    // Now, sort and deduplicate temp_coords to find unique active tiles
    std::sort(temp_coords.begin(), temp_coords.end(), [](const TileCoord& a, const TileCoord& b) {
        if (a.m_tile != b.m_tile) return a.m_tile < b.m_tile;
        return a.k_tile < b.k_tile;
    });

    std::vector<TileCoord> unique_tiles;
    unique_tiles.reserve(temp_coords.size() / 4 + 1);
    for (const auto& tc : temp_coords) {
        if (unique_tiles.empty() || unique_tiles.back().m_tile != tc.m_tile || unique_tiles.back().k_tile != tc.k_tile) {
            unique_tiles.push_back(tc);
        }
    }

    ctl.num_active_tiles = (uint32_t)unique_tiles.size();
    ctl.active_tiles = (TileCoord*)malloc(unique_tiles.size() * sizeof(TileCoord));
    memcpy(ctl.active_tiles, unique_tiles.data(), unique_tiles.size() * sizeof(TileCoord));

    // Build m_tile_start prefix sum
    ctl.m_tile_start = (uint32_t*)calloc(num_m_tiles + 1, sizeof(uint32_t));
    uint32_t curr_tile_idx = 0;
    for (uint32_t mt = 0; mt < num_m_tiles; mt++) {
        ctl.m_tile_start[mt] = curr_tile_idx;
        while (curr_tile_idx < ctl.num_active_tiles && unique_tiles[curr_tile_idx].m_tile == mt) {
            curr_tile_idx++;
        }
    }
    ctl.m_tile_start[num_m_tiles] = ctl.num_active_tiles;

    auto end_tiles = std::chrono::high_resolution_clock::now();
    double tiles_sec = std::chrono::duration<double>(end_tiles - start_tiles).count();
    IF_VERBOSE(0, verbose_stream() << "[MatrixBuild] Step 3 (Active Tile Identification): " << tiles_sec << "s, num_active_tiles: " << ctl.num_active_tiles << "\n";);

    // 4. Allocate and fill sparse tile arrays
    auto start_fill = std::chrono::high_resolution_clock::now();
    size_t active_bytes = (size_t)ctl.num_active_tiles * 256;
    ctl.A     = (int8_t*)calloc(active_bytes, 1);
    ctl.A_abs = (int8_t*)calloc(active_bytes, 1);

    // Fill clause data using binary search into active_tiles instead of 2D lookup table
    auto fill_clause_data = [&](uint32_t c_idx, const std::vector<std::pair<uint32_t, int8_t>>& cl_lits) {
        uint32_t mt = c_idx / TILE;
        uint32_t m_row = c_idx % TILE;
        uint32_t start_idx = ctl.m_tile_start[mt];
        uint32_t end_idx = ctl.m_tile_start[mt + 1];
        if (start_idx == end_idx) return;

        for (auto const& lit : cl_lits) {
            uint32_t v_perm = ctl.var_inv[lit.first];
            uint32_t kt = v_perm / TILE;
            uint32_t k_col = v_perm % TILE;

            // Binary search for kt in unique_tiles[start_idx .. end_idx - 1]
            uint32_t low = start_idx;
            uint32_t high = end_idx - 1;
            int32_t t_idx = -1;
            while (low <= high) {
                uint32_t mid = low + (high - low) / 2;
                if (unique_tiles[mid].k_tile == kt) {
                    t_idx = mid;
                    break;
                } else if (unique_tiles[mid].k_tile < kt) {
                    low = mid + 1;
                } else {
                    if (mid == 0) break;
                    high = mid - 1;
                }
            }

            if (t_idx >= 0) {
                size_t offset = (size_t)t_idx * 256 + m_row * 16 + k_col;
                ctl.A[offset] = lit.second;
                ctl.A_abs[offset] = 1;
            }
        }
    };

    clause_idx = 0;
    for (auto const& bin : bins) {
        cl_lits.clear();
        if (bin.first.var() < num_vars) cl_lits.push_back({bin.first.var(), bin.first.sign() ? -1 : 1});
        if (bin.second.var() < num_vars) cl_lits.push_back({bin.second.var(), bin.second.sign() ? -1 : 1});
        fill_clause_data(clause_idx++, cl_lits);
    }

    for (clause* c : m_clauses) {
        if (c->was_removed()) continue;
        cl_lits.clear();
        for (unsigned i = 0; i < c->size(); ++i) {
            literal l = (*c)[i];
            if (l.var() < num_vars) cl_lits.push_back({l.var(), l.sign() ? -1 : 1});
        }
        fill_clause_data(clause_idx++, cl_lits);
    }

    for (clause* c : m_learned) {
        if (c->was_removed()) continue;
        cl_lits.clear();
        for (unsigned i = 0; i < c->size(); ++i) {
            literal l = (*c)[i];
            if (l.var() < num_vars) cl_lits.push_back({l.var(), l.sign() ? -1 : 1});
        }
        fill_clause_data(clause_idx++, cl_lits);
    }

    auto end_fill = std::chrono::high_resolution_clock::now();
    double fill_sec = std::chrono::duration<double>(end_fill - start_fill).count();
    double total_sec = std::chrono::duration<double>(end_fill - start_total).count();
    IF_VERBOSE(0, verbose_stream() << "[MatrixBuild] Step 4 (Data Fill): " << fill_sec << "s\n";);
    IF_VERBOSE(0, verbose_stream() << "[MatrixBuild] Total Build Time: " << total_sec << "s\n";);

    return ctl;
}

} /* namespace sat */

#endif /* BOOLEDASS_SPARSE_TILE_H */
