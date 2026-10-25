# PROPOSAL 14 — evaluation: the grounding bound, the proof-net reading, and the passes

**Status: PROPOSED (eval-perf s-5173a0a0 step 3; opus drafts, the architect reviews, the user decides what lands).**
This document does three things:
- it records what eval-perf measured and merged (§3, the done passes);
- it states the bounds our two evaluation stages obey (§1, §2);
- it proposes the remaining passes with their invariants and their measured or predicted gains (§4).

Sources:
- steps/step1-profile.md, step1b-metisc-profile.md, step2-prototype.md, step2-metisc.md, step2b–2g on the subject;
- steps/step3-reading.md, the reading of EFD26;
- nina's MiniHack probe (refs/step4-measure.py): a 4-rule base over a room's cells in three forms, `static` (adj
  as bwd facts), `pred` (adj as a pred) and `roles` (k places).

## 0. In one table

| stage | what bounds it | before eval-perf | after (merged) |
|---|---|---|---|
| ground, static form | the guard join | metispy cells³: 21 s at 200 cells, 29 min at 840 | 37 ms at 200, 0.19 s at 840 (metispy P1+P2); metisc's index on master |
| ground, pred form | the typed product Π\|τ\| (no guard prunes it) | 1.28M events at 200 cells, 4.2 s, 1.35 GB | the same events (the program's), 4.9 s, 1.01 GB (P3+slots) |
| compile, static form | metisc's lexer, cells² (`line_col` per token) | 3.5 s at 840 cells | linear (bf7b570) |
| a turn (REPL) | candidates weighed per turn | 1.2 ms at 200 cells, 6.2 at 840 | 0.10 / 0.36 ms (counting index) |
| a step (C++ Live) | E × \|state\| (`count_of` linear) | 330 ms at pred 200 | 0.045 ms (by-atom tier, dense counts, 43414c4) |
| IR inference | min-fill width W and the sites' cardinalities | W 64 at H = 8 for room programs | unchanged: sampler-only for rooms (§2) |
| IR build | `Elim.elim_cost`, about V³ | 137 s at 2,900 vars | proposed (§4, P10) |

## 1. The grounding bound

**Upper bound, per rule.** Rule r has typed variables x₁…xₙ (types τᵢ), guards g₁…gₘ (bwd premises) and
distinct pairs. Its ground events are the substitutions θ ∈ τ₁ × … × τₙ for which every gⱼθ is Horn-derivable
and every distinct pair differs:

    |ground(r)| = |{θ ∈ Πτᵢ : ∧ⱼ Σ ⊢ gⱼθ, distinct}| ≤ Π |τᵢ|

The bound is reached exactly when no guard prunes, which is the pred form:
- adj is a pred, so move, open_door and fight emit cells² × 8, cells² × 8 and cells² × 8 × 2;
- that is 32 · cells² in all (1,280,200 at 200 cells, 88M at a full 1,659-cell level).

No grounder can do better here: the events are the program's. Only the program can change the count. Roles
bind the cells, so the count is k² × 32, about 9.3k at k = 16 for any level. A static table makes the guard
prune.

**Lower bound, what any grounder must spend.** It must read the facts its guards name and write its output:

    Ω(|facts read| + |ground(r)|)

**Today's grounders against it.**
- **Before P1** (metispy `_substitutions`, metisc `substitutions`), a guard was answered at its LAST variable.
  For adj(C, D, R) declared in that order, that is one Horn call per (C, D) prefix: cells² calls. Each call
  scanned every adj fact (8 · cells), so the cost was cells³ against an output of 8 · cells.
  - Measured exactly: 40,000 × 1,424 = 57M unify calls at 200 cells.
  - Only 3.6% of prefixes have any row.
  - This is join-before-filter, twice: the type product before the guard, and the full fact list before the
    constants.
- **P2** (the by-position fact index) answers a call from the narrowest bucket: cells² calls of O(8), i.e.
  cells² (11.7 s at 840 cells).
- **P1** (guard-first binding) filters every variable's domain by each fact-table guard that names it, as soon
  as the variable is bound. The bound positions come from the index, and the unbound ones are free with their
  repeated occurrences equal. This is a semi-join applied at each variable: a prefix no row can complete is never
  extended.
  - For one acyclic guard per rule, the work is O(|rows| + |output|), the lower bound.
  - Measured: 8 · cells candidates per rule, 0.19 s at 840 cells, 0 Horn variants.

**Where the output-linear bound does not hold:**
1. **Guards that are rules, not fact tables** (recursive Horn, arithmetic tables written as rules). They keep
   the tabled SLD path and are answered at their last variable: answered early, an existential query (e.g.
   `plus(X, ?, ?)`) can cost more than the late ground calls. Their cost is the SLD's, bounded by the variant
   table.
2. **Cyclic guard bodies.** For example a triangle `$e(X,Y) * $e(Y,Z) * $e(Z,X)`. P1's per-variable semi-join
   is not worst-case optimal there. The bound is AGM: |out| ≤ Π |Rⱼ|^{wⱼ} over a fractional edge cover w, reached
   by a worst-case-optimal join (leapfrog triejoin, generic join).
   - One rule has a cyclic guard body today: the road grid's `hit` (metis-catalog domains/road/grid_domain.llp,
     included by road_grid.llp), a pair/window triangle over A, B, X, in the parked road catalog. The 1,293
     rules of the programs that compile (a GYO reduction of every schema's and link's guard hypergraph over
     metis-catalog, metis-worlds and metis-lang/corpus; 180 with two or more guards) are acyclic. The scan that
     first said 0 skipped the programs metispy fails to compile; the road grid files fail on spec 12's
     type-unknown. The reduction does flag a triangle.
   - Proposed as a check, not a pass: the compiler reports a rule whose guard hypergraph is cyclic (a
     diagnostic, spec 08), so the cost is never a surprise.
