; QF_BV benchmark: Chained 64-bit ARX network (1 chains)
; Designed to produce >200K clauses for GPU BCP evaluation
(set-logic QF_BV)

(declare-fun x_0_0 () (_ BitVec 64))
(declare-fun x_0_1 () (_ BitVec 64))
(declare-fun x_0_2 () (_ BitVec 64))
(declare-fun x_0_3 () (_ BitVec 64))
(declare-fun x_0_4 () (_ BitVec 64))

; === Intra-chain constraints (multiplication + rotation + XOR) ===

; Chain 0
(assert (= x_0_1 (bvxor (bvmul x_0_0 (_ bv3735928559 64)) (bvor (bvshl x_0_0 (_ bv7 64)) (bvlshr x_0_0 (_ bv57 64))))))
(assert (= x_0_2 (bvmul x_0_0 x_0_1)))
(assert (= x_0_3 (bvxor (bvadd x_0_1 x_0_2) (bvor (bvshl x_0_2 (_ bv11 64)) (bvlshr x_0_2 (_ bv53 64))))))
(assert (= x_0_4 (bvmul x_0_2 x_0_3)))

; === Inter-chain constraints (cross-chain XOR mixing) ===
(assert (= (bvxor x_0_4 x_0_0) (_ bv4277009102 64)))

; === Range constraints ===
(assert (bvugt x_0_0 (_ bv4294967296 64)))
(assert (bvult x_0_0 (_ bv9223372036854775808 64)))

(check-sat)
