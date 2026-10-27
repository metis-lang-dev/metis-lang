-- SPDX-License-Identifier: Apache-2.0
/-
Belief through a finite port, paper §Belief.

Theorem 5 (a port is a mixture): the one-tick instrument started from a
mixture of initial states gives the mixture of the single-world answers,
because the forward filter is linear in its initial distribution.  The
cut bound: a filter that drops states returns an interval [lo, lo + CUT]
that brackets the exact number, because a stochastic kernel moves the
dropped mass around without creating or destroying it.  The sheet: a
belief table's side conditions are decidable on concrete data.
-/

import Mathlib
import Formal.Filter

namespace Metis

variable {σ : Type*} [Fintype σ] [DecidableEq σ]

/-! ### The filter is linear -/

/-- One marginalization step commutes with a finite weighted sum of
distributions. -/
theorem marginalStep_sum {ι : Type*} (k : σ → σ → ℚ) (W : Finset ι)
    (p : ι → ℚ) (D : ι → σ → ℚ) :
    marginalStep k (fun s => ∑ w ∈ W, p w * D w s)
      = fun s' => ∑ w ∈ W, p w * marginalStep k (D w) s' := by
  funext s'
  unfold marginalStep
  simp only [Finset.sum_mul, Finset.mul_sum, mul_assoc]
  exact Finset.sum_comm

/-- The `t`-step marginal of a weighted sum of distributions is the
weighted sum of their marginals. -/
theorem marginal_sum {ι : Type*} (k : σ → σ → ℚ) (W : Finset ι)
    (p : ι → ℚ) (D : ι → σ → ℚ) (t : ℕ) :
    marginal k (fun s => ∑ w ∈ W, p w * D w s) t
      = fun s => ∑ w ∈ W, p w * marginal k (D w) t s := by
  induction t with
  | zero => rfl
  | succ t ih =>
      have h : marginal k (fun s => ∑ w ∈ W, p w * D w s) (t + 1)
          = marginalStep k (marginal k (fun s => ∑ w ∈ W, p w * D w s) t) := rfl
      rw [h, ih, marginalStep_sum]
      rfl

/-- The point mass at a state. -/
def point (s₀ : σ) : σ → ℚ := fun s => if s = s₀ then 1 else 0

/-- The mass on an outcome set `Q` after `h` steps. -/
def hit (k : σ → σ → ℚ) (Q : Finset σ) (D : σ → ℚ) (h : ℕ) : ℚ :=
  ∑ s ∈ Q, marginal k D h s

/-- The kernel with `Q` made absorbing: a state where the outcome holds
is not expanded.  `hit (absorb k Q) Q D h` is the first-passage
probability of `Q` within `h` steps. -/
def absorb (k : σ → σ → ℚ) (Q : Finset σ) : σ → σ → ℚ :=
  fun s s' => if s ∈ Q then (if s' = s then 1 else 0) else k s s'

/-- **Theorem 5 (a port is a mixture).**  The instrument started from
the world mixture `∑ w, P(w) · δ(init w)` returns `∑ w, P(w) · (the
answer in world w)`, for any kernel, outcome and horizon.  With the
absorbing kernel this is the first-passage number. -/
theorem hit_mixture {ι : Type*} (k : σ → σ → ℚ) (Q : Finset σ)
    (W : Finset ι) (P : ι → ℚ) (init : ι → σ) (h : ℕ) :
    hit k Q (fun s => ∑ w ∈ W, P w * point (init w) s) h
      = ∑ w ∈ W, P w * hit k Q (point (init w)) h := by
  unfold hit
  rw [marginal_sum]
  simp only [Finset.mul_sum]
  exact Finset.sum_comm

/-! ### The cut bound -/

/-- The retained recursion: at step `t` the filter expands only the
states of `R t` and sets the rest aside. -/
def retained (k : σ → σ → ℚ) (D : σ → ℚ) (R : ℕ → Finset σ) : ℕ → σ → ℚ
  | 0 => D
  | t + 1 => marginalStep k (fun s => if s ∈ R t then retained k D R t s else 0)

