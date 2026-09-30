/-
The descent skeleton of Theorem 4 (trace invariance on the
factorizable class F), paper §6.

Abstract setting: events act deterministically on states (`upd`), each
event contributes a local weight factor (`f`, valued in a commutative
monoid), and an independence relation satisfies the two conclusions of
the paper's footprint-stability lemma — independent events commute as
state transformers, and an event's factor is unchanged by first
executing an independent event.  We prove the run weight (the product
of local factors along the run) and the final state are invariant
under adjacent transposition of independent events, hence constant on
Mazurkiewicz trace classes: the measure descends to occurrence nets.

The concrete instantiation — that the factored emission's sites and
declared `reads` scopes satisfy the two hypotheses — is the
footprint-stability argument of Theorem 4 and remains on paper, pinned
operationally by the emission's rejection gates.
-/

import Mathlib

namespace Metis

variable {E St M : Type*} [CommMonoid M]

variable (upd : E → St → St) (f : E → St → M) (indep : E → E → Prop)

/-- Independence-compatibility: the conclusions of the paper's
footprint-stability lemma, taken as hypotheses of the abstract
skeleton.  `symm` reflects that footprint disjointness is symmetric;
`comm` that independent events commute as state transformers; `stable`
that an event's local factor cannot see an independent event's
effect. -/
structure Compat : Prop where
  symm : ∀ e e', indep e e' → indep e' e
  comm : ∀ e e', indep e e' → ∀ s, upd e' (upd e s) = upd e (upd e' s)
  stable : ∀ e e', indep e e' → ∀ s, f e (upd e' s) = f e s

/-- The run weight: the product of the local factors along the run,
each evaluated in the state it fires from. -/
def weight : List E → St → M
  | [], _ => 1
  | e :: es, s => f e s * weight es (upd e s)

/-- The final state of a run. -/
def exec : List E → St → St
  | [], s => s
  | e :: es, s => exec es (upd e s)

/-- One Mazurkiewicz rewrite: transpose two adjacent independent
events. -/
inductive Swap : List E → List E → Prop
  | swap (u v : List E) (e e' : E) (h : indep e e') :
      Swap (u ++ e :: e' :: v) (u ++ e' :: e :: v)

/-- Mazurkiewicz trace equivalence: the equivalence closure of
adjacent transposition of independent events. -/
def TraceEquiv : List E → List E → Prop :=
  Relation.EqvGen (Swap indep)

theorem weight_append (u v : List E) (s : St) :
    weight upd f (u ++ v) s = weight upd f u s * weight upd f v (exec upd u s) := by
  induction u generalizing s with
  | nil => simp [weight, exec]
  | cons e es ih => simp [weight, exec, ih, mul_assoc]

theorem exec_append (u v : List E) (s : St) :
    exec upd (u ++ v) s = exec upd v (exec upd u s) := by
  induction u generalizing s with
  | nil => rfl
  | cons e es ih => simp [exec, ih]

variable {upd f indep}

/-- Transposing two adjacent independent events changes neither the
final state nor the run weight. -/
theorem weight_exec_swap (hc : Compat upd f indep) {r r' : List E}
    (h : Swap indep r r') (s : St) :
    weight upd f r s = weight upd f r' s ∧ exec upd r s = exec upd r' s := by
  obtain ⟨u, v, e, e', hee⟩ := h
  have he' : indep e' e := hc.symm _ _ hee
  set t := exec upd u s with ht
  have hstate : upd e' (upd e t) = upd e (upd e' t) := hc.comm _ _ hee t
  constructor
  · rw [weight_append, weight_append]
    congr 1
    show weight upd f (e :: e' :: v) t = weight upd f (e' :: e :: v) t
    simp only [weight]
    rw [hc.stable e' e he' t, hc.stable e e' hee t, hstate]
    exact mul_left_comm _ _ _
  · rw [exec_append, exec_append]
    show exec upd (e :: e' :: v) t = exec upd (e' :: e :: v) t
    simp only [exec]
    rw [hstate]

/-- **Theorem 4, descent skeleton.**  Run weights that factor through
schedule-stable local factors are constant on Mazurkiewicz trace
classes: the measure descends to the trace quotient (runs weigh their
occurrence nets, not their interleavings). -/
theorem traceEquiv_weight_eq (hc : Compat upd f indep) {r r' : List E}
    (h : TraceEquiv indep r r') (s : St) :
    weight upd f r s = weight upd f r' s := by
  induction h with
  | rel _ _ hs => exact (weight_exec_swap hc hs s).1
  | refl _ => rfl
  | symm _ _ _ ih => exact ih.symm
  | trans _ _ _ _ _ ih₁ ih₂ => exact ih₁.trans ih₂

/-- The final state is likewise a trace invariant. -/
theorem traceEquiv_exec_eq (hc : Compat upd f indep) {r r' : List E}
    (h : TraceEquiv indep r r') (s : St) :
    exec upd r s = exec upd r' s := by
  induction h with
  | rel _ _ hs => exact (weight_exec_swap hc hs s).2
  | refl _ => rfl
  | symm _ _ _ ih => exact ih.symm
  | trans _ _ _ _ _ ih₁ ih₂ => exact ih₁.trans ih₂

end Metis
