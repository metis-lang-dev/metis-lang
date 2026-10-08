# PROPOSAL 11 — cone-restricted projection and
# interleaving-insensitive horizons

**Status: direction ACCEPTED 2026-10-08 (user). Implemented ON A
BRANCH in metispy (`spec11-cone`), merged only through the §5
validation gate: exact agreement with the full filter on answerable
cases, the timing table, and a spec-alignment review. REPL/driver
only — the factored tier (spec 10 §8's IR item) stays a separate
roadmap entry.**

Motivation: spec 10 §8. `necessity` is the formalization loop's
instrument — "is this rule load-bearing?" — but on tragedy it costs
6M states / 21.9 GB / 10 min offline, and the event-count horizon
leaks scheduling competition into PN (0.22 for a structurally
independent chain). The blowup is irrelevant concurrency; the bias
is the readout. One package fixes both: restrict the filter to the
question's influence cone, and read the outcome at an
interleaving-insensitive point. Acceptance in one line (user):
**necessity must answer interactively — no 30-minute waits — or it
is not useful for formalization.**

## P1 — the influence cone (prospective)

From the question's outcome atoms (ATOM / `!ATOM`, or `whatif`'s
query), a backward reachability sweep over the GROUND rule graph,
after masks prune it: every event whose produce or consume touches a
cone atom joins the cone, and its consume + persist premises join
the cone atoms; repeat to closure (horizon-bounded where a bound is
given). The instruments print the cone up front: "tracking 14 of
212 atoms · 23 of 980 events" — itself a design insight (how much of
the world the question touches).

**The closure property (the load-bearing fact):** by construction,
ONLY cone events write cone atoms (any event writing one is pulled
in), and cone events read only cone atoms (their premises are pulled
in). The cone is therefore an AUTONOMOUS SUB-PROGRAM over the cone
atoms: out-of-cone events can neither change it nor enable/disable
it. Out-of-cone events may `$`-read cone atoms; reads do not disturb
it.

## P2 — the cone-restricted filter

ForwardProjection over the quotient: states projected to cone atoms,
equal projections merged, only cone events fired. By P1's closure
this is EXACT inference on the quotient program — not an
approximation — under the P3 readouts. The quotient program is a
Program like any other: it has a canonical key, printed with the
answer (a certification hook: the same question on the same cone is
the same computation).

## P3 — readouts (horizons)

- **`@frame`** — cone-quiescence: project until no cone event can
  fire; read the outcome there. "Would the outcome still fail when
  this frame settles." Interleaving-insensitive; exact by
  Mazurkiewicz commutation (independent events commute; the cone's
  settled state does not depend on how the gossip interleaved).
  Where stages exist this is the episode boundary; on single-stage
  catalogs (tragedy's `stage all`) it is the whole story — use @N.
- **`@N` (cone-steps)** — horizon counted in CONE events only: the
  de-biased analog of "within N events". Insensitive to out-of-cone
  scheduling; bounded; the practical default. Default N = the number
  of cone events in the actual remainder (matches necessity's
  current semantics, de-biased).
- **plain N (global events)** — kept ONLY for §5 validation and
  explicitly flagged "scheduling-sensitive" when used.

PN under a readout: P(¬ATOM at readout | do(~K)) from the fork at
K−1; whatif/query/sufficiency take the same `@` suffixes.

## P4 — surface

`necessity K ATOM [@frame|@N]`, `whatif … query ATOM [@frame|@N]`,
`query ATOM [@frame|@N]`; a `full` keyword forces the unrestricted
filter (validation; prints the same readout for comparability). The
cone line, the quotient key and the readout always appear in the
report — an answer must say what it tracked and when it read.

## §5 — the validation gate (the user's merge protocol)

On branch `spec11-cone`; opus implements; the architect reviews for
SPEC ALIGNMENT (P1 closure verified in code — an out-of-cone event
that writes a cone atom is a construction bug and a test must prove
the sweep closes); then:

1. **Agreement**: on every case the FULL filter can answer (3lp,
   love_triangle, short-tragedy tails), cone and full must agree
   EXACTLY under the same readout — any mismatch is a bug, never an
   acceptable approximation (P1/P2 claim exactness).
2. **Timing**: a table, full vs cone, same questions — including
   spec 10 §8's tragedy PN (seed 132, murder → suicidal). HARD
   acceptance: the tragedy case answers at the interactive budget
   in seconds; the general rule: no instrument answer takes longer
   than the user's patience for a formalization check.
3. **Bias**: love_triangle's independent-chain case — PN under @N
   cone-steps must drop to ~0 where the event-count horizon leaked
   0.22 (the §8 placebo concern resolved by the readout, not by a
   placebo).
Merge to master only when all three hold and the review is clean.

## §6 — scope

metispy only, driver/instrument layer: the cone sweep, the quotient
constructor, the readouts, the report lines. The kernel
ForwardProjection is REUSED on the quotient program (ideally zero
kernel change; if a seam is needed it must not move program_key or
any golden). No metisc, no IR, no runtime. The Lean statement of the
commutation exactness (disjoint footprints ⇒ readout invariance) is
noted for formal/ as future material, out of scope here.

## §D — decisions

- **D1 default readout**: `@N` cone-steps with N = the actual
  remainder's cone-event count (proposed); `@frame` where the user
  asks or the catalog has settling stages.
- **D2 plain-N global**: validation-only, flagged (proposed).
- **D3 the quotient key**: printed with every cone answer (proposed
  — certifiability and cache key in one).
- **D4 cone cache**: the sweep is per (question, masks) — cache it
  per session keyed by (quotient key, readout)? Propose yes,
  trivially (a dict), since formalization sessions re-ask.
