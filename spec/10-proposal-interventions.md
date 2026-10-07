# PROPOSAL 10 — interventions and prefix counterfactuals
# (Pearl's ladder over the trace measure)

**Status: direction ACCEPTED 2026-10-07 (user); REPL-FIRST — built
and evaluated in the metis shell (metispy) before any runtime port.
Kernel semantics, canonical keys and the IR are untouched (§6).**

Origin: the Pearl correspondence (2026-10-07). The ladder maps onto
what the kernel already is:

- **Rung 1, observe** — conditioning the exact measure over
  derivations: `query`, `lik` clamps, `recover()`. Exists.
- **Rung 2, intervene** — `do()` is graph surgery; metis performs it
  already, unnamed, in two forms. STATE surgery: `assert`/`retract`/
  `#init` — "an edit no event explains"; spec 09's rebase IS Pearl's
  mutilated graph (the cone is cut, the intervention is the new base).
  CHOICE surgery: `step NAME` / `#interactive` — forcing a ⊕ site
  (the site's CPT, spec 07) instead of sampling it; the continuation
  measure is `P(· | do)` by construction.
- **Rung 3, counterfactuals** — linearity abolishes trans-world
  identity: tokens are indistinguishable and CONSUMED (a spent
  resource has no "would have been", spec 09's no-token-lineage
  stance), and the sampler's draws have no cross-world coupling
  (after surgery different tiers are enabled; reusing the seed would
  be numerology). What survives, and suffices: **chancy,
  non-backtracking prefix-forks.** The multiset is the whole world,
  so with a certified trace Pearl's abduction step is trivial —
  rungs 2 and 3 coincide at a fork point; with partial evidence
  (surprise records, `#unknown`) abduction = the existing trace
  posterior. The unrealized future is honestly re-randomized.

## P1 — `fork [K]` and `back`

`fork K` branches the session at occurrence K of the current trace:
the actual world is SHELVED (trace, counts, stage, base), the session
state becomes exactly post-K (deterministic prefix replay), and the
causality graph marks the fork point. `back` restores the shelved
world. v1 keeps ONE alternative world at a time (D1); parallel
worlds are what multiple console sessions already are. `fork` with
no K forks at the current tip (= "from here").

## P2 — `do`: interventions as first-class marks

    do +ATOM [N]     state surgery (assert, recorded as intervention)
    do -ATOM [N]     state surgery (retract, recorded)
    do EVENT         choice surgery: force EVENT at the current tier

Same mechanics as today's `assert`/`retract`/`step`; the new part is
HONEST BOOKKEEPING: the session records which transitions were forced
and which atoms were set. Forced choices are excluded from the
trace's likelihood (spec 07 P2 already notes `#interactive` records
"conditioning, not sampling" — this unifies that), the causality
graph draws do-nodes distinctly (the rebase half-does this for state
surgery), `log`/`trace` mark them, and NARRATE must never present an
intervention as sampled — faithfulness extends to agency.
`do ~EVENT` (block) masks a ground event out of the enabled tier for
this session (the policy-hook semantics: prune, measure
renormalizes); needed by P4. Masks are session state, listed by
`ctx`, cleared by `reset`/`back`.

## P3 — `whatif`

    whatif K do(...) [do(...)...] query ATOM [STEPS]
    whatif K do(...) run N

Sugar: `fork K` → apply the do's → the exact query (or a sampled
run) → a COMPARISON report (actual world's outcome beside the
counterfactual marginal, the do's listed) → `back`. One command, one
answer: "had X been forced at step K, P(Y) would have been p (it was
q)."

## P4 — probabilities of causation (the exact tier)

- `necessity K [ATOM]` — PN: the actual trace fired event K and ATOM
  holds now; fork at K−1, `do ~EVENT_K` (block), ForwardProjection to
  the actual horizon: report `P(¬ATOM | do(¬K))` beside the fact.
  "Was the murder necessary for the suicide?" — tragedy is the demo.
- `sufficiency K ATOM` — true PS needs the posterior over worlds
  where K did NOT fire and ATOM did not result; v1 ships the
  INTERVENTIONAL PROXY (fork at K−1, force K, compare `P(ATOM)` with
  the unforced baseline) and SAYS it is a proxy (D3); exact PS via
  posterior enumeration is v2, budget doctrine applies.
- `why` (spec 09) remains graph-necessity (structural, Halpern–Pearl
  actual-cause skeleton); `necessity` is measure-necessity. The pair
  is the point.

## P5 — surfaces

REPL commands + the same ops on the wire (whitelist: all session-
local, no paths, no approval — `do`/`fork`/`whatif`/`necessity`/
`sufficiency`/`back` join INTENT_VERBS); the console gets them for
free through the intents pipeline, chips/UI later. `graph`/`why`
render do-nodes and the fork cut; `ctx` lists active masks and the
shelf.

