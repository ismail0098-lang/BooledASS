; QF_BV benchmark: 128-bit crypto-like mixing rounds
; Designed to produce a large SAT instance (>100K clauses) for GPU BCP evaluation
(set-logic QF_BV)

; State words (128-bit AES-like state)
(declare-fun s0 () (_ BitVec 128))
(declare-fun s1 () (_ BitVec 128))
(declare-fun s2 () (_ BitVec 128))
(declare-fun s3 () (_ BitVec 128))

; Key schedule words
(declare-fun k0 () (_ BitVec 128))
(declare-fun k1 () (_ BitVec 128))
(declare-fun k2 () (_ BitVec 128))
(declare-fun k3 () (_ BitVec 128))

; Intermediate values
(declare-fun t0 () (_ BitVec 128))
(declare-fun t1 () (_ BitVec 128))
(declare-fun t2 () (_ BitVec 128))
(declare-fun t3 () (_ BitVec 128))

; Round function: ARX-based mixing (Addition-Rotation-XOR)
; Round 1: t_i = (s_i + k_i) XOR (RotateLeft(s_{i+1 mod 4}, 7))
(assert (= t0 (bvxor (bvadd s0 k0) (bvor (bvshl s1 (_ bv7 128)) (bvlshr s1 (_ bv121 128))))))
(assert (= t1 (bvxor (bvadd s1 k1) (bvor (bvshl s2 (_ bv11 128)) (bvlshr s2 (_ bv117 128))))))
(assert (= t2 (bvxor (bvadd s2 k2) (bvor (bvshl s3 (_ bv13 128)) (bvlshr s3 (_ bv115 128))))))
(assert (= t3 (bvxor (bvadd s3 k3) (bvor (bvshl s0 (_ bv17 128)) (bvlshr s0 (_ bv111 128))))))

; Key schedule: k' = f(k)
(assert (= k1 (bvxor k0 (bvadd k0 (bvor (bvshl k0 (_ bv3 128)) (bvlshr k0 (_ bv125 128)))))))
(assert (= k2 (bvxor k1 (bvadd k1 (bvor (bvshl k1 (_ bv5 128)) (bvlshr k1 (_ bv123 128)))))))
(assert (= k3 (bvxor k2 (bvadd k2 (bvor (bvshl k2 (_ bv7 128)) (bvlshr k2 (_ bv121 128)))))))

; Known plaintext: fix s0..s3
(assert (= s0 #x00112233445566778899AABBCCDDEEFF))
(assert (= s1 #xFEDCBA9876543210FEDCBA9876543210))
(assert (= s2 #x0F1E2D3C4B5A69788796A5B4C3D2E1F0))
(assert (= s3 #xA5A5A5A5A5A5A5A55A5A5A5A5A5A5A5A))

; Known ciphertext: fix t0..t3 to specific values
; (these are NOT the correct round output — solver must determine if they're achievable)
(assert (= t0 #xDEADBEEFCAFEBABE1234567890ABCDEF))
(assert (= t1 #x0123456789ABCDEF0123456789ABCDEF))
(assert (= t2 #xAAAABBBBCCCCDDDDEEEEFFFF00001111))
(assert (= t3 #x11112222333344445555666677778888))

(check-sat)