3. **Variable order.** P1 filters in declaration order. A rule whose first-declared variable is unguarded and
   wide, with a selective guard on later variables, still enumerates the first variable's domain in full.
   - With P1 this is O(|τ₁| × the filtered rest), not a product.
   - A static variable ordering (the most selective guard's variables first) would remove it, but it changes the
     enumeration order, and so the event order. Under [E] it needs a re-sort of the output into type-product
     order, O(out log out). Not needed by any measured program; noted.

**Events and the measure.** Grounding cost is not inference cost. The event count bounds:
- the load and RSS of every runtime: about 1 µs and 370–440 B per event in C++;
- the per-event bytes in metispy: 717 B after P3 + slots;
- the size of each CHOICE site's table in the IR.

The inference cost is §2's.

## 2. The proof-net reading (EFD26, arXiv:2602.04045), and what it bounds

Condensed from steps/step3-reading.md. Numbers follow the PDF (Defs 3.1–3.2, Lemma 3.1, Thms 5.2, 8.1–8.3), as
bpn.py and paper/metis.tex cite them.

**Their object.**
- A Bayesian network is an MLL^B proof-net: a CPT is a box ⊢ Y⁻…, X⁺; contraction is fan-out; weakening is an
  unread variable.
- A cut is a factor product followed by the sum-out of the interface (Thm 5.2).
- The speed-up is **cut expansion, not elimination.** Splitting a net into a cut-net (Def 8.1) and interpreting
  it bottom-up (Thm 8.1) costs O(n · 2^Width) (Thm 8.2). The order of splittings is a variable-elimination order
  (App. D).
- **Box/weakening pruning** (§6, Lemma 6.2) restricts the net to the ancestors of the query.

**Our two stages.**
- **Grounding (§1) is Π-instantiation, before any net exists.** A guard premise is a cut against a Horn
  derivation, eliminated at compile time; its cost is a join. EFD does not cover this stage. Both probe curves
  are here.
- **Emission and inference** (factorize → bpn_check → factored / jtree) are EFD's object:
  - sites and SSA writes are boxes, and occurrence edges are cuts;
  - our min-fill elimination and junction tree are their cut-net interpretation;
  - `certificate()`'s induced width is their Width.

  metis.tex's Proposition "the emitted nets are Bayesian proof-nets" is pinned by bpn_check.

**The IR bound we measured (step 2d).**
- Exact inference over the emitted IR costs Π card over each (W+1)-clique, where card is a CHOICE site's
  cardinality: one value per enabled event, 246 to 3,334 on the probe.
- At H = 8, every room-shaped program (static and pred, 200 to 840 cells) emits the same IR (291 vars, W 64),
  because the agent reaches the same cells in 8 steps.
- Role programs give W 8 at H = 8, and W 10 / 18 / 34 at H = 100 for k = 8 / 16 / 32.
- So exact IR inference is for small role programs (W ≲ 10, small cards). Room-shaped programs are sampler-only
  on any device, and no pass below changes that. Only the program does (roles, or a smaller horizon).

## 3. The passes done (merged), with their invariants and measured gains

The invariants:
- **[E] same event set:** the same ground events in the same order with the same names, so the ordered digest
  and `program_key` equal main's;
- **[T] same tier:** the same enabled set, in the same order, with the same weights per step, so the same draws;
- **[S] same semantics:** the same measure, with event indices that may change.

| pass | where | invariant | measured gain | status |
|---|---|---|---|---|
| P2 by-position fact index | metispy horn.py (e41d7cc); metisc horn.ml (27d2987) | [E] | static 840: 29 min → 11.7 s alone | merged both |
| P1 guard-first binding | metispy ground.py (76ebc9d); metisc on eval-perf-2h-p1 | [E] | static 200 / 450 / 840: 21.97 s / 248 s / 1,736 s → 37 / 94 / 194 ms; Horn variants 0; retained B/event flat (871–942, was 6.2–14.7 KB) | metispy merged; metisc in progress |
| memo released with the generator (the `walk` closure cycle broken) | metispy ground.py (e41d7cc) | [E] | the cells²-growing retained bytes per event become flat | merged |
| P3 atom table (one str per distinct ground atom) + slots | metispy schema.py, ground.py, clause.py (f523fcd) | [E] | 1,057 → 717 B/event (−32%); pred 200 peak 1.35 → 1.01 GB, at +10% grounding time | merged |
| P6 complement guards → distinct | — | [E] | falls out of P1: the role complements are fact tables the index answers | no separate pass |
| REPL counting candidate index | metispy repl.py (119797a) | [T] (seeded corpus runs: 57 programs, 4,180 steps, identical fired) | turn: static 200 1.20 → 0.10 ms, 840 6.25 → 0.36; pred 200 6.7 → 1.1; roles unchanged | merged |
| C++ Live by-atom tier + dense counts | runtime kernel.hpp, live.hpp (43414c4) | [T] (50/50 traces byte-equal) | step: pred 200 325 → 0.045 ms, static 840 6.19 → 0.012, roles k32 0.94 → 0.004 | merged |
| lexer positions in one pass; add_horn, check_consts | metisc lexer.ml, compile.ml (bf7b570, 51bc292, 879e3af) | [E] plus token and catalog digests (46 files) | static 840 compile 3.5 s → linear | merged |
| tail-recursive event lists; wire artifact_lines | metisc ground.ml (077ae75), wire.ml (28d1c38) | [E]; product wires 5/5 | the pred 200 wire writes (it overflowed the stack at ~1M events); ground no longer O(E²) | merged |

**Measured once across toolchains, at pred 200.** metisc 1.8 s and 900 MB; metispy 4.9 s and 1.01 GB (it was
4.3 s and 1.35 GB).

## 4. The passes proposed

| # | pass | stage | rewrite | invariant | predicted or measured gain | decision asked |
|---|---|---|---|---|---|---|
| P4c | **columnar ground program** | metispy representation (and the runtimes' load) | Three int32 arrays per multiset field (atom ids, counts, offsets), an atom table, names regenerated from (rule id, value ids). The REPL, filter and nets read arrays | [E] of content; the object API changes for every reader | measured from the ground program: **~86 B/event (12×; 717 today)**: arrays 50, atom table 20, name ids 16. pred 200 → ~110 MB | a runtime rewrite: go only if a world keeps 10⁶-event programs in Python |
| P4t | tuple multisets (immutable flat tuples behind the mapping protocol) | metispy representation | as named | [E] measured (roles); **breaks 25 tests** (in-place mutation, a pair-unpacking reader in the cone and intervention verbs) | 361 B/event (3×), reads 1.7–2× slower | **no** (ruled; recorded) |
| P5 | dead-event pruning from init | after grounding | Drop an event that needs an atom neither in init nor produced by any event (the producible fixpoint). EFD §6's pruning applied on the generative side | [S] from that init only; the content key changes. Sound for a live session only with spec 13's re-grounding on assert | pred 200 with the room's adj in init: 1.28M → ~5.9k events (≈ 200×), 1.35 GB → ~6 MB | **no-go** while spec 13 is no-go (its trigger 3 met only by cell-level forms, which roles avoid) |
| P10 | **incremental min-fill** in metisc `Elim` | IR build | Keep each variable's fill in a priority queue. On eliminating v, update only v's neighbours and their neighbours, not every remaining variable | the same elimination order (ties broken as today) | `elim_cost` about V³ → about V · d² log V (d the elimination degree): 137 s at 2,900 vars → ~seconds; the H = 100 room IRs stop hitting the cap at emit, not elim | go for metisc (compile-host cost only; order equality is checkable by digest of the O/Y orders) |
| P11 | cyclic-guard diagnostic | compile | Report a rule whose guard hypergraph is cyclic (§1.2): its grounding is AGM-bounded, not output-linear | none (a listing) | — (1 in the corpus: the road grid's `hit`) | go as a spec 08 code |
| P8 | IR peephole: fuse a deterministic write box into its single reader; drop guard boxes whose indicator is 1 on every reachable row; prune by the query cone (EFD §6, our spec 11 cone) | emission | as named | [S]: same marginals | constant factors on box count. **Width unchanged** (Thm 8.2's cost is in the width, which min-fill already chooses) | note only |
| P9 | ⊗/⅋ cut merging (EFD Thm 8.3) | IR typing | group several occurrence edges between two clusters into one joint variable | [S] | none: the same names, the same width (a sequentialization result) | note only |
| P12 | rarest-atom tier in the sampled path | runtime | metispy's `ForwardProjection` and filter weigh candidates as the REPL now does | [T] | the REPL's gains, for exact filtering at many states | go if a filter-heavy world appears (none measured) |

**Not proposed.**
- **P7** (shared sub-condition factoring across rules): the Horn variant table already shares; 40,001 completes
  served 120,200 guard calls.
- **Lazy names:** a lazy (rule, values) tuple costs what the 66–70 B string does, and every policy, log and card
  reads names.

## 5. What the user decides
1. P10 (incremental min-fill in metisc): recommended, compile-host only.
2. P11 (a cyclic-guard diagnostic): recommended, a listing.
3. P4c (the columnar program): not now. It is the representation to adopt if a world keeps cell-level programs
   in Python, which roles avoid.
4. P5: stays tied to spec 13's no-go.
5. P8, P9, P12: notes; no measured program needs them.