## §6 — scope: REPL-first; the IR is NOT involved

Everything above is metispy SESSION/DRIVER code: fork/replay and
shelf bookkeeping, forced-choice flags, tier masks, ForwardProjection
calls. The kernel measure, the ground program, `program_key`/
`run_key`, the .llp language and the goldens are untouched — no
catalog compiles differently, no key moves. metisc and the IR
pipeline (`ir`/`bpn`/`elim`) are NOT involved: a later runtime port,
if the evaluation earns it, adds a RUNTIME API (state snapshot/
restore, forced-step, event mask) on the C++ side — driver surface,
not an IR format change; the compiled net is the same object. The
only conceivable IR touch would be computing PN/PS runtime-side,
which the exact-tier-is-metispy doctrine rules out for now.

## §7 — evaluation gate before any port (user)

The feature proves itself on the fiction catalogs before anything
moves to the runtime: 3lp (necessity of build_brick for surviving
the wolf), tragedy (PN of the murder for becomeSuicidal; whatif on
the eroticize forks), love_triangle (the some-fork from spec 09's
causes). The evaluation report — does whatif/necessity ANSWER the
"what if" the user actually asks in sessions? — decides the port.

## §D — decisions

- **D1 fork shape**: one shelved world + `back` (proposed) vs named
  branches. Parallel worlds = parallel sessions already.
- **D2 block grain**: `do ~EVENT` masks a GROUND event (proposed);
  a rule name masks all its ground instances.
- **D3 PS**: interventional proxy in v1, labeled as such; exact PS
  posterior enumeration deferred.
- **D4 steps**: 1 fork/back + do marks (forced flags; graph/log/
  narrate honesty); 2 whatif + the comparison report; 3 necessity +
  the PS proxy on the exact tier; 4 wire/console wiring + the §7
  evaluation report on the fiction catalogs.

## §8 — evaluation (the §7 gate, 2026-10-07)

Built REPL-first in metispy (steps 1-4: 5ba693a, 7709f92, 1fdd365,
step 4), wired to the console as session-local intents. Evidence:
the step reports of subject s-d0c6b72e; the verbatim runs are in the
step-4 report.

- **3lp, wolf survival** (`!wolf` = "the wolf is spent", added for this
  question): `necessity 4 !wolf` → PN = 1 — build_brick is necessary
  (blow_brick is the only rule that spends the wolf and it reads the
  brick house); `whatif 3 do(~build_brick) query !wolf` → P = 0 vs 1 by
  chance. Instant. The PS proxy is uninformative here (P = 1 forced and
  unforced) — expected: the brick house gets built anyway.
- **tragedy** (seed 132): PN of #75 Tybalt's murder of Romeo for
  suicidal(mercutio) ≈ **0.985** (necessary; mourn → depressed →
  becomeSuicidal), the contrast seed 53 PN ≈ 0.033 (not; the structural
  cone agrees on both). But the necessary one costs **10 min / 21.9 GB**
  on the exact tier (6M states); at the interactive budget it refuses,
  saying the outcome lies beyond what it can answer. 600 seeds: no
  murder→despair pair under a 6-event horizon.
- **love_triangle** (seed 1, the two jealousy chains 1<2<4, 3<5):
  per-chain answers are sharp (#3 for anger(lysander,hermia): PN = 1;
  #4, a repeat of #1's ground event: PN = 0 although it is a
  structural ancestor — the measure sees redundancy the cone cannot).
  But #1 measures PN ≈ 0.22 for an atom of the OTHER chain, structurally
  independent — the same as for its own chain's (0.217): with an
  event-count horizon, blocking an event reschedules the others, and
  that competition leaks into PN.

**Verdict.** `whatif`/`necessity` answer the what-if a session asks —
in one screen, as a sentence, with the fact, the counterfactual and
chance side by side — on the catalogs the exact tier can hold (3lp,
love_triangle, short tragedy tails). They do NOT yet answer tragedy's
real questions interactively, and the reason is inference, not driver
speed: the filter's state set explodes with unrelated concurrent
events. **A runtime port of the driver API (snapshot/restore,
forced-step, mask) would not change that** — the C++ filter is a
constant factor, the blowup is exponential. Recommended, in order:
(1) no runtime port yet; (2) kernel roadmap: interactive PN/whatif
through the factored tier (factorize/jtree, IR item 2 — today the
counterfactual instruments ride the exact filter only), or a
cone-restricted projection (an approximation: own spec); with the
metis-exact-audit backlog; (3) a scheduling control for PN — a placebo
block of an unrelated event of the same tier, reported beside PN, or a
horizon "until quiescence" — so competition for the event clock is not
read as causation. The port decision is the user's.
