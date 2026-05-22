; QF_BV benchmark: Chained 128-bit ARX network (6 chains)
; Designed to produce >200K clauses for GPU BCP evaluation
(set-logic QF_BV)

(declare-fun x_0_0 () (_ BitVec 128))
(declare-fun x_0_1 () (_ BitVec 128))
(declare-fun x_0_2 () (_ BitVec 128))
(declare-fun x_0_3 () (_ BitVec 128))
(declare-fun x_0_4 () (_ BitVec 128))
(declare-fun x_1_0 () (_ BitVec 128))
(declare-fun x_1_1 () (_ BitVec 128))
(declare-fun x_1_2 () (_ BitVec 128))
(declare-fun x_1_3 () (_ BitVec 128))
(declare-fun x_1_4 () (_ BitVec 128))
(declare-fun x_2_0 () (_ BitVec 128))
(declare-fun x_2_1 () (_ BitVec 128))
(declare-fun x_2_2 () (_ BitVec 128))
(declare-fun x_2_3 () (_ BitVec 128))
(declare-fun x_2_4 () (_ BitVec 128))
(declare-fun x_3_0 () (_ BitVec 128))
(declare-fun x_3_1 () (_ BitVec 128))
(declare-fun x_3_2 () (_ BitVec 128))
(declare-fun x_3_3 () (_ BitVec 128))
(declare-fun x_3_4 () (_ BitVec 128))
(declare-fun x_4_0 () (_ BitVec 128))
(declare-fun x_4_1 () (_ BitVec 128))
(declare-fun x_4_2 () (_ BitVec 128))
(declare-fun x_4_3 () (_ BitVec 128))
(declare-fun x_4_4 () (_ BitVec 128))
(declare-fun x_5_0 () (_ BitVec 128))
(declare-fun x_5_1 () (_ BitVec 128))
(declare-fun x_5_2 () (_ BitVec 128))
(declare-fun x_5_3 () (_ BitVec 128))
(declare-fun x_5_4 () (_ BitVec 128))

; === Intra-chain constraints (multiplication + rotation + XOR) ===

; Chain 0
(assert (= x_0_1 (bvxor (bvmul x_0_0 (_ bv3735928559 128)) (bvor (bvshl x_0_0 (_ bv7 128)) (bvlshr x_0_0 (_ bv121 128))))))
(assert (= x_0_2 (bvmul x_0_0 x_0_1)))
(assert (= x_0_3 (bvxor (bvadd x_0_1 x_0_2) (bvor (bvshl x_0_2 (_ bv11 128)) (bvlshr x_0_2 (_ bv117 128))))))
(assert (= x_0_4 (bvmul x_0_2 x_0_3)))

; Chain 1
(assert (= x_1_1 (bvxor (bvmul x_1_0 (_ bv3735932928 128)) (bvor (bvshl x_1_0 (_ bv10 128)) (bvlshr x_1_0 (_ bv118 128))))))
(assert (= x_1_2 (bvmul x_1_0 x_1_1)))
(assert (= x_1_3 (bvxor (bvadd x_1_1 x_1_2) (bvor (bvshl x_1_2 (_ bv13 128)) (bvlshr x_1_2 (_ bv115 128))))))
(assert (= x_1_4 (bvmul x_1_2 x_1_3)))

; Chain 2
(assert (= x_2_1 (bvxor (bvmul x_2_0 (_ bv3735937297 128)) (bvor (bvshl x_2_0 (_ bv13 128)) (bvlshr x_2_0 (_ bv115 128))))))
(assert (= x_2_2 (bvmul x_2_0 x_2_1)))
(assert (= x_2_3 (bvxor (bvadd x_2_1 x_2_2) (bvor (bvshl x_2_2 (_ bv15 128)) (bvlshr x_2_2 (_ bv113 128))))))
(assert (= x_2_4 (bvmul x_2_2 x_2_3)))

; Chain 3
(assert (= x_3_1 (bvxor (bvmul x_3_0 (_ bv3735941666 128)) (bvor (bvshl x_3_0 (_ bv16 128)) (bvlshr x_3_0 (_ bv112 128))))))
(assert (= x_3_2 (bvmul x_3_0 x_3_1)))
(assert (= x_3_3 (bvxor (bvadd x_3_1 x_3_2) (bvor (bvshl x_3_2 (_ bv17 128)) (bvlshr x_3_2 (_ bv111 128))))))
(assert (= x_3_4 (bvmul x_3_2 x_3_3)))

; Chain 4
(assert (= x_4_1 (bvxor (bvmul x_4_0 (_ bv3735946035 128)) (bvor (bvshl x_4_0 (_ bv19 128)) (bvlshr x_4_0 (_ bv109 128))))))
(assert (= x_4_2 (bvmul x_4_0 x_4_1)))
(assert (= x_4_3 (bvxor (bvadd x_4_1 x_4_2) (bvor (bvshl x_4_2 (_ bv19 128)) (bvlshr x_4_2 (_ bv109 128))))))
(assert (= x_4_4 (bvmul x_4_2 x_4_3)))

; Chain 5
(assert (= x_5_1 (bvxor (bvmul x_5_0 (_ bv3735950404 128)) (bvor (bvshl x_5_0 (_ bv22 128)) (bvlshr x_5_0 (_ bv106 128))))))
(assert (= x_5_2 (bvmul x_5_0 x_5_1)))
(assert (= x_5_3 (bvxor (bvadd x_5_1 x_5_2) (bvor (bvshl x_5_2 (_ bv21 128)) (bvlshr x_5_2 (_ bv107 128))))))
(assert (= x_5_4 (bvmul x_5_2 x_5_3)))

; === Inter-chain constraints (cross-chain XOR mixing) ===
(assert (= (bvxor x_0_4 x_1_0) (_ bv3405691582 128)))
(assert (= (bvxor x_1_4 x_2_0) (_ bv3711111478 128)))
(assert (= (bvxor x_2_4 x_3_0) (_ bv4016531374 128)))
(assert (= (bvxor x_3_4 x_4_0) (_ bv4321951270 128)))
(assert (= (bvxor x_4_4 x_5_0) (_ bv4627371166 128)))
(assert (= (bvxor x_5_4 x_0_0) (_ bv4277009102 128)))

; === Range constraints ===
(assert (bvugt x_0_0 (_ bv4294967296 128)))
(assert (bvult x_0_0 (_ bv170141183460469231731687303715884105728 128)))
(assert (bvugt x_1_0 (_ bv4294968296 128)))
(assert (bvult x_1_0 (_ bv170141183460469231731687303715884105728 128)))
(assert (bvugt x_2_0 (_ bv4294969296 128)))
(assert (bvult x_2_0 (_ bv170141183460469231731687303715884105728 128)))
(assert (bvugt x_3_0 (_ bv4294970296 128)))
(assert (bvult x_3_0 (_ bv170141183460469231731687303715884105728 128)))
(assert (bvugt x_4_0 (_ bv4294971296 128)))
(assert (bvult x_4_0 (_ bv170141183460469231731687303715884105728 128)))
(assert (bvugt x_5_0 (_ bv4294972296 128)))
(assert (bvult x_5_0 (_ bv170141183460469231731687303715884105728 128)))

(check-sat)
