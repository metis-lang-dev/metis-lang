/-
Theorem 2 (exact filtering), paper §3.

The forward filter computes the next slice by summing only over its
current support; the DBN marginal sums over the whole state space (law
of total probability).  We prove the two recursions coincide: states
outside the support carry no mass, so restriction to the reachable
support loses nothing, and the filter is exact inference on the
denoted DBN — not an approximation.
-/

import Mathlib

namespace Metis

variable {σ : Type*} [Fintype σ] [DecidableEq σ]

/-- One filtering step over an explicit support: the next distribution
summed only over `supp`. -/
def filterStep (k : σ → σ → ℚ) (D : σ → ℚ) (supp : Finset σ) : σ → ℚ :=
  fun s' => ∑ s ∈ supp, D s * k s s'

/-- One marginalization step of the DBN: the law of total probability,
summed over the whole state space. -/
def marginalStep (k : σ → σ → ℚ) (D : σ → ℚ) : σ → ℚ :=
  fun s' => ∑ s, D s * k s s'

/-- The support of a distribution presented as a function. -/
def support (D : σ → ℚ) : Finset σ := Finset.univ.filter (D · ≠ 0)

/-- The filter iterated from `D`, always summing over its own current
support. -/
def filterIter (k : σ → σ → ℚ) (D : σ → ℚ) : ℕ → σ → ℚ
  | 0 => D
  | t + 1 => filterStep k (filterIter k D t) (support (filterIter k D t))

/-- The DBN marginal at slice `t`. -/
def marginal (k : σ → σ → ℚ) (D : σ → ℚ) : ℕ → σ → ℚ
  | 0 => D
  | t + 1 => marginalStep k (marginal k D t)

/-- A single step over any set containing the support equals the full
law-of-total-probability step: excluded states carry no mass. -/
theorem filterStep_eq_marginalStep (k : σ → σ → ℚ) (D : σ → ℚ)
    {supp : Finset σ} (h : ∀ s, D s ≠ 0 → s ∈ supp) :
    filterStep k D supp = marginalStep k D := by
  funext s'
  unfold filterStep marginalStep
  refine Finset.sum_subset (Finset.subset_univ supp) fun s _ hs => ?_
  have hD : D s = 0 := by
    by_contra hD
    exact hs (h s hD)
  simp [hD]

/-- **Theorem 2.**  The forward filter computed over the reachable
support at every step equals the DBN's exact slice marginal. -/
theorem filter_eq_marginal (k : σ → σ → ℚ) (D : σ → ℚ) (t : ℕ) :
    filterIter k D t = marginal k D t := by
  induction t with
  | zero => rfl
  | succ t ih =>
      unfold filterIter marginal
      rw [ih, filterStep_eq_marginalStep]
      intro s hs
      simp [support, hs]

end Metis
