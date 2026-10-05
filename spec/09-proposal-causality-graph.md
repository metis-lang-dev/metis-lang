# PROPOSAL — causality graph (the run as a queryable partial order)

**Status: ACCEPTED 2026-10-05 (user review); D1–D4 resolved — the
decisions are recorded inline in §D at the end.**

Origin: the execution-readability gap. In a live session it is hard
to tell WHAT IS RELEVANT (which fired events the current state
actually depends on) and WHERE WE ARE (the frontier of the run —
`log` is a flat list, `state` a flat multiset; the causal structure
between them is invisible). Audit against TeLLer (jff/TeLLer, the
interactive LL prover built to study causality in interactive
storytelling) and its CelfToGraph frontend (Celf solutions →
structured graphs with a small query language). Their answer is the
causality graph of a run. metis already COMPUTES the underlying
object — `run_key` hashes the Foata normal form of the Mazurkiewicz
trace (`nets._footprint` dependence, `foata_levels` beats) and
`narrate` speaks its beats — but nothing ever SHOWS it. This
proposal exposes the object we already certify.

## Command audit (TeLLer → metis)

| TeLLer            | metis today                         | verdict |
|-------------------|-------------------------------------|---------|
| `p` print env     | `state` / `list`                    | have    |
| `+`/`-` resources | `assert`/`retract` (same aliases)   | have    |
| `s` forward chain | `run N`                             | have    |
| `l` load          | serving file + `reload`             | have    |
| `r` reset         | `reset`                             | have    |
| `d` debug toggle  | `findings` (spec 08)                | have    |
| `a` all stories   | exact tier: `query`/`map` (filter)  | non-goal|
| `g` granularity   | the firing tier is normative (06 §4)| rejected|
| `c FILE` graph    | — MISSING                           | **P2**  |
| `x a1 a2` caused? | — MISSING                           | **P3**  |
| CelfToGraph `exists a` | `log` (grep)                   | note    |
| CelfToGraph `link a1 a2` | — MISSING                    | **P3**  |
| boolean query ops `~ && \|\| <= => <=>` | —             | deferred (P5) |

## P1 — the object (normative, toolchain-neutral)

The **causality graph of a trace** is a pure function of
`(program, init, trace)` — no session state, no new semantics.

