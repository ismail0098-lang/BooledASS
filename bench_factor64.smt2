; QF_BV benchmark: 64-bit factoring with multiple entangled constraints
; Designed to create a large, hard SAT instance for GPU BCP evaluation
(set-logic QF_BV)

; Factor a product of two 32-bit primes
(declare-fun p () (_ BitVec 64))
(declare-fun q () (_ BitVec 64))

; The product N = p * q (a known 64-bit composite)
; N = 15241578750190521 = 123456789 * 123456789 (not prime factors, just a test)
; Actually use a product that's harder: 
; 3233 = 53 * 61 is trivial, we need bigger

; p and q are at least 2^16 and at most 2^32
(assert (bvugt p (_ bv65536 64)))
(assert (bvult p (_ bv4294967296 64)))
(assert (bvugt q (_ bv65536 64)))
(assert (bvult q (_ bv4294967296 64)))

; p <= q (symmetry breaking)
(assert (bvule p q))

; p is odd (not a factor of 2)
(assert (= ((_ extract 0 0) p) #b1))
; q is odd
(assert (= ((_ extract 0 0) q) #b1))

; The product: p * q = N
; N = 4611686018427387847 is too large, use something manageable
; Let's use N = 3215031751 = 56891 * 56521
(assert (= (bvmul p q) (_ bv3215031751 64)))

; Additional entanglement constraints to create more clauses
(declare-fun r () (_ BitVec 64))
(assert (= r (bvxor p q)))
(assert (bvugt r (_ bv0 64)))

; Hash-like mixing of p
(declare-fun h () (_ BitVec 64))
(assert (= h (bvxor (bvadd p (bvor (bvshl p (_ bv13 64)) (bvlshr p (_ bv51 64))))
                     (bvsub q (bvand q (bvor (bvshl q (_ bv7 64)) (bvlshr q (_ bv57 64))))))))

; Constraint on h
(assert (bvugt h (_ bv1000 64)))

(check-sat)
(get-model)
