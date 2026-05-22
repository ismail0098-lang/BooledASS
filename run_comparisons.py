import subprocess
import re
import os
import sys
import shutil

# Define 10 QF_BV benchmarks
benchmarks = [
    "test_qfbv.smt2",
    "test_qfbv_hard.smt2",
    "bench_qfbv_mult16.smt2",
    "bench_qfbv_mult32.smt2",
    "bench_qfbv_mult64.smt2",
    "bench_comm_96.smt2",
    "bench_dist_96.smt2",
    "test_crypto.smt2",
    "bench_factor64.smt2",
    "bench_wrap_128.smt2"
]

solver_path = os.path.join("build", "Release", "z3.exe")
bench_dir = "c:\\YSU-engine-main\\YSU-engine-main\\src\\Y_lang\\z3_benchmarks"

def run_command(cmd, shell=True):
    res = subprocess.run(cmd, capture_output=True, text=True, shell=shell)
    return res.stdout, res.stderr, res.returncode

def parse_stats(output):
    stats = {
        "status": "unknown",
        "variables": 0,
        "clauses": 0,
        "conflicts": 0,
        "decisions": 0,
        "time": 0.0
    }
    
    # Determine SAT/UNSAT
    if "unsat" in output:
        stats["status"] = "unsat"
    elif "sat" in output:
        stats["status"] = "sat"
        
    # Regex parse statistics
    var_match = re.search(r":sat-mk-var\s+(\d+)", output)
    if var_match:
        stats["variables"] = int(var_match.group(1))
        
    # Sum up binary, ternary and n-ary clauses
    clause_nary = re.search(r":sat-mk-clause-nary\s+(\d+)", output)
    clause_3ary = re.search(r":sat-mk-clause-3ary\s+(\d+)", output)
    clause_2ary = re.search(r":sat-mk-clause-2ary\s+(\d+)", output)
    
    nary = int(clause_nary.group(1)) if clause_nary else 0
    tary = int(clause_3ary.group(1)) if clause_3ary else 0
    bary = int(clause_2ary.group(1)) if clause_2ary else 0
    stats["clauses"] = nary + tary + bary
    
    conflict_match = re.search(r":sat-conflicts\s+(\d+)", output)
    if conflict_match:
        stats["conflicts"] = int(conflict_match.group(1))
        
    decision_match = re.search(r":sat-decisions\s+(\d+)", output)
    if decision_match:
        stats["decisions"] = int(decision_match.group(1))
        
    time_match = re.search(r":total-time\s+([\d.]+)", output)
    if time_match:
        stats["time"] = float(time_match.group(1))
    else:
        time_match_alt = re.search(r":time\s+([\d.]+)", output)
        if time_match_alt:
            stats["time"] = float(time_match_alt.group(1))
            
    return stats

def collect_results():
    results = {}
    for bench in benchmarks:
        bench_path = os.path.join(bench_dir, bench)
        print(f"Running {bench} from {bench_dir}...")
        stdout, stderr, code = run_command([solver_path, "-st", bench_path])
        # Allow code != 0 if output contains sat or unsat (expected for get-model on unsat)
        if code != 0 and not ("sat" in stdout or "unsat" in stdout):
            print(f"Error running {bench}: {stderr}", file=sys.stderr)
        results[bench] = parse_stats(stdout)
    return results

def build_solver():
    print("Building Z3 solver...")
    # Compile directly using cmd.exe with the proper visual studio build tools path
    build_cmd = (
        'call "C:\\Program Files (x86)\\Microsoft Visual Studio\\2022\\BuildTools\\VC\\Auxiliary\\Build\\vcvars64.bat" && '
        'set "PATH=C:\\Program Files (x86)\\Microsoft Visual Studio\\2022\\BuildTools\\Common7\\IDE\\CommonExtensions\\Microsoft\\CMake\\CMake\\bin;%PATH%" && '
        'cmake --build build --config Release --parallel 8'
    )
    out, err, code = run_command(build_cmd)
    if code != 0:
        print(f"Build failed: {err}\n{out}", file=sys.stderr)
        sys.exit(1)
    print("Build successful.")