/-- The mass set aside through step `t`. -/
def cutMass (k : σ → σ → ℚ) (D : σ → ℚ) (R : ℕ → Finset σ) : ℕ → ℚ
  | 0 => 0
  | t + 1 => cutMass k D R t + ∑ s ∈ Finset.univ \ R t, retained k D R t s

theorem marginalStep_add (k : σ → σ → ℚ) (F G : σ → ℚ) :
    marginalStep k (fun s => F s + G s)
      = fun s' => marginalStep k F s' + marginalStep k G s' := by
  funext s'
  unfold marginalStep
  simp only [add_mul, Finset.sum_add_distrib]

theorem marginalStep_sub (k : σ → σ → ℚ) (F G : σ → ℚ) :
    marginalStep k (fun s => F s - G s)
      = fun s' => marginalStep k F s' - marginalStep k G s' := by
  funext s'
  unfold marginalStep
  simp only [sub_mul, Finset.sum_sub_distrib]

theorem marginalStep_nonneg (k : σ → σ → ℚ) (hk : ∀ s s', 0 ≤ k s s')
    (F : σ → ℚ) (hF : ∀ s, 0 ≤ F s) (s' : σ) : 0 ≤ marginalStep k F s' := by
  unfold marginalStep
  exact Finset.sum_nonneg fun s _ => mul_nonneg (hF s) (hk s s')

/-- A stochastic kernel preserves total mass. -/
theorem marginalStep_total (k : σ → σ → ℚ) (hk1 : ∀ s, ∑ s', k s s' = 1)
    (F : σ → ℚ) : ∑ s', marginalStep k F s' = ∑ s, F s := by
  unfold marginalStep
  rw [Finset.sum_comm]
  simp only [← Finset.mul_sum, hk1, mul_one]

/-- The dropped part of the exact distribution: what the exact filter
carries and the retained one does not. -/
def dropped (k : σ → σ → ℚ) (D : σ → ℚ) (R : ℕ → Finset σ) (t : ℕ) : σ → ℚ :=
  fun s => marginal k D t s - retained k D R t s

theorem retained_nonneg (k : σ → σ → ℚ) (hk : ∀ s s', 0 ≤ k s s')
    (D : σ → ℚ) (hD : ∀ s, 0 ≤ D s) (R : ℕ → Finset σ) (t : ℕ) (s : σ) :
    0 ≤ retained k D R t s := by
  induction t generalizing s with
  | zero => exact hD s
  | succ t ih =>
      show 0 ≤ marginalStep k (fun s => if s ∈ R t then retained k D R t s else 0) s
      refine marginalStep_nonneg k hk _ (fun s => ?_) s
      split_ifs
      · exact ih s
      · exact le_rfl

/-- One step of the dropped part: the previous dropped part moved by the
kernel, plus the mass set aside at this step, moved by the kernel. -/
theorem dropped_succ (k : σ → σ → ℚ) (D : σ → ℚ) (R : ℕ → Finset σ) (t : ℕ) :
    dropped k D R (t + 1)
      = marginalStep k (fun s => dropped k D R t s
          + (if s ∈ R t then 0 else retained k D R t s)) := by
  have hm : marginal k D (t + 1) = marginalStep k (marginal k D t) := rfl
  have hr : retained k D R (t + 1)
      = marginalStep k (fun s => if s ∈ R t then retained k D R t s else 0) := rfl
  have hpt : (fun s => marginal k D t s - (if s ∈ R t then retained k D R t s else 0))
      = fun s => dropped k D R t s + (if s ∈ R t then 0 else retained k D R t s) := by
    funext s
    unfold dropped
    split_ifs <;> ring
  show (fun s' => marginal k D (t + 1) s' - retained k D R (t + 1) s') = _
  rw [hm, hr, ← marginalStep_sub, hpt]

theorem dropped_nonneg (k : σ → σ → ℚ) (hk : ∀ s s', 0 ≤ k s s')
    (D : σ → ℚ) (hD : ∀ s, 0 ≤ D s) (R : ℕ → Finset σ) (t : ℕ) (s : σ) :
    0 ≤ dropped k D R t s := by
  induction t generalizing s with
  | zero =>
      show 0 ≤ D s - D s
      simp
  | succ t ih =>
      rw [dropped_succ]
      refine marginalStep_nonneg k hk _ (fun s => ?_) s
      refine add_nonneg (ih s) ?_
      split_ifs
      · exact le_rfl
      · exact retained_nonneg k hk D hD R t s

/-- The dropped part's total mass is exactly the mass set aside. -/
theorem dropped_total (k : σ → σ → ℚ) (hk1 : ∀ s, ∑ s', k s s' = 1)
    (D : σ → ℚ) (R : ℕ → Finset σ) (t : ℕ) :
    ∑ s, dropped k D R t s = cutMass k D R t := by
  induction t with
  | zero =>
      show ∑ s, (D s - D s) = 0
      simp
  | succ t ih =>
      rw [dropped_succ, marginalStep_total k hk1]
      show ∑ s, (dropped k D R t s + (if s ∈ R t then 0 else retained k D R t s))
        = cutMass k D R t + ∑ s ∈ Finset.univ \ R t, retained k D R t s
      rw [Finset.sum_add_distrib, ih]
      congr 1
      rw [Finset.sum_ite, Finset.sum_const_zero, zero_add]
      congr 1
      ext s
      simp

/-- **The cut bound.**  With a nonnegative stochastic kernel and a
nonnegative initial distribution, the retained filter's hit mass `lo`
and the set-aside mass `CUT` bracket the exact hit mass:
`lo ≤ exact ≤ lo + CUT`. -/
theorem hit_cut_bounds (k : σ → σ → ℚ) (hk : ∀ s s', 0 ≤ k s s')
    (hk1 : ∀ s, ∑ s', k s s' = 1) (D : σ → ℚ) (hD : ∀ s, 0 ≤ D s)
    (R : ℕ → Finset σ) (Q : Finset σ) (h : ℕ) :
    ∑ s ∈ Q, retained k D R h s ≤ hit k Q D h
      ∧ hit k Q D h ≤ ∑ s ∈ Q, retained k D R h s + cutMass k D R h := by
  have hsplit : hit k Q D h
      = ∑ s ∈ Q, retained k D R h s + ∑ s ∈ Q, dropped k D R h s := by
    unfold hit dropped
    rw [← Finset.sum_add_distrib]
    congr 1
    funext s
    ring
  have hnn : 0 ≤ ∑ s ∈ Q, dropped k D R h s :=
    Finset.sum_nonneg fun s _ => dropped_nonneg k hk D hD R h s
  have hle : ∑ s ∈ Q, dropped k D R h s ≤ cutMass k D R h := by
    rw [← dropped_total k hk1 D R h]
    exact Finset.sum_le_sum_of_subset_of_nonneg (Finset.subset_univ Q)
      fun s _ _ => dropped_nonneg k hk D hD R h s
  constructor
  · rw [hsplit]; linarith
  · rw [hsplit]; linarith

/-! ### The sheet: a belief table's side conditions are decidable -/

/-- A belief sheet: the masses of each `one` group, and a level port's
cut points. -/
structure Sheet where
  rows : List (List ℚ)
  cuts : List ℚ

/-- The side conditions the compiler emits per table: every group's
masses are nonnegative and sum to one; the cut points are strictly
increasing and lie in `(0, 1)`. -/
def Sheet.ok (S : Sheet) : Prop :=
  (∀ r ∈ S.rows, r.sum = 1 ∧ ∀ x ∈ r, 0 ≤ x)
    ∧ S.cuts.Pairwise (· < ·)
    ∧ ∀ c ∈ S.cuts, 0 < c ∧ c < 1

instance (S : Sheet) : Decidable S.ok := by
  unfold Sheet.ok
  infer_instance

/-- The fetch example's table: the cup in the drawer, on the shelf, in
the bin, with the risk levels `low / mid / high` cut at `0.1` and
`0.3`.  Closed by normalization. -/
example : Sheet.ok ⟨[[6/10, 3/10, 1/10]], [1/10, 3/10]⟩ := by
  norm_num [Sheet.ok]

/-- A table that does not sum to one is refused by the same tactic. -/
example : ¬ Sheet.ok ⟨[[6/10, 3/10, 2/10]], [1/10, 3/10]⟩ := by
  norm_num [Sheet.ok]

end Metis
