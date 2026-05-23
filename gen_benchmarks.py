"""
Generate a hard QF_BV benchmark that produces >200K clauses and takes 1-2 minutes.
Strategy: Chain of 128-bit multiplications with partial output constraints,
creating a system where the solver must search extensively.
"""

def gen_benchmark(filename, num_chains=8, width=128):
    with open(filename, 'w') as f:
        f.write(f"; QF_BV benchmark: Chained {width}-bit ARX network ({num_chains} chains)\n")
        f.write(f"; Designed to produce >200K clauses for GPU BCP evaluation\n")
        f.write("(set-logic QF_BV)\n\n")
        
        all_vars = []
        
        # Declare chain variables
        for c in range(num_chains):
            for i in range(5):  # 5 variables per chain
                vname = f"x_{c}_{i}"
                f.write(f"(declare-fun {vname} () (_ BitVec {width}))\n")
                all_vars.append(vname)
        
        f.write("\n; === Intra-chain constraints (multiplication + rotation + XOR) ===\n")
        
        for c in range(num_chains):
            # Each chain: x[i+1] = f(x[i], x[i-1]) with multiplications
            # Multiplication is the key - it generates ~width^2 clauses when bit-blasted
            f.write(f"\n; Chain {c}\n")
            
            # x[c][1] = x[c][0] * some_constant + rotate(x[c][0])
            rot_amt = 7 + c * 3
            back_rot = width - rot_amt
            f.write(f"(assert (= x_{c}_1 (bvxor (bvmul x_{c}_0 (_ bv{0xDEADBEEF + c * 0x1111} {width})) "
                    f"(bvor (bvshl x_{c}_0 (_ bv{rot_amt} {width})) (bvlshr x_{c}_0 (_ bv{back_rot} {width}))))))\n")
            
            # x[c][2] = x[c][0] * x[c][1] (full multiplication - very expensive in bit-blast)
            f.write(f"(assert (= x_{c}_2 (bvmul x_{c}_0 x_{c}_1)))\n")
            
            # x[c][3] = (x[c][1] + x[c][2]) XOR rotate(x[c][2])
            rot_amt2 = 11 + c * 2
            back_rot2 = width - rot_amt2
            f.write(f"(assert (= x_{c}_3 (bvxor (bvadd x_{c}_1 x_{c}_2) "
                    f"(bvor (bvshl x_{c}_2 (_ bv{rot_amt2} {width})) (bvlshr x_{c}_2 (_ bv{back_rot2} {width}))))))\n")
            
            # x[c][4] = x[c][2] * x[c][3] (another full multiplication)
            f.write(f"(assert (= x_{c}_4 (bvmul x_{c}_2 x_{c}_3)))\n")
        
        f.write("\n; === Inter-chain constraints (cross-chain XOR mixing) ===\n")
        for c in range(num_chains - 1):
            f.write(f"(assert (= (bvxor x_{c}_4 x_{c+1}_0) "
                    f"(_ bv{0xCAFEBABE + c * 0x12345678} {width})))\n")
        
        # Close the loop
        f.write(f"(assert (= (bvxor x_{num_chains-1}_4 x_0_0) "
                f"(_ bv{0xFEEDFACE} {width})))\n")
        
        f.write("\n; === Range constraints ===\n")
        for c in range(num_chains):
            f.write(f"(assert (bvugt x_{c}_0 (_ bv{2**32 + c * 1000} {width})))\n")
            f.write(f"(assert (bvult x_{c}_0 (_ bv{2**(width-1)} {width})))\n")
        
        f.write("\n(check-sat)\n")
    
    print(f"Generated {filename}")

# Generate two benchmarks of different sizes
gen_benchmark("bench_gpu_arx_medium.smt2", num_chains=4, width=64)
gen_benchmark("bench_gpu_arx_large.smt2", num_chains=6, width=128)
