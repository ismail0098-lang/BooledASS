# GPU-Accelerated Z3 SAT Solver

This is a modified version of the Z3 SAT solver integrated with the BooledASS GPU BCP (Boolean Constraint Propagation) engine. It is specifically designed and optimized for QF_BV (Quantifier-Free Bit-Vectors) logic benchmarks. It offloads parallel unit propagation to the GPU using CUDA.

## How it works

1. Small problems are solved on the CPU to avoid GPU setup overhead.
2. Large problems automatically switch to the GPU-integrated solver.
3. The solver performs BCP operations on the GPU in parallel, accelerating search on large formulas.

## Threshold control

The solver uses a clause count threshold to decide when to switch from CPU to GPU.
- Default threshold: 200,000 clauses.
- You can override this threshold at runtime using the Z3_GPU_THRESHOLD environment variable.

Example:
$env:Z3_GPU_THRESHOLD=1000000

## How to build

To compile the solver with full GPU/CUDA acceleration support (default, automatically detects NVCC):
```powershell
.\build_z3.bat
```

To compile the solver in **CPU-only mode** (for CPU-only tracks like SMT-COMP, stripping all CUDA library dependencies to prevent binary load crashes on cluster nodes without NVIDIA drivers):
```powershell
.\build_z3.bat cpu
```

Alternatively, you can run CMake directly with:
```bash
cmake -DZ3_GPU=OFF ..
```

## Benchmark Results

Below are the benchmark comparisons between the pure CPU solver and the GPU-integrated solver on QF_BV benchmarks at different clause sizes and conflict limits.

| Benchmark | Clauses | Conflicts | CPU Time | GPU Time | Speedup |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Small (Breakeven)** | 312,474 | 100,000 | 25.02s | 26.60s | -6.3% |
| **Medium** | 624,235 | 100,000 | 67.28s | 61.89s | +8.0% |
| **Large** | 1,248,376 | 200,000 | 520.43s | 500.46s | +3.8% |

These results show that the GPU solver begins outpacing the CPU solver as the problem size scales beyond 300,000 clauses and the conflict search depth increases, successfully amortizing the initial GPU setup and transfer overhead.

