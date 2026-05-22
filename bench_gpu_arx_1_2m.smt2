; QF_BV benchmark: Chained 64-bit ARX network (8 chains)
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
(declare-fun x_4_0 () (_ BitVec 64))
(declare-fun x_4_1 () (_ BitVec 64))
(declare-fun x_4_2 () (_ BitVec 64))
(declare-fun x_4_3 () (_ BitVec 64))
(declare-fun x_4_4 () (_ BitVec 64))
(declare-fun x_5_0 () (_ BitVec 64))
(declare-fun x_5_1 () (_ BitVec 64))
(declare-fun x_5_2 () (_ BitVec 64))
(declare-fun x_5_3 () (_ BitVec 64))
(declare-fun x_5_4 () (_ BitVec 64))
(declare-fun x_6_0 () (_ BitVec 64))
(declare-fun x_6_1 () (_ BitVec 64))
(declare-fun x_6_2 () (_ BitVec 64))
(declare-fun x_6_3 () (_ BitVec 64))
(declare-fun x_6_4 () (_ BitVec 64))
(declare-fun x_7_0 () (_ BitVec 64))
(declare-fun x_7_1 () (_ BitVec 64))
(declare-fun x_7_2 () (_ BitVec 64))
(declare-fun x_7_3 () (_ BitVec 64))
(declare-fun x_7_4 () (_ BitVec 64))

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

; Chain 4
(assert (= x_4_1 (bvxor (bvmul x_4_0 (_ bv3735946035 64)) (bvor (bvshl x_4_0 (_ bv19 64)) (bvlshr x_4_0 (_ bv45 64))))))
(assert (= x_4_2 (bvmul x_4_0 x_4_1)))
(assert (= x_4_3 (bvxor (bvadd x_4_1 x_4_2) (bvor (bvshl x_4_2 (_ bv19 64)) (bvlshr x_4_2 (_ bv45 64))))))
(assert (= x_4_4 (bvmul x_4_2 x_4_3)))

; Chain 5
(assert (= x_5_1 (bvxor (bvmul x_5_0 (_ bv3735950404 64)) (bvor (bvshl x_5_0 (_ bv22 64)) (bvlshr x_5_0 (_ bv42 64))))))
(assert (= x_5_2 (bvmul x_5_0 x_5_1)))
(assert (= x_5_3 (bvxor (bvadd x_5_1 x_5_2) (bvor (bvshl x_5_2 (_ bv21 64)) (bvlshr x_5_2 (_ bv43 64))))))
(assert (= x_5_4 (bvmul x_5_2 x_5_3)))

; Chain 6
(assert (= x_6_1 (bvxor (bvmul x_6_0 (_ bv3735954773 64)) (bvor (bvshl x_6_0 (_ bv25 64)) (bvlshr x_6_0 (_ bv39 64))))))
(assert (= x_6_2 (bvmul x_6_0 x_6_1)))
(assert (= x_6_3 (bvxor (bvadd x_6_1 x_6_2) (bvor (bvshl x_6_2 (_ bv23 64)) (bvlshr x_6_2 (_ bv41 64))))))
(assert (= x_6_4 (bvmul x_6_2 x_6_3)))

; Chain 7
(assert (= x_7_1 (bvxor (bvmul x_7_0 (_ bv3735959142 64)) (bvor (bvshl x_7_0 (_ bv28 64)) (bvlshr x_7_0 (_ bv36 64))))))
(assert (= x_7_2 (bvmul x_7_0 x_7_1)))
(assert (= x_7_3 (bvxor (bvadd x_7_1 x_7_2) (bvor (bvshl x_7_2 (_ bv25 64)) (bvlshr x_7_2 (_ bv39 64))))))
(assert (= x_7_4 (bvmul x_7_2 x_7_3)))

; === Inter-chain constraints (cross-chain XOR mixing) ===
(assert (= (bvxor x_0_4 x_1_0) (_ bv3405691582 64)))
(assert (= (bvxor x_1_4 x_2_0) (_ bv3711111478 64)))
(assert (= (bvxor x_2_4 x_3_0) (_ bv4016531374 64)))
(assert (= (bvxor x_3_4 x_4_0) (_ bv4321951270 64)))
(assert (= (bvxor x_4_4 x_5_0) (_ bv4627371166 64)))
(assert (= (bvxor x_5_4 x_6_0) (_ bv4932791062 64)))
(assert (= (bvxor x_6_4 x_7_0) (_ bv5238210958 64)))
(assert (= (bvxor x_7_4 x_0_0) (_ bv4277009102 64)))

; === Range constraints ===
(assert (bvugt x_0_0 (_ bv4294967296 64)))
(assert (bvult x_0_0 (_ bv9223372036854775808 64)))
(assert (bvugt x_1_0 (_ bv4294968296 64)))
(assert (bvult x_1_0 (_ bv9223372036854775808 64)))
(assert (bvugt x_2_0 (_ bv4294969296 64)))
(assert (bvult x_2_0 (_ bv9223372036854775808 64)))
(assert (bvugt x_3_0 (_ bv4294970296 64)))
(assert (bvult x_3_0 (_ bv9223372036854775808 64)))
(assert (bvugt x_4_0 (_ bv4294971296 64)))
(assert (bvult x_4_0 (_ bv9223372036854775808 64)))
(assert (bvugt x_5_0 (_ bv4294972296 64)))
(assert (bvult x_5_0 (_ bv9223372036854775808 64)))
(assert (bvugt x_6_0 (_ bv4294973296 64)))
(assert (bvult x_6_0 (_ bv9223372036854775808 64)))
(assert (bvugt x_7_0 (_ bv4294974296 64)))
(assert (bvult x_7_0 (_ bv9223372036854775808 64)))

(check-sat)