def main():
    # Make sure target folder exists and copy files
    if not os.path.exists(bench_dir):
        os.makedirs(bench_dir)
    for bench in benchmarks:
        if os.path.exists(bench):
            shutil.copy(bench, os.path.join(bench_dir, bench))

    print("=== Step 1: Collect results for Optimized BooledASS ===")
    booledass_results = collect_results()
    
    print("\n=== Step 2: Checking out origin/master to revert to baseline Z3 ===")
    stdout, stderr, code = run_command(["git", "checkout", "origin/master"])
    print(stdout, stderr)
    
    try:
        build_solver()
        
        print("\n=== Step 3: Collect results for Baseline Z3 ===")
        baseline_results = collect_results()
    finally:
        print("\n=== Step 4: Restoring optimizations ===")
        stdout, stderr, code = run_command(["git", "checkout", "master"])
        print(stdout, stderr)
        build_solver()
        
    # Generate markdown report
    report = []
    report.append("# BooledASS vs Baseline Z3: 10 QF_BV Benchmarks Comparison\n")
    report.append("Detailed performance evaluation of the optimized **BooledASS** solver (featuring joint full-adder internalization and ITE-shared carry gate optimizations) compared to the standard **Baseline Z3** solver.\n")
    
    headers = "| Benchmark | Logic / Status | Metric | Baseline Z3 | BooledASS | Change / Speedup |"
    sep = "| :--- | :--- | :--- | :---: | :---: | :---: |"
    report.append(headers)
    report.append(sep)
    
    for bench in benchmarks:
        b_res = baseline_results.get(bench, {})
        o_res = booledass_results.get(bench, {})
        
        status = o_res.get("status", "unknown").upper()
        
        # Variable comparison
        b_var = b_res.get("variables", 0)
        o_var = o_res.get("variables", 0)
        var_change = f"{((o_var - b_var) / b_var * 100):+.1f}%" if b_var > 0 else "0.0%"
        if b_var == o_var: var_change = "0.0%"
        
        # Clause comparison
        b_cls = b_res.get("clauses", 0)
        o_cls = o_res.get("clauses", 0)
        cls_change = f"{((o_cls - b_cls) / b_cls * 100):+.1f}%" if b_cls > 0 else "0.0%"
        if b_cls == o_cls: cls_change = "0.0%"
        
        # Conflicts comparison
        b_cnf = b_res.get("conflicts", 0)
        o_cnf = o_res.get("conflicts", 0)
        cnf_change = f"{((o_cnf - b_cnf) / b_cnf * 100):+.1f}%" if b_cnf > 0 else "0.0%"
        if b_cnf == o_cnf: cnf_change = "0.0%"
        
        # Time comparison
        b_time = b_res.get("time", 0.0)
        o_time = o_res.get("time", 0.0)
        if b_time > 0.02 and o_time > 0.02:
            time_speedup = f"+{((b_time - o_time) / b_time * 100):.1f}% Speedup" if b_time >= o_time else f"-{((o_time - b_time) / b_time * 100):.1f}%"
        else:
            time_speedup = "N/A (<0.02s)"
            
        report.append(f"| **{bench}** | {status} | SAT Variables | {b_var:,} | {o_var:,} | **{var_change}** |")
        report.append(f"| | | Total SAT Clauses | {b_cls:,} | {o_cls:,} | **{cls_change}** |")
        report.append(f"| | | SAT Conflicts | {b_cnf:,} | {o_cnf:,} | **{cnf_change}** |")
        report.append(f"| | | Solving Time | {b_time:.2f}s | {o_time:.2f}s | **{time_speedup}** |")
        report.append("|--- |--- |--- |--- |--- |--- |")

    report_text = "\n".join(report)
    print("\n=== COMPARISON REPORT ===")
    print(report_text)
    
    with open("benchmark_comparison_report.md", "w") as f:
        f.write(report_text)
    print("\nSaved report to benchmark_comparison_report.md")

if __name__ == "__main__":
    main()
