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

## P1a — links (branch finding, amendment)

A quiescence link fires on GLOBAL stage quiescence — a negative
premise over every clause of the stage, out-of-cone ones included.
A reachable link therefore pulls its pre and post stages into the
cone WHOLE (exact, no reduction). The fiction catalogs have no
links; stage-structured ones pay this honestly.

## P5 — the sampled tier (branch finding, amendment)

The branch measured the structural truth: on densely coupled
catalogs the cone IS the world (tragedy: 458/459 atoms, every
outcome tried; `at(C,L)` is persisted by nearly every rule and
written by travelTo, and the attitude web closes over itself), and
sound reachability pruning (14800 → 222 live events) does not cut
the real cost driver — 35 enabled events × 6 steps of breadth. The
cone/quotient REMAINS the exact tier's reduction (free and exact
where cones are small); interactivity on tragedy-class catalogs
comes from a SAMPLED tier instead:

- Paired Monte Carlo for necessity/whatif: both arms (do vs chance)
  driven by COMMON RANDOM NUMBERS — a variance-reduction device for
  the difference estimator, NEVER a cross-world coupling claim (each
  arm estimates its own well-defined marginal; the pairing is
  statistics, not metaphysics — spec 10's no-canonical-coupling
  stance stands).
- The answer is labelled: "sampled, n=…, ± ci"; n grows until the
  CI meets a target or the time budget; the report states which
  tier answered and why ("exact refused: …; sampled n=2000").
- Auto-selection: exact when the projection fits the interactive
  budget, sampled otherwise; `full`/`exact` forces (and may refuse).
- Measured on spec 10 §8's tragedy PN (seed 132): n=2000 → 0.980
  ± 0.006 in 1.6 s; n=20000 → 0.984 ± 0.002 in 16 s; exact 0.9846
  inside both intervals.

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

1. **Agreement** (unchanged): wherever the exact tier answers, cone
   and full agree EXACTLY under the same readout — any mismatch is a
   bug (P1/P2 claim exactness; GATE PASSED on the branch: 3lp 768
   cases, love_triangle 324, max |Δ| 7e-16; check_closed on every
   sweep). The sampled tier's own gate: on exactly-answerable cases
   the CI covers the exact value at its stated level.
2. **Interactivity** (rewritten — the original "cone makes tragedy
   exact-interactive" is structurally false, P5): necessity answers
   on tragedy-class catalogs in SECONDS with honest uncertainty —
   the §8 tragedy PN via the sampled tier at the default n; the
   exact tier used automatically below budget; the timing table
   reports full vs cone vs sampled, and cone speedups are shown
   where cones are small.
3. **Readout bias** (rewritten — the branch showed love_triangle's
   0.22 is PARTLY REAL: move_on consumes the eros every jealousy
   reads, so the chains are prospectively coupled through resource
   competition; spec 10 §8's "leak" reading is CORRECTED — part
   coupling, part readout): the bias test moves to a SYNTHETIC
   fixture of two provably resource-disjoint chains, where @N
   cone-steps must give PN ≈ 0 while global-N leaks; love_triangle
   becomes the coupling DEMO, its report explaining the competition.
Merge to master only when all three hold and the review is clean.
Deferred, not in scope: the trace-conditioned (retrospective) cone —
a different question (conditioning on the actual run's structure);
noted for a future proposal if the sampled tier proves insufficient.

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
