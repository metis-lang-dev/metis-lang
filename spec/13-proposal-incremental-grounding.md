# PROPOSAL 13 — incremental grounding: ground the delta

**Status: DESIGN DOCUMENT, no code (incremental-grounding s-1bb733de, opus, 2026-10-25). It is (B) of the
semantic-map ruling, scoped by the architect to its one enabler. The decision it asks for is a go/no-go on
the kernel work, and that decision is the user's (§9).**

## The grounder today (survey, metispy master, file:line)

- **`Catalog.ground` (`kernel/catalog.py:233-244`)** typechecks, refuses an incomplete catalog (spec 12), and
  grounds EVERY schema and link every time.
  - The enumeration `_substitutions` (`kernel/ground.py:35-92`) walks each variable over its type's constants in
    declaration order, depth first.
  - Each guard is attached at its last bound variable and answered as a SET: one memoized Horn query per (guard,
    bound args) filters the domain, with a per-constant `derivable` fallback for quantified facts.
  - The `<>` pairs are checked as soon as both sides are bound.
  - It is equal to filtering the full product, in the same order (`tests/test_ground_prune.py`). OCaml's
    `ground.ml` filters the product.
- **Horn is top-down SLD with variant tabling (`kernel/horn.py`)**: answers per call variant, no proofs, a
  per-catalog cache. A catalog is immutable after construction (`catalog.py:218`).
- **Event identity.**
  - An event is named `schema[X=c,…]` (`ground.py:95-110`).
  - It has two positional indexings: `Program.events()` (declared order) and `canonical_events` (sorted by
    content, `kernel/refsample.py:40-51`). An insertion shifts both.
  - The canonical key (`kernel/nets.py:98-121`) hashes sorted clause lines and init, with no names.
- **What already exists toward deltas:**
  - the REPL's atom → candidates index (`lang/repl.py:860-886`), rebuilt when the table changes;
  - the cone and `live_events` (spec 11), both post-ground;
  - pack admission (`catalog.py:155-214`): new constants for abstract types only, through a new catalog and a
    full re-ground.
- **Nothing changes a type or a `bwd` fact on a live session.** `assert`/`retract` are resource counts.

## Motivation

Today a program's ground form is a pure function of its catalog: types, Horn facts and rules, schemas.
- Every change goes through a full `ground()`: a pack admitted (spec 12), a reload, the loop's accept.
- A catalog is immutable after construction (metispy `kernel/catalog.py:218`: "packs and revisions build NEW
  catalogs"), and the Horn table is cached per catalog object.
- Nothing on a live session changes a type's constants or a `bwd` fact. `assert` and `retract` change resource
  counts only (`lang/repl.py:1036-1070`).

The semantic map (s-d4270bed) met this wall twice:
1. **A room as types.** The room's constants as closed types grounded grasp/place to 159k events (0.7 s to
   ground, 1.25 s to open, 261 MB). Every new or vanished thing meant all of it again. The ruling (C) avoided
   this with **roles**: a small fixed vocabulary that the host binds to the map.
2. **Static tables as dynamics.** Under (C) a place's location and openness must change on a live session. Since
   a `bwd` table cannot change, step 2 turned `recat`, `openable` and `notopenable` into `pred`s that the
   projection asserts. The price is the guards: grasp at k = 16 grounds 12,996 events instead of the 610 it
   grounds with static tables (places³ instead of places²).

Incremental grounding is the one mechanism behind both: when a constant joins a type, or a `bwd` fact is added
or removed, re-ground only what it touches. "Open types" and "dynamic Horn tables" are what it would make
possible. This document says how it would work, what it would cost, what the existing code already has toward
it, and whether to build it now.

## 1. The index: what each fact and constant admitted

A ground event is a schema S under a substitution σ that passed S's guards (`kernel/ground.py:35-92`).
Grounding keeps no record of why; incremental grounding needs two indexes, built in the same walk:

- **By constant:** `C[c] = { e : c ∈ range(σ_e) }`. This costs one append per (event, distinct constant): at
  most |vars(S)| per event.
- **By support:** `F[f] = { e : f is in the support of one of e's guards }`. The support of a guard answer is the
  set of Horn facts its proof used.
  - **For a guard over a fact table**, the answer is the matching fact itself, so the support is one fact.
  - **For a guard over Horn rules**, the support is the facts the proof used. The tabled SLD in `kernel/horn.py`
    keeps answers per call variant (`_table`, l.121-139) but not their proofs. Supports need either:
    - the table to record, for each answer, the facts it used (one proof, the first found: enough for deletion
      with re-derivation, §2.4); or
    - a dependency graph between tabled calls (answer → the calls it consumed), which is the standard
      incremental-tabling structure.

  The first is enough and is cheaper.