Occurrences: the fired rows `(kind, stage, ev)` in firing order,
numbered 1..n (`log`'s numbering), plus a virtual occurrence 0,
`#init`, whose footprint writes the initial multiset and
`("@stage", init_stage)` and reads nothing.

Dependence: exactly the footprint conflict `run_key` quotients by
(`nets._footprint`, writer-vs-anything) — NOT a new relation. The
causal order `≤` is the reflexive-transitive closure of
{ i ≺ j : i < j and footprints conflict }.

Graph: the **Hasse diagram** of `≤` (covering edges only — D1:
readability; every covering edge is a direct conflict, so each edge
carries its conflicting atoms). Edge vocabulary, in this precedence:

- **flow** `a`  — produce(i) ∩ consume(j): a token i made, j spent
  (solid, atom-labeled; the causal edge proper, TeLLer's arrows);
- **read** `$a` — produce(i) ∩ persist(j): j read what i made;
- **order**     — remaining write-write conflicts: consume-consume
  competition, stage switches.

v1 renders ONLY the flow class distinctly (D4); read/order covering
edges draw plain and unlabeled, the classification held in reserve.

Ranking: `foata_levels` — nodes of one level are one beat (pairwise
independent), rendered rank-per-beat. Links (stage switches) are the
run's phase boundaries and render distinctly (diamond). **Maximal
nodes are the frontier** — "where we are" — and render bold; the
graph label carries file, key prefix, current stage, step count.

Determinism: node order = occurrence index; edges sorted by (i, j);
atoms in a label sorted. Two traces with equal `run_key` have equal
graphs up to beat-internal renumbering — the graph IS run_key made
visible, which is why the dependence relation must stay the shared
one and never fork.

Mirrors, both deterministic:

- DOT (text only — rendering is the user's `dot -Tsvg`; no graphviz
  dependency, the mis-deployed-pack doctrine applies to viewers too);
- JSON (the wire/console channel):
  `{nodes: [{i, name, kind, stage, beat}],
    edges: [{from, to, atoms, kind}], frontier: [i...],
    stage, key}`.

## P2 — `graph [PATH]` (REPL + wire)

    graph               beats as text: one line per Foata level,
                        each occurrence with its covering parents
                        (k<j notation), frontier marked *
    graph FILE.dot      write the DOT rendering
    graph FILE.json     write the JSON mirror

Derived ON DEMAND from the fired rows SINCE THE LAST EDIT NO EVENT
EXPLAINS (session start, `reset`, `assert`/`retract`, buffer `#init`,
`reload`/`accept` when they reset counts) — the base occurrence 0 is
the state at that edit, log numbering is kept, and the base rides the
undo stack so `undo` restores it. (Step-1 amendment: the draft's
"undo/reset stay correct for free" was wrong — those commands mutate
state without a fired row, so a graph over the whole log would show
tokens from nowhere.) Wire op `graph` returns the JSON object (the
web console draws it). The bare text form is the primary surface: the
answer to "where are we" must not require leaving the terminal.

## P3 — `why` and `causes` (relevance queries)

    why                 causal cone (ancestors) of the frontier —
                        the events the current position actually
                        depends on; prints the cone grouped by beat
                        with source lines (as `list` renders rules),
                        then "pruned: K irrelevant events"
    why ATOM            cone of the last occurrence that produced
                        ATOM (never produced but present → #init)
    why K               cone of fired event K (log numbering)
    causes A B          TeLLer's `x`: for each occurrence of event
                        B, is some occurrence of A among its
                        ancestors — per-pair rows + a yes/some/no
                        summary (CelfToGraph's `link a1 a2`)

`exists a` needs no command: `log` already lists occurrences.
Multiset token identity is NOT tracked (atoms are indistinguishable;
Celf has proof-term provenance, we do not): `why ATOM` is defined on
occurrences-that-produced, not on token lineage — stated in help so
nobody reads token provenance into it.

## P4 — toolchain scope

metispy-only (D2): this is the discovery surface (REPL/wire), metisc
has no REPL — precedent spec 08 C1. P1 stays toolchain-neutral on
paper so a later OCaml emitter (if ever wanted) cannot drift, but no
`--graph` lands in metisc.

## P5 — non-goals

- `g` (focusing granularity) and `a` (all stories): the firing tier
  is normative; exhaustive semantics is the exact tier's job
  (`query`, `map`, ForwardProjection) — a second enumerator would
  fork the measure.
- CelfToGraph's boolean query combinators: deferred until composed
  queries are an observed need; `causes`/`why`/`query` cover today's.
- The state-space DAG of ForwardProjection: a different object (the
  possibility order, not a run). A later proposal may draw it; this
  one is strictly the fired trace.
- In-process rendering (jpg/svg): DOT text only.

## Implementation sketch

- `metis/kernel/nets.py`: `causal_graph(rows, init, init_stage)` —
  pure, reuses `_footprint`/`foata_levels`; O(n²) in fired steps
  like `foata_levels` (sessions are short; if a pathological session
  hurts, the budget doctrine applies — say so, don't wait).
- `metis/lang/causality.py`: DOT / JSON / beat-text renderers
  (deterministic ordering as P1).
- `repl.py`: `do_graph`, `do_why`, `do_causes` over `fired_rows`;
  `_HELP` gains a "causality" stanza; wire ops `graph`/`why`/
  `causes` return JSON.
- Tests: pinned graph goldens on the tragedy fixture (DOT + JSON
  bytes); property: adjacent-independent swap leaves the canonical
  graph bytes invariant (the run_key theorem, now visible); `why`
  cone = ancestors check against a hand-computed trace; `causes`
  truth table on a fixture with a fork.

## §D — decisions (resolved in review, 2026-10-05)

- **D1 edges — RESOLVED: Hasse diagram.** Readability preferred;
  revisit only if a pruned flow edge ever confuses a real session.
- **D2 metisc parity emitter — RESOLVED: not needed.** metispy-only;
  P1 stays toolchain-neutral on paper so a later emitter cannot
  drift, but no `--graph` in metisc.
- **D3 bare `why` — RESOLVED: cone of the current state.** (Step-2
  amendment: the resolution first said "frontier cone", which is
  vacuous — every node lies below some maximal node, so that cone is
  always the whole graph. The intent was always the Origin's "which
  fired events the current state actually depends on": a virtual
  `now` reads every present atom and the active stage; the roots are
  the occurrences whose writes conflict with that read, the cone is
  roots + ancestors. Presence only — atoms are indistinguishable, so
  this is dependence on the multiset, never token lineage.)
  Follow-up noted: the cone is the candidate formalization of
  `list`'s "relevant context" (which rules/state the position
  depends on) — a later change may derive `list`'s relevance marking
  from the cone instead of the enabled-now check alone.
- **D4 edge classes — RESOLVED: flow-only first; CHECKED 2026-10-05:
  insufficient.** On tragedy (heavily `$`-guarded, attitude-token
  competition) most covering edges are read/order, so the flow-only
  DOT reads as a web of unlabeled gray arrows — the user's dotty
  check of the step-1 golden found "label missing and semantic not
  clear". Step 3 adopts the full P1 vocabulary in the DOT, aiming at
  CelfToGraph's causal diagrams (Martens, *Programming Interactive
  Worlds with Linear Logic*, §3.4.1: nodes are actions, edges are
  causal relationships): read edges dashed with `$atom` labels,
  order edges dotted/gray (tooltip carries the atoms), node labels
  split name / bindings over lines, and the graph label gains a
  legend line naming the three edge classes. The beat-text and JSON
  mirrors already carry the classification; goldens regenerate.
  Landed metispy 74dcc97^..: plus a beat column as the time axis,
  order edges constraint=false, frontier penwidth 2.
- **D5 quiescence frames (user, 2026-10-05) — step 4.** Group the
  DOT by the run's stage EPISODES: a quiescence link's footprint
  writes both `@stage` markers, so every beat lies within one
  episode — one `subgraph cluster` per episode (label: stage name ·
  episode ordinal, faint fill), link diamonds standing BETWEEN
  clusters, beat ranks unchanged inside. A single-episode run
  (tragedy) renders exactly as step 3 — no cluster wrapper. Needs a
  multi-stage golden beside tragedy's. The JSON mirror gains the
  episode index per node (additive); beat text is unchanged. Other
  groupings (by actor/binding, via color) stay out until asked for.
