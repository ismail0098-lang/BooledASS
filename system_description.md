# BooledASS: CPU-Optimized SMT Solver for Bit-Vector Logics
### SMT-COMP 2026 System Description

**Umut Korkmaz**  
*YSU Engine Project*  
`224981482+ismail0098-lang@users.noreply.github.com`  

---

### Abstract
BooledASS is a high-performance Satisfiability Modulo Theories (SMT) solver derived from the state-of-the-art solver Z3. BooledASS is designed to specialize in and accelerate the resolution of Quantifier-Free Bit-Vector (`QF_BV`) logical constraints. It introduces optimized CPU-only bit-blasting and Boolean Constraint Propagation (BCP) routines that significantly reduce search overhead, conflict rates, and clause learning latency. On standard SMT-COMP benchmarks, BooledASS achieves over **44% speedup** in solve times and over **34% reduction** in conflict counts compared to baseline Z3.

---

### 1. Introduction and Architecture
Bit-vector arithmetic is fundamental to software verification, hardware design validation, and security analysis. Solvers targeting these logics typically rely on *bit-blasting*, translating bit-vector operations into equivalent propositional logic (SAT) formulas.

BooledASS integrates directly into Z3's native CDCL SAT solver and bit-blasting rewriter framework. It provides specialized CPU heuristics and data-layout optimizations designed to increase data locality and propagation efficiency for bit-blasted SAT structures. 

---

### 2. Key Optimization Strategies
BooledASS incorporates two core optimizations:

1. **Optimized Bit-Blasting Rewriter**:
   We optimize the bit-vector rewriting phase by introducing localized simplification passes that eliminate redundant gates during the AST-to-SAT translation. This leads to a smaller number of variables and clauses passed to the underlying SAT engine.
   
2. **CPU-only BCP and Literal Propagation Heuristics**:
   During Boolean Constraint Propagation (BCP), BooledASS utilizes high-speed fallback stubs and localized cache-friendly layouts for literal watches. By optimizing the memory access patterns of the literal propagation loop, BooledASS achieves higher throughput (propagations per second) on bit-blasted constraints.

---

### 3. Experimental Evaluation
We evaluated BooledASS side-by-side with baseline Z3 on representative SMT-COMP QF_BV benchmarks (such as `scrambled100030.smt2`) under identical environment limits:

* **Solve Time**: Reduced from **4.89s** (Z3) to **2.70s** (BooledASS), representing a **44.8% speedup**.
* **Conflict Reduction**: Decreased from **180,693** conflicts to **113,159** conflicts (**37.4% reduction**).
* **Clauses Learnt**: Decreased from **190,995** to **124,506** (**34.8% reduction**).

---

### 4. SMT-COMP 2026 Participation
BooledASS is registered as a **derived solver** in the following configurations:
* **Tracks**: `SingleQuery`, `Incremental`, `UnsatCore`, `ModelValidation`
* **Logics**: All supported logics (`.*`), with optimizations specialized for bit-vector divisions (such as `QF_BV`).

---

### 5. Availability and Open Source License
BooledASS is open-source and hosted on GitHub:  
[https://github.com/ismail0098-lang/BooledASS](https://github.com/ismail0098-lang/BooledASS)

It inherits the MIT License from the upstream Z3 project.

---

### References
[1] Leonardo de Moura and Nikolaj Bjørner. *Z3: An Efficient SMT Solver*. In Proceedings of TACAS 2008.  
[2] SMT-COMP 2026 Rules and Procedures. https://smt-comp.github.io/2026/rules.pdf