- **Memo invalidation.** `_substitutions` memoizes one Horn query per (guard, bound args) (l.20-32). The memo
  is keyed by the query, so a changed fact invalidates exactly the memo entries for queries whose predicate is
  the fact's or depends on it. The dependency is the static predicate graph of the Horn rules, known at compile
  time.

The cost is one entry per (event, constant) and one per (event, supporting fact): O(|events| · (|vars| +
|guards|)). That is the same order as the events table itself. For the full room it is 159k events × ≤ 6. The
index is built only when the session asks for deltas (a mode flag), never for a one-shot `metisc --run`.

## 2. The delta algorithm

`D_t` is type t's constants, and ⊕ is the set of new constants. Every case below must produce the same events as
a full re-ground of the changed catalog. §5's invariant tests exactly that.

### 2.1 Add a constant c to type t
The new substitutions of a schema S are those where at least one t-typed variable is c. They split into disjoint
parts, one per t-typed variable position i, in S's variable order v_1..v_n:

    Δ_i(S) = { σ : σ(v_i) = c ;  σ(v_j) ∈ D_t (old) for t-typed j < i ;  σ(v_j) ∈ D_t ∪ {c} for j > i }

This is the semi-naive split, so every new substitution appears exactly once. Each Δ_i is walked by the
existing `_substitutions` with v_i's domain fixed to {c}. The guards and the `<>` pairs are answered as they
bind, unchanged.

