/-
Theorem 3 (equivalence onto the image), paper §5 — in full.

Ground staged programs are name-carrying lists of clauses and links
over ambient types of atoms `A`, stages `S`, weights `W` and names
`N`; the image class (stage-gated mass-action SPNs) carries the same
content as multisets; the denotation forgets names and list order;
structural congruence is a renaming injective on the program's names
together with permutations of the clause and link lists.

We prove the denotation is
  (i)   total, functional, and constant on congruence classes
        (`denote_congr`),
  (ii)  surjective, via an explicit fresh-naming section
        (`denote_readBack`, `wellFormed_readBack`,
        `denote_surjective`),
  (iii) injective up to congruence on well-formed programs
        (`congr_of_denote_eq`),
and hence a bijection between programs-mod-congruence and the class
(`denote_eq_iff_congr`).

The two boundary remarks of the paper are visible in the statement:
the SPN retains the declared stage list (empty stages included), and
its transition components are multisets, not sets — under either
alternative, (iii) is false.
-/

import Mathlib

namespace Metis

/-- Content of a ground clause: stage, consume/read/produce multisets,
prior weight.  Names are *not* part of the content. -/
structure ClauseData (A S W : Type*) where
  stage : S
  consume : Multiset A
  reads : Multiset A
  produce : Multiset A
  weight : W
  deriving DecidableEq

/-- Content of a ground link (a stage gate): source and target stage,
consume/read/produce multisets, prior weight. -/
structure LinkData (A S W : Type*) where
  src : S
  tgt : S
  consume : Multiset A
  reads : Multiset A
  produce : Multiset A
  weight : W
  deriving DecidableEq

/-- A ground staged program: the declared stage list (order is
semantics; empty stages are retained), *named* clause and link lists,
and the initial data. -/
structure Program (N A S W : Type*) where
  stages : List S
  clauses : List (N × ClauseData A S W)
  links : List (N × LinkData A S W)
  initStage : S
  init : Multiset A

/-- A stage-gated mass-action SPN: the image class.  Transitions and
gates are *multisets* of content records (duplicate transitions count
separately in the firing rule); the stage list is retained in declared
order (empty stages included). -/
@[ext]
structure Spn (A S W : Type*) where
  stages : List S
  trans : Multiset (ClauseData A S W)
  gates : Multiset (LinkData A S W)
  initStage : S
  init : Multiset A

variable {N A S W : Type*}

/-- The names a program uses, clauses then links. -/
def Program.names (P : Program N A S W) : List N :=
  P.clauses.map Prod.fst ++ P.links.map Prod.fst

/-- Well-formedness: all clause and link names are distinct. -/
def Program.WellFormed (P : Program N A S W) : Prop := P.names.Nodup

/-- The denotation: forget names and list order, keep everything
else.  Total and functional by construction. -/
def denote (P : Program N A S W) : Spn A S W where
  stages := P.stages
  trans := (P.clauses.map Prod.snd : List _)
  gates := (P.links.map Prod.snd : List _)
  initStage := P.initStage
  init := P.init

