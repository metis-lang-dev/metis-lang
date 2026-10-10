-- SPDX-License-Identifier: Apache-2.0
/-
The counting kernel of Theorem 1 (run-level preservation), paper §3.

An *instance* of a ground clause at a marking, in the ordered-resource
interpreter, chooses per species an injective assignment of consume
slots to tokens and one token per read occurrence.  We prove the
instance count is exactly the mass-action weight

    φ(m, r) = Π_a  m(a)^(underline c_r(a)) · Π_a m(a)^(p_r(a))

(falling factorials on consumed species, powers on read species), and
that the instance→clause pushforward carries weight w·φ — the DBN's
CHOICE weight.  This is the substantive combinatorial content of
Theorem 1; the surrounding product induction is routine and remains on
paper.
-/

import Mathlib

namespace Metis

variable {A : Type*} [Fintype A] [DecidableEq A]

/-- The mass-action count: falling factorial per consumed species,
power per read species.  `m` is the marking, `c` the consume
multiplicities, `p` the read multiplicities (all species-indexed). -/
def phi (m c p : A → ℕ) : ℕ :=
  (∏ a, (m a).descFactorial (c a)) * ∏ a, m a ^ p a

/-- An instance of a clause `(c, p)` at marking `m`: per species, an
injective assignment of consume slots to tokens, and a choice of token
per read occurrence. -/
abbrev Instance (m c p : A → ℕ) : Type _ :=
  (∀ a, Fin (c a) ↪ Fin (m a)) × (∀ a, Fin (p a) → Fin (m a))

/-- **Theorem 1, counting kernel.**  The instances of a clause at a
marking are equinumerous with φ: token individuation forces the
falling-factorial weights. -/
theorem card_instance (m c p : A → ℕ) :
    Fintype.card (Instance m c p) = phi m c p := by
  simp [Instance, phi, Fintype.card_pi, Fintype.card_embedding_eq,
    Fintype.card_fin, Finset.prod_const]

variable {R : Type*} [CommSemiring R]

/-- **Theorem 1, pushforward identity.**  The interpreter draws
instances with probability proportional to the clause prior `w` per
instance; the total (unnormalized) mass reaching a clause is therefore
`w · φ` — the DBN's CHOICE weight `W_r(m)`.  Normalizing over the
enabled set on both sides gives equality of the one-step kernels. -/
theorem pushforward_weight (m c p : A → ℕ) (w : R) :
    ∑ _ι : Instance m c p, w = w * (phi m c p : R) := by
  rw [Finset.sum_const, Finset.card_univ, card_instance, nsmul_eq_mul,
    mul_comm]

end Metis
