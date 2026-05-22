# BooledASS vs Baseline Z3: 10 QF_BV Benchmarks Comparison

Detailed performance evaluation of the optimized **BooledASS** solver (featuring joint full-adder internalization and ITE-shared carry gate optimizations) compared to the standard **Baseline Z3** solver.

| Benchmark | Logic / Status | Metric | Baseline Z3 | BooledASS | Change / Speedup |
| :--- | :--- | :--- | :---: | :---: | :---: |
| **test_qfbv.smt2** | SAT | SAT Variables | 38 | 38 | **0.0%** |
| | | Total SAT Clauses | 105 | 105 | **0.0%** |
| | | SAT Conflicts | 5 | 5 | **0.0%** |
| | | Solving Time | 0.01s | 0.01s | **N/A (<0.02s)** |
|--- |--- |--- |--- |--- |--- |
| **test_qfbv_hard.smt2** | UNSAT | SAT Variables | 1 | 1 | **0.0%** |
| | | Total SAT Clauses | 0 | 0 | **0.0%** |
| | | SAT Conflicts | 0 | 0 | **0.0%** |
| | | Solving Time | 0.00s | 0.00s | **N/A (<0.02s)** |
|--- |--- |--- |--- |--- |--- |
| **bench_qfbv_mult16.smt2** | SAT | SAT Variables | 2,305 | 1,738 | **-24.6%** |
| | | Total SAT Clauses | 7,865 | 7,067 | **-10.1%** |
| | | SAT Conflicts | 26 | 61 | **+134.6%** |
| | | Solving Time | 0.01s | 0.01s | **N/A (<0.02s)** |
|--- |--- |--- |--- |--- |--- |
| **bench_qfbv_mult32.smt2** | SAT | SAT Variables | 9,838 | 7,180 | **-27.0%** |
| | | Total SAT Clauses | 59,103 | 29,805 | **-49.6%** |
| | | SAT Conflicts | 168 | 115 | **-31.5%** |
| | | Solving Time | 0.07s | 0.02s | **N/A (<0.02s)** |
|--- |--- |--- |--- |--- |--- |
| **bench_qfbv_mult64.smt2** | SAT | SAT Variables | 40,646 | 29,204 | **-28.2%** |
| | | Total SAT Clauses | 247,468 | 218,407 | **-11.7%** |
| | | SAT Conflicts | 877 | 2,479 | **+182.7%** |
| | | Solving Time | 0.31s | 0.35s | **-12.9%** |
|--- |--- |--- |--- |--- |--- |
| **bench_comm_96.smt2** | UNSAT | SAT Variables | 1 | 1 | **0.0%** |
| | | Total SAT Clauses | 0 | 0 | **0.0%** |
| | | SAT Conflicts | 0 | 0 | **0.0%** |
| | | Solving Time | 0.00s | 0.00s | **N/A (<0.02s)** |
|--- |--- |--- |--- |--- |--- |
| **bench_dist_96.smt2** | UNSAT | SAT Variables | 1 | 1 | **0.0%** |
| | | Total SAT Clauses | 0 | 0 | **0.0%** |
| | | SAT Conflicts | 0 | 0 | **0.0%** |
| | | Solving Time | 0.00s | 0.00s | **N/A (<0.02s)** |
|--- |--- |--- |--- |--- |--- |
| **test_crypto.smt2** | SAT | SAT Variables | 7,720 | 5,305 | **-31.3%** |
| | | Total SAT Clauses | 168,980 | 64,703 | **-61.7%** |
| | | SAT Conflicts | 114,046 | 20,687 | **-81.9%** |
| | | Solving Time | 8.29s | 1.54s | **+81.4% Speedup** |
|--- |--- |--- |--- |--- |--- |
| **bench_factor64.smt2** | UNSAT | SAT Variables | 8,116 | 6,213 | **-23.4%** |
| | | Total SAT Clauses | 62,631 | 52,569 | **-16.1%** |
| | | SAT Conflicts | 15,529 | 11,388 | **-26.7%** |
| | | Solving Time | 0.96s | 0.56s | **+41.7% Speedup** |
|--- |--- |--- |--- |--- |--- |
| **bench_wrap_128.smt2** | SAT | SAT Variables | 56,269 | 40,519 | **-28.0%** |
| | | Total SAT Clauses | 340,782 | 296,016 | **-13.1%** |
| | | SAT Conflicts | 2,161 | 1,302 | **-39.8%** |
| | | Solving Time | 0.47s | 0.34s | **+27.7% Speedup** |
|--- |--- |--- |--- |--- |--- |