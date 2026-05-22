; QF_BV benchmark: Chained 64-bit ARX network (4 chains)
; Designed to produce >200K clauses for GPU BCP evaluation
(set-logic QF_BV)

(declare-fun x_0_0 () (_ BitVec 64))
(declare-fun x_0_1 () (_ BitVec 64))
(declare-fun x_0_2 () (_ BitVec 64))
(declare-fun x_0_3 () (_ BitVec 64))
(declare-fun x_0_4 () (_ BitVec 64))
(declare-fun x_1_0 () (_ BitVec 64))
(declare-fun x_1_1 () (_ BitVec 64))
(declare-fun x_1_2 () (_ BitVec 64))
(declare-fun x_1_3 () (_ BitVec 64))
(declare-fun x_1_4 () (_ BitVec 64))
(declare-fun x_2_0 () (_ BitVec 64))
(declare-fun x_2_1 () (_ BitVec 64))
(declare-fun x_2_2 () (_ BitVec 64))
(declare-fun x_2_3 () (_ BitVec 64))
(declare-fun x_2_4 () (_ BitVec 64))
(declare-fun x_3_0 () (_ BitVec 64))
(declare-fun x_3_1 () (_ BitVec 64))
(declare-fun x_3_2 () (_ BitVec 64))
(declare-fun x_3_3 () (_ BitVec 64))
(declare-fun x_3_4 () (_ BitVec 64))

; === Intra-chain constraints (multiplication + rotation + XOR) ===

; Chain 0
(assert (= x_0_1 (bvxor (bvmul x_0_0 (_ bv3735928559 64)) (bvor (bvshl x_0_0 (_ bv7 64)) (bvlshr x_0_0 (_ bv57 64))))))
(assert (= x_0_2 (bvmul x_0_0 x_0_1)))
(assert (= x_0_3 (bvxor (bvadd x_0_1 x_0_2) (bvor (bvshl x_0_2 (_ bv11 64)) (bvlshr x_0_2 (_ bv53 64))))))
(assert (= x_0_4 (bvmul x_0_2 x_0_3)))

; Chain 1
(assert (= x_1_1 (bvxor (bvmul x_1_0 (_ bv3735932928 64)) (bvor (bvshl x_1_0 (_ bv10 64)) (bvlshr x_1_0 (_ bv54 64))))))
(assert (= x_1_2 (bvmul x_1_0 x_1_1)))
(assert (= x_1_3 (bvxor (bvadd x_1_1 x_1_2) (bvor (bvshl x_1_2 (_ bv13 64)) (bvlshr x_1_2 (_ bv51 64))))))
(assert (= x_1_4 (bvmul x_1_2 x_1_3)))

; Chain 2
(assert (= x_2_1 (bvxor (bvmul x_2_0 (_ bv3735937297 64)) (bvor (bvshl x_2_0 (_ bv13 64)) (bvlshr x_2_0 (_ bv51 64))))))
(assert (= x_2_2 (bvmul x_2_0 x_2_1)))
(assert (= x_2_3 (bvxor (bvadd x_2_1 x_2_2) (bvor (bvshl x_2_2 (_ bv15 64)) (bvlshr x_2_2 (_ bv49 64))))))
(assert (= x_2_4 (bvmul x_2_2 x_2_3)))

; Chain 3
(assert (= x_3_1 (bvxor (bvmul x_3_0 (_ bv3735941666 64)) (bvor (bvshl x_3_0 (_ bv16 64)) (bvlshr x_3_0 (_ bv48 64))))))
(assert (= x_3_2 (bvmul x_3_0 x_3_1)))
(assert (= x_3_3 (bvxor (bvadd x_3_1 x_3_2) (bvor (bvshl x_3_2 (_ bv17 64)) (bvlshr x_3_2 (_ bv47 64))))))
(assert (= x_3_4 (bvmul x_3_2 x_3_3)))

; === Inter-chain constraints (cross-chain XOR mixing) ===
(assert (= (bvxor x_0_4 x_1_0) (_ bv3405691582 64)))
(assert (= (bvxor x_1_4 x_2_0) (_ bv3711111478 64)))
(assert (= (bvxor x_2_4 x_3_0) (_ bv4016531374 64)))
(assert (= (bvxor x_3_4 x_0_0) (_ bv4277009102 64)))

; === Range constraints ===
(assert (bvugt x_0_0 (_ bv4294967296 64)))
(assert (bvult x_0_0 (_ bv9223372036854775808 64)))
(assert (bvugt x_1_0 (_ bv4294968296 64)))
(assert (bvult x_1_0 (_ bv9223372036854775808 64)))
(assert (bvugt x_2_0 (_ bv4294969296 64)))
(assert (bvult x_2_0 (_ bv9223372036854775808 64)))
(assert (bvugt x_3_0 (_ bv4294970296 64)))
(assert (bvult x_3_0 (_ bv9223372036854775808 64)))

(check-sat)
