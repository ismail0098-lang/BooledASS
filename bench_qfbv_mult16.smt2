(set-logic QF_BV)

; ─── 16-bit multiplier verification ───
; This is a classic hard QF_BV benchmark: verify that
; a = b * c implies properties about bit patterns.
; After bit-blasting, this produces ~1000+ SAT clauses.

(declare-fun a () (_ BitVec 16))
(declare-fun b () (_ BitVec 16))
(declare-fun c () (_ BitVec 16))
(declare-fun d () (_ BitVec 16))

; Multiply constraints (non-linear → large bit-blast)
(assert (= a (bvmul b c)))
(assert (= d (bvadd (bvmul a b) (bvmul c d))))

; Range constraints
(assert (bvugt b (_ bv255 16)))
(assert (bvugt c (_ bv255 16)))
(assert (bvult a (_ bv60000 16)))
(assert (not (= d (_ bv0 16))))

; XOR mixing to prevent algebraic shortcuts
(assert (= (bvxor a d) (bvand b c)))

(check-sat)