/-- Structural congruence: `P'` is obtained from `P` by a renaming of
clause/link names injective on the names `P` uses, together with
reorderings of the clause and link lists.  Atoms, stage labels, stage
order, weights and initial data are fixed pointwise. -/
def Congr (P P' : Program N A S W) : Prop :=
  ∃ π : N → N,
    Set.InjOn π {n | n ∈ P.names} ∧
    P'.stages = P.stages ∧ P'.initStage = P.initStage ∧ P'.init = P.init ∧
    (P.clauses.map fun q => (π q.1, q.2)).Perm P'.clauses ∧
    (P.links.map fun q => (π q.1, q.2)).Perm P'.links

/-! ### (i) Invariance: the denotation is constant on congruence
classes -/

theorem denote_congr {P P' : Program N A S W} (h : Congr P P') :
    denote P = denote P' := by
  obtain ⟨π, -, hst, hs0, hm0, hc, hl⟩ := h
  have hcs : (P.clauses.map Prod.snd).Perm (P'.clauses.map Prod.snd) := by
    simpa [List.map_map, Function.comp_def] using hc.map Prod.snd
  have hls : (P.links.map Prod.snd).Perm (P'.links.map Prod.snd) := by
    simpa [List.map_map, Function.comp_def] using hl.map Prod.snd
  ext1
  · exact hst.symm
  · exact Multiset.coe_eq_coe.mpr hcs
  · exact Multiset.coe_eq_coe.mpr hls
  · exact hs0.symm
  · exact hm0.symm

/-! ### The matching lemma

The workhorse of injectivity-up-to-congruence: two lists of named
records with distinct names and equal content multisets are related by
a renaming injective on the first list's names.  This is the paper's
duplicate-content matching argument, done once, generically, and
applied to clauses and links separately. -/

theorem exists_rename_of_perm_snd {α : Type*} [DecidableEq N] [DecidableEq α]
    {l₁ l₂ : List (N × α)}
    (h₁ : (l₁.map Prod.fst).Nodup) (h₂ : (l₂.map Prod.fst).Nodup)
    (h : (l₁.map Prod.snd).Perm (l₂.map Prod.snd)) :
    ∃ π : N → N,
      Set.InjOn π {n | n ∈ l₁.map Prod.fst} ∧
      (∀ n ∈ l₁.map Prod.fst, π n ∈ l₂.map Prod.fst) ∧
      (l₁.map fun q => (π q.1, q.2)).Perm l₂ := by
  induction l₁ generalizing l₂ with
  | nil =>
    have h2 : l₂.map Prod.snd = [] := h.symm.eq_nil
    have : l₂ = [] := List.map_eq_nil_iff.mp h2
    subst this
    exact ⟨id, by simp [Set.InjOn], by simp, by simp⟩
  | cons q t ih =>
    -- match the head content to some pair of l₂
    have hmem : q.2 ∈ l₂.map Prod.snd := h.subset (by simp)
    obtain ⟨p, hp, hpq⟩ := List.mem_map.mp hmem
    have hperm₂ : l₂.Perm (p :: l₂.erase p) := List.perm_cons_erase hp
    -- the tails have permuted contents
    have htail : (t.map Prod.snd).Perm ((l₂.erase p).map Prod.snd) := by
      have hh : (q.2 :: t.map Prod.snd).Perm
          (q.2 :: (l₂.erase p).map Prod.snd) := by
        have := h.trans (hperm₂.map Prod.snd)
        simpa [hpq] using this
      exact hh.cons_inv
    -- name bookkeeping
    rw [List.map_cons, List.nodup_cons] at h₁
    obtain ⟨hqnot, h₁t⟩ := h₁
    have hfstperm : (l₂.map Prod.fst).Perm
        (p.1 :: (l₂.erase p).map Prod.fst) := by
      simpa using hperm₂.map Prod.fst
    obtain ⟨hpnot, h₂e⟩ := List.nodup_cons.mp (hfstperm.nodup_iff.mp h₂)
    -- induction
    obtain ⟨π', hinj, hrange, hperm⟩ := ih h₁t h₂e htail
    have hupd : ∀ z ∈ t.map Prod.fst, Function.update π' q.1 p.1 z = π' z := by
      intro z hz
      have : z ≠ q.1 := fun hcon => hqnot (hcon ▸ hz)
      exact Function.update_of_ne this _ _
    refine ⟨Function.update π' q.1 p.1, ?_, ?_, ?_⟩
    · -- injective on q.1 :: names of t
      intro x hx y hy hxy
      simp only [Set.mem_setOf_eq, List.map_cons, List.mem_cons] at hx hy
      rcases hx with hx | hx <;> rcases hy with hy | hy
      · exact hx.trans hy.symm
      · exfalso
        rw [hx, Function.update_self, hupd y hy] at hxy
        apply hpnot
        rw [hxy]
        exact hrange y hy
      · exfalso
        rw [hy, Function.update_self, hupd x hx] at hxy
        apply hpnot
        rw [← hxy]
        exact hrange x hx
      · rw [hupd x hx, hupd y hy] at hxy
        exact hinj hx hy hxy
    · -- names land in l₂'s names
      intro n hn
      simp only [List.map_cons, List.mem_cons] at hn
      rcases hn with hn | hn
      · rw [hn, Function.update_self]
        exact List.mem_map_of_mem (f := Prod.fst) hp
      · rw [hupd n hn]
        have hsub : ((l₂.erase p).map Prod.fst) ⊆ l₂.map Prod.fst :=
          (List.erase_sublist.map Prod.fst).subset
        exact hsub (hrange n hn)
    · -- the renamed list is a permutation of l₂
      have hmap : (t.map fun r => (Function.update π' q.1 p.1 r.1, r.2))
          = t.map fun r => (π' r.1, r.2) := by
        refine List.map_congr_left fun r hr => ?_
        rw [hupd r.1 (List.mem_map_of_mem (f := Prod.fst) hr)]
      have hhead : (Function.update π' q.1 p.1 q.1, q.2) = p := by
        rw [Function.update_self, ← hpq]
      have hlist : ((q :: t).map fun r => (Function.update π' q.1 p.1 r.1, r.2))
          = p :: (t.map fun r => (π' r.1, r.2)) := by
        rw [List.map_cons, hmap, hhead]
      rw [hlist]
      exact (hperm.cons p).trans hperm₂.symm

/-! ### (iii) Injectivity up to congruence -/

/-- Merge two renamings along a name list: the paper's assembly of the
per-stage clause matching and the link matching into one global
renaming. -/
def mergeRename [DecidableEq N] (cnames : List N) (πc πl : N → N) (n : N) : N :=
  if n ∈ cnames then πc n else πl n

theorem congr_of_denote_eq
    [DecidableEq N] [DecidableEq A] [DecidableEq S] [DecidableEq W]
    {P P' : Program N A S W}
    (hP : P.WellFormed) (hP' : P'.WellFormed)
    (h : denote P = denote P') : Congr P P' := by
  -- unpack the component equalities
  have hst : P.stages = P'.stages := congrArg Spn.stages h
  have hs0 : P.initStage = P'.initStage := congrArg Spn.initStage h
  have hm0 : P.init = P'.init := congrArg Spn.init h
  have hcs : (P.clauses.map Prod.snd).Perm (P'.clauses.map Prod.snd) :=
    Multiset.coe_eq_coe.mp (congrArg Spn.trans h)
  have hls : (P.links.map Prod.snd).Perm (P'.links.map Prod.snd) :=
    Multiset.coe_eq_coe.mp (congrArg Spn.gates h)
  -- unpack well-formedness
  obtain ⟨hc₁, hl₁, hdisj₁⟩ := List.nodup_append'.mp hP
  obtain ⟨hc₂, hl₂, hdisj₂⟩ := List.nodup_append'.mp hP'
  -- match clauses and links separately
  obtain ⟨πc, hcinj, hcrange, hcperm⟩ := exists_rename_of_perm_snd hc₁ hc₂ hcs
  obtain ⟨πl, hlinj, hlrange, hlperm⟩ := exists_rename_of_perm_snd hl₁ hl₂ hls
  -- merge into one renaming
  refine ⟨mergeRename (P.clauses.map Prod.fst) πc πl,
    ?_, hst.symm, hs0.symm, hm0.symm, ?_, ?_⟩
  · -- injective on P.names
    intro x hx y hy hxy
    simp only [Set.mem_setOf_eq, Program.names, List.mem_append] at hx hy
    simp only [mergeRename] at hxy
    rcases hx with hx | hx <;> rcases hy with hy | hy
    · rw [if_pos hx, if_pos hy] at hxy
      exact hcinj hx hy hxy
    · exfalso
      have hy' : y ∉ P.clauses.map Prod.fst := fun hcon => hdisj₁ hcon hy
      rw [if_pos hx, if_neg hy'] at hxy
      have : πl y ∈ P'.clauses.map Prod.fst := by
        rw [← hxy]; exact hcrange x hx
      exact hdisj₂ this (hlrange y hy)
    · exfalso
      have hx' : x ∉ P.clauses.map Prod.fst := fun hcon => hdisj₁ hcon hx
      rw [if_neg hx', if_pos hy] at hxy
      have : πl x ∈ P'.clauses.map Prod.fst := by
        rw [hxy]; exact hcrange y hy
      exact hdisj₂ this (hlrange x hx)
    · have hx' : x ∉ P.clauses.map Prod.fst := fun hcon => hdisj₁ hcon hx
      have hy' : y ∉ P.clauses.map Prod.fst := fun hcon => hdisj₁ hcon hy
      rw [if_neg hx', if_neg hy'] at hxy
      exact hlinj hx hy hxy
  · -- clauses: the merged renaming agrees with πc there
    have hmapc : (P.clauses.map fun q =>
        (mergeRename (P.clauses.map Prod.fst) πc πl q.1, q.2))
        = P.clauses.map fun q => (πc q.1, q.2) := by
      refine List.map_congr_left fun q hq => ?_
      simp only [mergeRename]
      rw [if_pos (List.mem_map_of_mem (f := Prod.fst) hq)]
    rw [hmapc]
    exact hcperm
  · -- links: link names are never clause names (well-formedness)
    have hmapl : (P.links.map fun q =>
        (mergeRename (P.clauses.map Prod.fst) πc πl q.1, q.2))
        = P.links.map fun q => (πl q.1, q.2) := by
      refine List.map_congr_left fun q hq => ?_
      simp only [mergeRename]
      rw [if_neg fun hcon =>
        hdisj₁ hcon (List.mem_map_of_mem (f := Prod.fst) hq)]
    rw [hmapl]
    exact hlperm

/-! ### (ii) Surjectivity: an explicit fresh-naming section -/

/-- Attach consecutive natural-number names starting at `k`. -/
def withNames (k : ℕ) : List α → List (ℕ × α)
  | [] => []
  | a :: t => (k, a) :: withNames (k + 1) t

@[simp] theorem map_snd_withNames (k : ℕ) (l : List α) :
    ((withNames k l).map Prod.snd) = l := by
  induction l generalizing k with
  | nil => rfl
  | cons a t ih => simp [withNames, ih]

@[simp] theorem map_fst_withNames (k : ℕ) (l : List α) :
    ((withNames k l).map Prod.fst) = List.range' k l.length := by
  induction l generalizing k with
  | nil => rfl
  | cons a t ih => simp [withNames, ih, List.range'_succ]

/-- The reading-back `U(N)` of the paper: enumerate the transition and
gate multisets, name clauses `0..k-1` and links `k..k+l-1`. -/
noncomputable def readBack (Q : Spn A S W) : Program ℕ A S W where
  stages := Q.stages
  clauses := withNames 0 Q.trans.toList
  links := withNames Q.trans.toList.length Q.gates.toList
  initStage := Q.initStage
  init := Q.init

/-- Surjectivity on the nose: `⟦U(N)⟧ = N`. -/
theorem denote_readBack (Q : Spn A S W) : denote (readBack Q) = Q := by
  simp only [denote, readBack]
  ext1 <;> simp

/-- The reading-back is well-formed: all its names are distinct. -/
theorem wellFormed_readBack (Q : Spn A S W) : (readBack Q).WellFormed := by
  simp only [Program.WellFormed, Program.names, readBack, map_fst_withNames]
  rw [List.nodup_append']
  refine ⟨List.nodup_range' 1 Nat.one_pos, List.nodup_range' 1 Nat.one_pos, ?_⟩
  intro n hn hn'
  rw [List.mem_range'_1] at hn hn'
  omega

/-- The denotation is surjective (onto the class, with names in ℕ). -/
theorem denote_surjective :
    Function.Surjective (denote : Program ℕ A S W → Spn A S W) :=
  fun Q => ⟨readBack Q, denote_readBack Q⟩

/-! ### The theorem -/

/-- **Theorem 3 (equivalence onto the image).**  On well-formed
programs, denotational equality is exactly structural congruence;
with `denote_surjective`, the denotation descends to a bijection
between programs-mod-congruence and the stage-gated mass-action SPN
class. -/
theorem denote_eq_iff_congr
    [DecidableEq N] [DecidableEq A] [DecidableEq S] [DecidableEq W]
    {P P' : Program N A S W}
    (hP : P.WellFormed) (hP' : P'.WellFormed) :
    denote P = denote P' ↔ Congr P P' :=
  ⟨congr_of_denote_eq hP hP', denote_congr⟩

end Metis
