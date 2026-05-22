(set-logic QF_BV)
; Cryptographic hash collision simulation — forces deep bit-blasting
(declare-fun x0 () (_ BitVec 32))
(declare-fun x1 () (_ BitVec 32))
(declare-fun x2 () (_ BitVec 32))
(declare-fun x3 () (_ BitVec 32))

; Define non-linear mixing (Feistel-like rounds)
(define-fun round1 () (_ BitVec 32)
  (bvxor (bvadd (bvmul x0 #x6D5A56DA) (bvmul x1 #x8F1BBCDC))
         (bvor (bvshl x2 (_ bv7 32)) (bvlshr x2 (_ bv25 32)))))

(define-fun round2 () (_ BitVec 32)
  (bvxor (bvadd (bvmul x1 #x5A827999) (bvmul x2 #xCA62C1D6))
         (bvor (bvshl x3 (_ bv11 32)) (bvlshr x3 (_ bv21 32)))))

(define-fun round3 () (_ BitVec 32)
  (bvxor (bvadd (bvmul x2 #x6ED9EBA1) (bvmul x3 #x8F1BBCDC))
         (bvor (bvshl x0 (_ bv13 32)) (bvlshr x0 (_ bv19 32)))))

; Constrain to specific output (like finding a hash preimage)
(assert (= round1 #xA5A5A5A5))
(assert (= round2 #x5A5A5A5A))
(assert (= round3 #xDEADFACE))
(assert (bvugt x0 #x00000000))
(assert (bvugt x1 #x00000000))
(assert (bvugt x2 #x00000000))
(assert (bvugt x3 #x00000000))

(check-sat)