- **The cost** is Σ_S Σ_{i : type(v_i) = t} |Δ_i(S)|. That is the share of S's grounding that names c: for a
  schema whose size is spread evenly over t, about (#t-vars of S) · |S| / |D_t|.
- **On the full room** (grasp: 159k events, 52 objects), one new object is ≈ 3.1k events against 0.7 s for all of
  it: about 50× less.
- **A new constant with no facts yet** fails every guard that needs a fact about it. The delta is then only the
  schemas without such a guard, which is the cheap case and the common one: the robot sees a thing before it
  knows anything about it.

### 2.2 Remove a constant c from type t
Delete `C[c]`: every event naming c. There is no search; the cost is |C[c]|. The Horn facts that name c are
removed first (§2.4), so no derived fact still names c afterwards.

### 2.3 Add a bwd fact f
1. **Derive.** Compute the new derived facts Δ⁺ by semi-naive forward evaluation of the Horn rules from f, or by
   re-querying the invalidated tabled calls. Δ⁺ includes f.
2. **Fire the guards.** For each schema guard g that unifies with a fact of Δ⁺, walk the substitutions with g's
   variables fixed by the unifier. The other guards and the `<>` pairs are answered as usual.
3. **Deduplicate.** The parts may overlap, because two new facts can admit the same σ. Deduplicate on the
   event name, which is a function of (S, σ) (`ground.py:95-110`).

- **The cost** is |Δ⁺| times the rest of each schema the guard leaves free.
- **For the semantic map's `recat(p_i, l_j)`**, if recat stayed a static table, a rebinding (a place moved) would
  be a removal plus an addition. Each touches about |events of S| / |places|: at k = 16, ≈ 610 / 18 ≈ 35 for
  grasp, so ≈ 70 per move. The program stays the static table's 610 events instead of the dynamic form's 13k.

### 2.4 Remove a bwd fact f: delete and re-derive (DRed)
1. **Over-delete.** Remove f and every derived fact whose recorded support includes f, transitively. Mark every
   event in `F[f′]` for each removed f′.
2. **Re-derive.** Re-query the removed derived facts against the remaining facts: an alternative proof may
   exist. A fact proven again comes back with its new support.
3. **Re-check.** Re-check each marked event's guards against the remaining facts and keep those that still hold.
   An event that held only through a removed fact is deleted.

This is standard DRed. It is the only reason supports are recorded per answer. The cost is the marked set plus
the re-derivations: bounded by the events f supported, and in fact tables by exactly those.

### 2.5 What stays outside the delta
- **The `<>` pairs and closed (variable-free) guards** need nothing: they are checked per σ.
- **A schema or a rule added or removed** (the loop's accept, a reload) is a catalog change, not a delta. It is
  ground for that schema alone: add = ground S, remove = drop S's events, by schema name.
- **A type changing its order of constants.** The order of D_t is the IR's normative grounding order (spec 01
  §0), which §4 deals with.

## 3. `type t open.`: what it would mean, and why it is not needed now

On top of §2, an open type is a type whose constants the SESSION supplies:
- it compiles with no constants (an abstract type that is legal to ground, empty, unlike spec 12's which
  refuses);
- `+const t c` / `-const t c` on a live session are §2.1 and §2.2;
- `bwd` facts about c arrive as §2.3 and §2.4;
- the host's map becomes the program's types again: the room as constants, now cheap to change.

The language change is small: a keyword on the type declaration, two REPL verbs, a wire op. Spec 12 already
separates "declared" from "has constants".

**It is not needed while (C) holds.** Roles bound the working set by construction (k places, 2 objects), so
every ground program is small and fixed, and a changed world is a rebinding of atoms (`deliver()`, `sync()`),
measured at 1.09–1.14 s for the whole win turn (nina, step 2). Open types would bring back what roles removed:
the program's size follows the room's.
- That is right only for a world whose rules must tell apart **more things than any fixed capacity holds** at
  once. One example is a planner over every object in the room, such as the agent's person-mode task: 44
  pickupables, 28.5k events.
- No world in the catalog needs that today. Roles serve alfworld, and MiniHack is next on the same roles (step 3).

## 4. The key and the IR after a delta

**The canonical key (spec 03, `kernel/nets.py:98-121`)** hashes the ground program's content: clause lines sorted
bytewise, the links, the init stage, the init multiset. It hashes no names and no declaration order. So:

> **Ruling proposed: a grounded program's identity is the key of its CURRENT ground content (a re-key), never
> "base key + the applied deltas".**

- **Correctness rests on the invariant**: incremental ≡ full re-ground of the changed catalog, as sets of clause
  lines (§5). With it, the key after a delta IS the key a full re-ground would give. Two sessions that reach the
  same content by different deltas share a key, as they must: the key is about what the program is, not how it
  got there.
- **Base + deltas** would give two keys to one program, and the formalization loop's records (key-addressed)
  would split.
- **The cost of re-keying** is the sorted hash, O(n log n) per delta. If that ever matters, the key can be
  maintained incrementally as a commutative multiset hash over clause lines (add on insert, subtract on
  delete). That would be a new key version (spec 03's versioning), not a change of meaning. At 2.4k events the
  sort is microseconds; nothing in alfworld's numbers asks for it.

**The IR (spec 01)** is "a function of the catalog text, the init multiset, the horizon, the unknowns set" (§0),
in a normative order: type constants in declaration order, then the substitution product, first variable
slowest.
- **After a delta**, the session's IR is the IR of the changed catalog: the catalog text plus the delta log
  applied (the constants appended to their types in order of arrival, the facts added or removed).
- **An emitted IR is always that full form**, re-emitted. A delta-IR is not proposed: no consumer reads one, and
  the certifier and the Go runtime work from a whole IR.
- **The order.** Appended constants come last in D_t, so the full re-ground's order of substitutions is not the
  incremental one. That is harmless:
  - the event table the REPL uses is `canonical_events`, sorted by content (`kernel/refsample.py:40-51`);
  - the IR's event order is re-derived at emission.

## 5. What a session holds that a delta must keep right

From the survey of metispy (file:line for each):

| holder | keyed by | after a delta |
|---|---|---|
| `fired_rows`, `fired`, `ledger`, `fired_how` (`repl.py:338, 903-917`) | the Clause objects / names | **unchanged**: a fired event's record stands, even if the event is later deleted (history) |
| the undo marks (`repl.py:782-786`) | counts, lengths | unchanged; an undo across a delta is refused (or the delta log is undone too: a later decision) |
| `PortPricer._sites` (`compiler.py:824-844`) | event NAME, but the read scope is computed through the Horn DB | **invalidate** the entries whose scope used a changed predicate |
| `PortPricer.policy`, `ForwardProjection._rank`, `Cone.events` (`compiler.py:868-887`, `kernel/filter.py:114-117`, `lang/cone.py:45-47`) | event INDEX into canonical / declared order | rebuilt per program today; **rebuild after a delta** (cheap at these sizes) |
| `_maybe_enabled`'s index `_cidx` (`repl.py:860-886`) | the table's identity and length | **maintain**: append a new event to `by[rarest premise]` (or `free`); remove a deleted one; recount rarity lazily. This is the existing partial step: it is already an atom → candidates index |
| `events_tbl`, `atoms`, `key` (`repl.py:401-445`) | — | apply the delta, union the new atoms, re-key (§4) |
| `_scene_cache` (`loop/wire.py:110-124`) | the catalog object's identity | invalidate |

**The invariant test** (the gate for any implementation): for a random sequence of deltas over the corpus's
catalogs (types with ≥ 2 constants, Horn facts and rules), after each delta, the set of clause lines and the key
must equal a full `ground()` of the changed catalog. Byte parity with the OCaml grounder is the existing gate,
and OCaml would not need the incremental path (`metisc` is one-shot).

## 6. The partial steps that exist

1. **Guards answered as they bind (aa55fb3, `ground.py:35-92`).** The walk §2 reuses unchanged: fix one
   variable's domain and walk. It took the 160k-event room from 14 s to 0.7 s, and it is why the deltas are cheap.
2. **The candidate index (`_maybe_enabled`).** An atom → events index, rebuilt only when the table object or
   its length changes (e361c99: "no path mutates it today"). Incremental maintenance is a few lines once the
   table changes in place.
3. **The cone (spec 11, `lang/cone.py`, `lang/measure.py:89-114`).** Post-ground relevance: backward from a
   query's atoms, plus forward may-reach (`live_events`). It is complementary, not a substitute: the cone
   shrinks what one question looks at, while deltas change what the program is. A cone over a delta-maintained
   program is recomputed, as it is per question today.
4. **Pack admission (spec 12, `catalog.py:155-214`).** It completes abstract types by building a new catalog and
   re-grounding fully. It is the one existing "constants arrive later" path. With §2.1 it could become a delta
   when the session is live (the loop's `_reserve`).

## 7. The cost bound, in one line

A delta costs the share of grounding that names what changed: |Δ| ≈ Σ_S (#vars of S touching it) · |S| / |D|
for a constant, and the events its support reached for a fact. The index costs O(|events| · (vars + guards)) in
memory. Against a full re-ground, the gain is the ratio |program| / |share|: about |D_t| / (#t-vars) for a
constant, 25–50× on the full room, and about the number of places for a recat change.

## 8. The measured motivation (semantic-map steps 1–2, CPU)

| situation | full re-ground | delta (estimated from §2) |
|---|---|---|
| the full room, one new object (grasp, 52 objects, 159k events) | 0.7 s ground, 1.25 s open, 261 MB | ≈ 3.1k events, ≈ 15 ms |
| roles k = 16, a place moved, if recat stayed a static table (grasp, 610 events) | 4 ms (k = 16 static) | ≈ 70 events |
| roles k = 16 as built (recat dynamic: 12,996 events, 42 ms, loaded once) | — (no re-ground: atoms) | — |
| today's narrowed per-activation instances (gone since step 2) | ~3k events, ~30 ms, every activation | — |
| the agent's person-mode task over every pickupable (28.5k events) | 155 ms open | ≈ 650 events per new object |

**What it shows:**
- **The full-room case is the one where deltas matter (≈ 50×).** That is exactly the case (C) designed away.
- **Under roles, deltas would only buy back the static-table pruning** (13k → 610 events at k = 16, 2.4k → ≈ 180
  at k = 8: step 1's role measure, recat static). Both are already loaded once in milliseconds, and the win turn is 1.1 s with the model at
  ~0.6 s of it.
- **Nothing measured today waits on grounding.**

## 9. Go / no-go — the user's decision

**Recommendation: NO-GO for the kernel work now.** Keep this document as the design to resume from.
- (C) roles carry the semantic map with no language change.
- The grounding the session pays is loaded once and measured in milliseconds.
- The cost of the dynamic tables (places³) is accepted (the architect, step 2) and has a cheaper fix inside
  (C), if one is ever needed: the projection asserts recat only for bound places (it already does), and rules
  test it earlier in the body.
- The work is not small: the support-recording Horn table and DRed (§2.4), the index (§1), the session holders
  (§5), the invariant gate, and the open-type surface (§3). That is a kernel change in metispy, with OCaml
  untouched.

**GO if any of these is measured** (a trigger, not a guess):
1. **A world whose rules must tell apart more things at once than a fixed capacity holds.** For example, a
   planner over every object in view, where k = 16 roles would not do: the person-mode task's 28.5k events
   re-opened per new thing (155 ms) on the critical path of a turn.
2. **The formalization loop's accept dominated by re-grounding**, where a pack's admission (§6.4) costs seconds
   on the loop's catalogs. That needs a measurement on the loop's records first. None is on file.
3. **A world needing a `bwd` table to change on a live session** where the pred form's growth (places³-like)
   leaves the millisecond range at its real capacity. For example, MiniHack's geometry at a dungeon's real size
   in step 3.

On a go, the order is:
1. §1 index and §2.1 / §2.2 (constants: no Horn change);
2. the §5 holders and the invariant gate;
3. §2.3 / §2.4 (facts, DRed);
4. §3 `type t open.` last, as its own language proposal.

Probabilistic facts stay out of scope: belief is the weight ports' (`look(O, R)`, step 2).
