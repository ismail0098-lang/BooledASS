(set-logic QF_BV)
; Harder QF_BV: multiple 32-bit constraints that force bit-blasting
(declare-fun a () (_ BitVec 32))
(declare-fun b () (_ BitVec 32))
(declare-fun c () (_ BitVec 32))
(declare-fun d () (_ BitVec 32))

(assert (= (bvxor a b) #xDEADBEEF))
(assert (= (bvand b c) #x0F0F0F0F))
(assert (= (bvor c d)  #xFFFF0000))
(assert (= (bvadd a d) #x12345678))
(assert (bvugt a #x80000000))
(assert (bvugt b #x00000001))
(assert (bvult c #xF0000000))
(assert (not (= d #x00000000)))

(check-sat)
