# PROPOSAL 16 — belief in the language: categorical ports, belief facts, level ports, the one-tick instrument

**Status: RULED 2026-10-25 (spec16 s-b12d90f2 step 1, metis; the architect's brief v1 and rulings on §11).
Step 2, the metisc prototype, is IMPLEMENTED on a branch (§12); step 3 is metispy parity and one alfworld use.
Nothing here changes the grammar: the declarations are manifest fields, the query is a case field with an
embedded `#` directive (spec 00 §8), so the program_key of every existing program is unchanged.**

The user's framing (2026-10-25):
- With fixed weights, a program is a certified MDP.
- With the map's belief entering through ports, it is a belief MDP over a finite quantisation.
- The total probability of an outcome needs both factors multiplied: what the world is (the belief), and what
  the program does in it (the rule weights). Nothing multiplies them today.
- Certification stays, because nothing continuous enters the IR. The arithmetic lives in an INSTRUMENT, and
  its result re-enters the program through a LEVEL PORT, a finite atom.

## 0. In one table

| piece | where it is declared | what it means | § |
|---|---|---|---|
| categorical port | manifest `beliefs:`, over a weight port's `reads` | one distribution per group of mutually exclusive facts, bound by the host | 2 |
| belief fact | manifest `beliefs:` | a pred whose presence the instrument DRAWS from its port, instead of reading it from the init | 3 |
| level port | manifest `levels:` | a finite level atom quantised from a belief or from a query, by declared thresholds | 4 |
| query | manifest or case `evaluate:`; `#evaluate` in an `.llp` | P(outcome within h), or the risk of a violation within h | 5 |
| the instrument | `metisc --evaluate` (§7) | sum-product over worlds × traces, beliefs constant over h, the state budget as the cut | 6 |
| certification | the cell table | per cell of level combinations, the bound the static instrument gives | 8 |
| the paper's rewrites | the instrument's net only | weakening, deferred draws, absorption, merging: same exact number, fewer states | 9 |

## 1. What is wrong today, and the two factors

The alfworld task's port is the only belief in the language today:

```
weight look(O, R) reads {inrecep(O, R)}.
go_for [dyn] : want(O) * start * $inrecep(O, R) -o want(O) * goto(R)  @w look(O, R).
```

The map asserts `inrecep(O, R)` for every place the object may be, and `look` prices the choice among them.

That is a CHOICE weight: spec 06 §4 normalises it over the enabled events of the state. It answers "where
does the task go first", not "where is the object". Two things a total probability needs are missing:

- **The world factor.** P(the object is in R) is a distribution over mutually exclusive facts: exactly one R
  holds. Pricing each `inrecep(O, R)` by its own independent weight describes 2^k worlds, including ones with
  the object in two places or in none. That is wrong for a total probability: the mass of the impossible
  worlds is counted.
- **The product.** P(fetch done within h) = Σ_R P(object in R) × P(done within h | object in R, the task's
  choices). The first factor is the belief, the second the program's measure. Nothing multiplies them: the
  sampler draws one trace from one init, and the exact filter (metispy `ForwardProjection`) projects one init.

The instrument (§6) is that product, computed exactly. A level port (§4) brings its number back as a finite
atom.

## 2. The categorical port

**Declaration.** A belief group is declared in the member's manifest (`domain.yaml`) over a weight port that
already exists in the program, and the port's `reads` scope ties its formals to the fact's arguments:

```yaml
beliefs:
  inrecep: {port: look, one: R}     # categorical: for each O, exactly one R holds; look(O, ·) its distribution
  pot_space: {port: room}           # independent: present with probability room()
```

```
weight look(O, R) reads {inrecep(O, R)}.          % the program, unchanged
weight room reads {pot_space}.
```

- `port` names a weight port of the program. Its `reads` scope must be exactly one pattern over the belief
  pred, whose arguments are the port's formals. A guard on the pattern (`reads {inrecep(O, R) if place(R)}`)
  restricts the support. Anything else is a finding (`belief-port`).
- `one: V` names one formal of the port. The group key is the other formals; the members are V's domain (its
  type, cut by the guards). Without `one`, every ground atom is its own independent group.
- `lone: V` instead of `one: V` allows "none of them": the members' mass may be below 1, and the residual is
  the world where no member holds (alfworld's `lost`).

**The binding contract.** The host binds the port as today (spec 00 §8, metispy `Registry`): a value per
ground argument tuple. A categorical port adds one obligation, checked exactly by the instrument:

- `one`: for every group key, Σ over the members = 1;
- `lone`: Σ ≤ 1;
- an independent belief: every value in [0, 1].

A violation refuses the evaluation, naming the group and its sum (`belief-sum`). There is no silent
renormalisation: a distribution the host did not mean is not repaired.

**Why a manifest field, not syntax.** Syntax is frozen (spec 00 header). A belief is a fact ABOUT the
program's inputs, like spec 15's natures, and the tick never reads it: it changes nothing the sampler does, so
the program_key must not move. Like the natures sidecar (spec 15 amendment 4), the canonical line of
`beliefs:` and `levels:` enters the certificate's key (§8). A grammar form (`weight look(O, R) one R reads …`)
is a later option if a toolchain without manifests needs it.

**The proof-net reading** (Di Guardia, Ehrhard, Evrard, Faggian, arXiv:2602.04045; spec 14 §2). A group is
ONE categorical node: a box ⊢ X⁺ whose variable has the group's k members as its values, with the port as its
CPT. k independent Bernoulli boxes denote the same distribution only once an "exactly one" factor couples
them, and that factor spans all k variables. The categorical box is one variable of card k. So the
categorical form is both the correct total and the cheaper net.

## 3. Belief facts

**Semantics.** In the instrument, the presence of a belief pred's ground atoms is not read from the init. It
is DRAWN from the port:
- each `one` group puts exactly one member present (count 1), with probability f(member);
- each `lone` group puts one member present with probability f(member), or none with the residual;
- each independent atom is present with probability f, absent with 1 − f.

A WORLD is one outcome of all the draws. Its probability is the product over the groups. The instrument's
initial distribution is the mixture μ₀ = Σ_w P(w) · δ(init ⊎ w).

- **The case's init must not list a belief atom.** The draw puts it there, so an init line of a belief pred is
  refused (`belief-init`). The tick's init is untouched: there the map asserts the atoms as today.
- **Belief preds are resource preds.** A `bwd` pred cannot be belief-bearing: a guard is a Horn premise
  eliminated at grounding (spec 14 §2), and a world must not change the ground program. Every world shares
  one ground program, and only the init differs. A static fact that should be uncertain becomes a `$`-read
  resource pred.
- **Which atoms are drawn.** Only the groups some ground event reads or writes. A group no event touches
  sums to 1 and is dropped (§9, R1).

**Reading discipline: a read of a belief fact is conditioned on the truth.** In world w, a rule enabled by
`$inrecep(O, R)` fires only where w has the object in R. That is right for the WORLD's rules (the observation
"absent", the find). It is OMNISCIENT for the agent's decisions: a task whose `go_for` reads `$inrecep` goes
straight to the true place in every world, and its success probability is overstated.
- So the instrument lists every rule that reads a belief pred, as the note `belief-read <rule> <pred>`. The
  author sees which decisions are conditioned on the hidden truth.
- The honest form keeps two preds: the agent's SUPPORT (where it may be, the map's assertion, read by the
  decision) and the belief fact (where it is, read by the world's rules). The port prices both: as a choice
  weight on the decision (`@w look(O, R)`, today's use) and as the presence of the truth. That is "the look
  port generalised": one port, two roles.
- For a member run alone, the world's rules come from a WORLD MODEL file the instrument's case includes (as
  the stub's case closes the interface with facts, spec 15 §10.4): `goto(R)` answered by `reached(R)`, and
  `absent(O, R)` or the find by the belief fact. Step 3 writes alfworld's.

## 4. Level ports

A level port turns a number into a finite atom the program reads. It is declared in the manifest:

```yaml
levels:
  fetch_risk:                        # pred fetch_risk(risk) — a level pred the program declares
    from: {evaluate: lose}           # the query named lose (§5): one number
    at: [0.1, 0.3]                   # increasing thresholds in (0, 1)
    names: [low, mid, high]          # the level type's constants in order; |names| = |at| + 1
  sure:                              # pred sure(certainty, object, receptacle)
    from: {belief: look}             # one number per ground atom of the belief: its probability
    at: [0.5, 0.9]
    names: [unlikely, likely, certain]
```

- **Quantisation.** For a value p: level names[i] iff at[i−1] ≤ p < at[i], with at[−1] = 0 and at[n] = +∞.
  The comparison is exact (§6.4), so a value on a threshold has one level on every host.
- **The level pred.** Its first argument has the level type, whose constants are `names` in order (a finding
  otherwise, `level-type`). The rest are the source's key: none for a query, the port's formals for a belief.
  The host asserts exactly one level atom per key and retracts the previous one. It is a world-private
  reading in spec 15's directions.
- **Levels are the only belief-derived input of the tick.** The program reads levels; it never reads a number.
  A tick program that reads only levels (and static weights) is a finite program: §8 certifies it per cell.
- Whether any world wants belief levels (the `belief:` source) is the worlds' decision. The spec defines both
  sources either way.

## 5. The query

A query names an outcome and a horizon:

```yaml
evaluate:
  lose:  {risk: stuck(_), within: 8}                    # the risk of a violation within 8 steps
  fetch: {reach: done, within: 12, budget: 200000}      # P(outcome within 12), the state budget for this query
```

- **The outcome** is an atom pattern: a ground atom, a pred with `_` for any argument (`stuck(_)`: any
  instance present), or a conjunction `a * b` (all present at once).
- **`reach` and `risk` compute the same number.** They differ only in the reading a level port gives it (a
  wanted outcome, a violation).
- **`within: h`** is the probability that the outcome holds at SOME step t ≤ h, the first passage, with t
  counting the program's events (spec 06 §4: a clause or a link, one per step; DONE absorbs). `at: h` instead
  reads presence at step h, as the REPL's `query ATOM @h` does. For an outcome no rule consumes once it holds
  (`done`, `solved`), the two are equal. Events, not spec 11's cone steps, are ruled for step 2; `within h
  cone` is a later option. The worlds will want a TICK-based horizon once the world model (step 3) fixes
  what one tick is for a member: its events per tick (and §2.3 of spec 15's ρ) convert one into the other.
- **`budget`** is the state budget (§6.3). It defaults to the exact filter's 500,000.
- **The embedded form.** For an `.llp` with its own case (spec 00 §8), one directive per query:
  `#evaluate lose risk stuck(_) within 8`. Port values for such a file: `#port look(target, p0) 0.6`, one per
  argument tuple. Beliefs: `#belief inrecep one R by look`. These mirror the manifest and case fields for dev
  runs. As spec 00 §8 says, certified expectations stay in manifests.
- **A case binds the ports and states the expectations.** It uses the stub's `ports:` (spec 15 §10.4) with a
  table form for a port with arguments, `ports: {look: {look(target, p0): 0.6, look(target, p1): 0.4}}`, plus
  `expect: {fetch: 0.37…}`. A constant (`look: 1.0`) binds every argument tuple, as today. Each value is a
  number, and an argument tuple the port cannot take is refused.
- **The case YAML (step 2b).** A case file holds `init:`, `ports:`, `evaluate:` (queries added after the
  manifest's) and `expect:`, plus `manifest:` and an optional `case:` name. Any other key is refused (the
  stub's `boundaries:` included).
  - **The manifest** holds `program:`, `beliefs:`, `levels:` and `evaluate:`, and the instrument ignores its
    other fields. It is found as the case's `manifest:`, else `domain.yaml` in the parent of a `cases/`
    directory (a package's own cases), else `domain.yaml` beside the case.
  - **`init:`** is a flow list of atoms, `atom` or `atom n`.
  - **`ports:`** maps a port to a number, or to a table `atom: number` whose atoms are that port's own
    argument tuples. A list is a `port-function` refusal.
  - Both files are read by metisc's YAML subset: `key: value` lines and flow lists and maps (spec 15's
    reader), plus block MAPPINGS by indentation. Block lists (`- x`) are refused. An atom's parentheses hold
    its commas in a flow value (`{look(target, p0): 0.6}`), and spaces inside an atom are formatting, as in a
    directive.
  - A case and its embedded form give the same directives, so the same listing, byte for byte (gate 14).

## 6. The instrument: one-tick semantics (normative)

### 6.1 Inputs, and the one-tick assumptions

The inputs are:
- the ground program P (the case's `.llp`, with a world model when §3 needs one);
- the case's init;
- the beliefs B and the port bindings f (the case's `ports:`);
- the query: outcome Q, horizon h, budget N.

**One tick.** The instrument answers for the beliefs as they stand at this tick:
- **Beliefs are constant over the horizon.** f is evaluated once, before step 0, and every weight port
  (`@w f(args)`) prices its events by that frozen table at every step. A binding that reads the state (a
  port as a function of counts) is the later extension (§10), refused today (`port-function`).
- **Filtering stays in the map.** Within the horizon, what the program observes is conditioned exactly, by
  the enumeration itself: in world w every observation follows w's truth. What the instrument never does is
  move the belief, either by its own dynamics (the object carried away, the plant drying) or by updating the
  port from what was seen. The next tick's ports come from the map's filter, outside the instrument.

### 6.2 The number

    μ₀       = Σ_w P(w) · δ((init stage, init ⊎ w))                          (§3)
    step     = spec 06 §4 exactly: tier 0 the stage's enabled clauses with W = w · φ · port factor, normalised;
               tier 1 the links; tier 2 DONE, absorbing
    absorb   = a state where Q holds (for `within`) is not expanded: its mass is added to HIT and leaves
    result   = HIT after h steps           (`within`)
             = the mass of states where Q holds at step h   (`at`)

It is sum-product over worlds × traces: products along a trace (the draws, then the normalised choices), sums
where states meet. It is metispy's `ForwardProjection` started from a mixture instead of one state, with the
outcome absorbing.

### 6.3 The state budget is the cut

The budget N bounds the retained states, cumulatively, as the exact filter's does (metispy
`StateBudgetExceeded`). The instrument does not fail at N. It CUTS:
- states are expanded in canonical order (stage, then the sorted counts);
- the mass of the states that cannot be expanded within N is CUT and set aside;
- the answer is an interval:

      lo = HIT
      hi = HIT + CUT

  This is sound for `within`: the cut mass may or may not reach Q, and nothing else can. For `at`, the same
  holds with "present at h".
- With no cut, lo = hi: the exact number.

A query is answered in bounded work at any horizon, and the width hi − lo says how much the budget hid. The
REPL's refusal at the budget (spec 10's "lower the horizon") becomes a bound.

### 6.4 Arithmetic: exact rationals

The normative value is a RATIONAL:
- every number (a rule weight, a port value, a threshold) enters as the exact DECIMAL of its binary64's
  shortest round-trip representation: a rule weight as `strtod` parsed it (spec 00 §7), a host's float
  binding, a case's literal. So 0.7 enters as 7/10, and a distribution written 0.7, 0.3 sums to exactly 1.
  The binary64's own exact value (0.6999999999999999555…) would not, and no `one` group written in decimals
  would pass §2's check. (Step 2's finding, ruled; the draft said "the exact value of its binary64".)
  - **The algorithm, normative in both toolchains:** the first of `%.15g`, `%.16g`, `%.17g` whose string
    parses back to the same binary64, read as an exact decimal. That is Python's `repr`, so metispy's form
    is `Fraction(repr(x))`. (A decimal with fewer than 15 significant digits that round-trips prints the
    same under `%.15g`: a binary64's error is below half a unit in the 15th digit.)
  - **The evidence** (metisc `src/rat.ml`, step 2b): Rat.of_float equals `Fraction(repr(x))` on 20,012
    random binary64 bit patterns, and Rat's add, sub, mul, div, compare and correctly rounded to_float
    equal `Fraction`'s on 300 random decimal pairs of up to 61 digits;
- φ is an integer, and every product, normalisation and sum is exact.

So the result does not depend on summation order, and the brute-force referee (§7) agrees to the last digit
by construction. The printed decimal is the correctly rounded binary64 of the rational, `%.17g`.
- metisc is stdlib-only, so it carries a small arbitrary-precision natural (add, mul, divmod, gcd).
- metispy has `fractions.Fraction`.
- A binary64 fast path with a stated error bound is a later option (ruled). It is not the referee.
- **The denominators grow with the horizon.** Normalisation at every step multiplies them: under rule
  weights 0.7 / 0.3 a value gains about one decimal digit per step (403 digits at h = 400, §12). Dyadic
  weights (1, 0.5, 0.25) and uniform choices keep them small.

## 7. The CLI

**`metisc --evaluate CASE` is the proposed name, kept.** It is metisc's verb for the instrument, beside
`--run` (the sampler), `--interface` and `--keys`. CASE is a case YAML (the program, its manifest's
`beliefs:` and `levels:`, `ports:`, init, `evaluate:` and `expect:`), or an `.llp` with embedded directives.

One line per query:

```
V <name> <reach|risk> <outcome> within <h> = <p>/<q> ~ <%.17g> worlds <k> states <n>
V <name> <reach|risk> <outcome> within <h> in [<p>/<q>, <p'>/<q'>] ~ [<lo>, <hi>] cut <%.17g> worlds <k> states <N>
L <level-pred>(<level>[, key…])                        one per level atom the case derives (`lo..hi cut` across)
N belief-read <rule> <pred>                            §3's notes, first, in catalog order
X <name> expected <v> got <value>                      a failed `expect`
```

`--cost` adds one line per query on stderr: `C <name> h <h> groups <g> worlds <k> bits <b> digits <d> ms <t>`
(b the largest denominator met, in bits; d the result's denominator, in digits; t CPU time).

- **Exit codes.** 0 when every `expect:` holds (`p/q` equal to the rational; a decimal equal to its
  binary64, or within the interval). 1 on a mismatch. 2 on a refusal, `refused <code>: <text>` on stderr:
  `belief-bwd` (a bwd pred as a belief), `belief-port`, `belief-init`, `belief-sum`, `port-unbound` (a
  weight port the case does not bind), `port-unknown` (a port the program does not declare, or an argument
  tuple of the wrong arity), `port-value` (negative, or above 1 under `~`), `level-type`, and
  `port-function`.
- **`port-function` is the stated host refusal.** A binding that computes (a host function, a plugin name, a
  list) is §10's later extension. A case binds numbers or a table of them, so any other value is refused
  with this code: `refused port-function: port where bound to compute.py:where: a binding that computes is
  the host's function form (spec/16 §10, later); a case binds numbers or a table of them`.
- **`--evaluate --brute`** is the referee: it draws every world up front and enumerates every event path of
  length ≤ h, with no merging, no deferred draw and no budget. Its `V` lines end `paths <n>`. It shares the
  step (spec 06 §4) with the instrument, so it referees R1–R4 and the cut, not the step semantics; those
  are refereed by metispy's exact filter, run per world (§12). Step 2's gate is `--evaluate` = `--brute`,
  as rationals, on every fixture.

## 8. Certification: the cell table

- **The cells.** The tick program sees beliefs only through level atoms (§4). A CELL is one level per level
  port: finitely many, Π n_l.
- **What a certificate holds.** For each cell c it records the interval [lo_c, hi_c] the static instrument
  gives for each query, over every belief consistent with c. At runtime the levels SELECT a cell. The
  certificate is then the program's own certificate plus this table, keyed by the program_key and the
  canonical line of `beliefs:`, `levels:` and `evaluate:`.
- **Why a cell has a finite bound.**
  - A belief level (`from: {belief: …}`) confines each port value to an interval, and a categorical group to a
    polytope (its box ∩ the simplex).
  - When beliefs enter the number only through the presence draw (§3), the result is MULTILINEAR: linear in
    each group's distribution, because μ₀ is a product of the groups and the trace measure does not depend
    on them.
  - A multilinear function over a product of polytopes has its extremes at products of vertices. So
    [lo_c, hi_c] is the min and max over the cell's vertex combinations, each one exact instrument run (with
    its own cut interval).
- **The vertex count.** Per group, by its declaration and its belief levels:

  | group | its region in a cell | vertices |
  |---|---|---|
  | independent atom | [a, b] (no belief level: [0, 1]) | 2 |
  | `one` over k members | {a ≤ p ≤ b, Σ p = 1} (no level: the simplex) | ≤ k · 2^(k−1) (no level: k, the pure worlds) |
  | `lone` over k members | {a ≤ p ≤ b, Σ p ≤ 1} (no level: the corner simplex) | ≤ 2^k + k · 2^(k−1) (no level: k + 1) |

  A cell costs Π_g V_g instrument runs. With no belief level, a cell's vertices are the PURE worlds, and its
  bound is the min and max of P(Q | w) over the worlds: the numbers `--brute` already enumerates.
  - The step 2 fixtures declare no belief level, so each has one cell: **wgc_bank 2 · 2 · 2 = 8 runs**
    (three `one` groups of k = 2), **bridge 2 per wick case** (one `one` group of k = 2), **cook_a 2 · 2 = 4**
    (two independent atoms).
  - With wgc_bank's `sure` level (thresholds 0.5, 0.9), a k = 2 group's two levels must agree with
    p_far = 1 − p_near. That leaves 5 consistent level pairs per group: four segments with 2 vertices each,
    and the point p_near = p_far = 0.5 (likely, likely) with 1. So 5³ = 125 cells, and Σ over the cells of
    Π_g V_g = (2 + 2 + 2 + 1 + 2)³ = 729 exact runs: the sweep the certificate would make. It is specified,
    not built in step 2 (ruled).
- **The enumerator is the budget sweep.** This is the bridge puzzle's method: there, one exact run per wick
  count (15 > 0, 14 = 0, metis-catalog `domains/bridge`) answered a question no single run could. Here, one
  exact run per vertex per cell.
- **A choice weight that reads a belief port** (`@w look`) makes the trace measure itself depend on the
  belief, as a ratio of the port's values. The function is then rational, not multilinear, and the vertex
  bound is not sound. Such a cell is listed `uncertified (choice reads a belief)`. The certified form gates
  the decision on a belief LEVEL with static weights. Both forms stay legal; the certificate tells them apart
  (ruled). The alfworld task keeps `@w look` until belief-levels (s-80d9a065) decides between the level rule
  and the weight-port rule; if the weight port stays, alfworld's cell stays uncertified, which is the honest
  statement.

## 9. The paper's rewrites apply to the instrument, never to the tick

The tick has no net: it samples one step (spec 06). The instrument's net is static: the beliefs, the ground
program, h and Q are fixed before it runs. So EFD's rewrites (spec 14 §2) apply to it. Each one keeps the exact
rational ([S], spec 14 §3), and the gate checks each against `--brute`.

| # | rewrite | EFD | what it saves |
|---|---|---|---|
| R1 | **weakening**: a belief group no ground event touches is dropped (it sums to 1) | §6, Lemma 6.2 | a factor k per dropped group in worlds |
| R2 | **deferred draws**: a group is drawn at the first state where its presence could matter, not at step 0: some event of that state's tiers has one of the group's atoms among its premises or consumes, or Q mentions the group. Until then the state carries it undrawn. Exact because the draw is independent of the trace so far, and nothing before that state depended on it | the cut moved to its first use (App. D's elimination order) | the worlds a trace never distinguishes: k^g up front becomes the groups actually met |
| R3 | **absorption**: a state where Q holds stops (§6.2) | box pruning to the query | every continuation past the first hit |
| R4 | **merging**: equal states sum (the frontier is the cut-net's interface) | Thm 5.2 | traces → states, the filter's reason to exist |
| R5 | **the cone**: restrict to the outcome's influence cone (spec 11 P1), when its closure holds | §6 | the events and atoms the query never meets |

Peephole and factoring in the paper's sense (§8, the cut-net's width) are the next rewrites if a fixture's
state count needs them. None is proposed before step 2 measures the cost against h and the number of belief
groups.

## 10. Later, stated, not in this spec: ports as functions

The map's PREDICT inside the instrument: a port whose value moves along the horizon (the object carried, a
beast's position, a plant drying) makes the belief a hidden Markov chain over the horizon. That is the
instrument filtering, which this spec leaves in the map. Its form when it comes: a port bound as a function
of (step, the frozen table), still evaluated by the host, never in the IR. The exact rational semantics and
the cut carry over; the multilinearity of §8 does not.

## 11. Step 2, the fixtures, and the questions for the ruling

**Step 2 (metis).** `metisc --evaluate` and `--brute` on a branch: the YAML case reader (iface.ml's subset), the
world enumeration with R1–R4, the exact rational arithmetic, and the `V`/`L`/`N` lines. Fixtures go in
`corpus/evaluate/`, and a ci/check.sh gate requires `--evaluate` = `--brute` = the golden for each.
Measured: states, worlds and time against h and the number of belief groups. Each fixture's belief is chosen
small enough for `--brute`:
- **wgc** (metis-catalog `domains/wgc`): a categorical belief over each item's starting bank, `on(X, A)` with
  `one: A`. Queries: `risk gone(_)` and `reach solved` within h, under the program's uniform choices.
- **bridge-torch** (`domains/bridge`): a categorical belief over the torch's starting side, `torch(S)` with
  `one: S`. Query: `reach solved within 20`, and the wick sweep 13/14/15 as three cases (the §8 enumerator in
  miniature).
- **kitchen_pot's cook_a** (spec 15's fixture): independent beliefs on the grant `tick__grant(cook_a, pot)`
  (will this tick's world give it the pot) and on `order` (does an order wait). `pot_space` is a count (three
  atoms), not a presence, so it stays in the init. Query: `reach tick__done(cook_a)` within h.

**The rulings (the architect, 2026-10-25).** 1 yes: the manifest; the certificate key covers the canonical line
of `beliefs:`, `levels:` and `evaluate:`. 2 yes: the instrument answers [lo, hi] and prints the cut mass; the
REPL's `query` keeps refusing. 3: both forms legal, the certificate tells them apart (§8); alfworld's `go_for`
is not changed by the spec. 4 yes: rationals as the referee, binary64 later with a stated bound; step 2
reports the digit growth. 5 yes: events for step 2, `within h cone` later, a tick-based horizon when step 3's
world model fixes a tick (§5). 6 yes: `--evaluate`, `--brute`. The §8 cell sweep is specified, not built in
step 2; the belief-read notes and the bwd refusal are required outputs.

**The questions as they were put.**
1. **Manifest, not grammar**, for `beliefs:` and `levels:` (§2): agreed? Then the program_key never moves for a
   belief, and the certificate key covers their canonical line.
2. **The budget cuts to an interval** (§6.3) instead of refusing as the REPL does: agreed? The REPL's
   `query` can keep refusing; the instrument answers [lo, hi].
3. **A choice weight that reads a belief port** (§8): certify only presence-only beliefs, and list the rest
   `uncertified`? Or require the decision to read a belief LEVEL with static weights, which changes the
   alfworld task's `go_for` (`@w look`) in step 3?
4. **Exact rationals as the referee** (§6.4): agreed, with binary64 a later fast path?
5. **The horizon counts events** (spec 06), not cone steps (spec 11's interleaving-insensitive readout): agreed
   for step 2, with `within h cone` a later option?
6. **The CLI name** `metisc --evaluate`, with `--brute` as the referee flag: keep?

## 12. Step 2 as built (metisc, branch spec16-instrument)

- **`src/rat.ml`** is the exact arithmetic: naturals in base-2^24 limbs (Knuth's division, Euclid's gcd),
  reduced rationals, the shortest-round-trip decimal intake, and correctly rounded conversion to binary64.
  It agrees with Python's `Fraction` on 300 random cases, the conversion included.
- **`src/evaluate.ml`** is the instrument:
  - the groups (R1: a group no event touches and no query mentions is dropped, after its sum is checked);
  - the deferred draws (R2: per stage, the groups its clauses or links touch, plus the query's groups at
    step 0);
  - absorption (R3), merging (R4), the canonical-order cut;
  - `--brute`, the `N`/`L`/`X` lines and the refusals.

  R5 (the cone) is not built (later, ruled). Step 2 built the embedded case form (`#belief`, `#port`,
  `#evaluate`, `#expect`, `#level` in an `.llp`).
- **Step 2b (branch spec16-reader)** adds the case-YAML reader. `Evaluate.case_of_yaml` reads a case and its
  manifest into the same directives, through `Iface.read_yaml_block` (spec 15's subset plus block mappings;
  the composition reader stays strict, and its `yaml_block` refusal is unchanged).
  - Every embedded fixture is also a case (`corpus/evaluate/<name>.yaml` the manifest,
    `corpus/evaluate/cases/<name>.yaml` the case). Its listing equals the embedded golden byte for byte.
  - Five case-only fixtures:
    - `wgc_lone`, a `lone` belief: the goat on neither bank with 0.1, 3 worlds, lose = 31/60, `--brute`
      equal;
    - `cook/cases/served`, the `cases/` → `../domain.yaml` convention, with a query the case adds;
    - `port_function`, `port_unknown`, and a refused case key.
  - Gate 14: `EVALUATE 27/27 (16 case YAMLs, 16 goldens)`.
- **The gate:** ci/check.sh gate 14, `EVALUATE 11/11`. Five fixtures with beliefs (wgc_bank, bridge_w15/14/13,
  cook_a_pot) and six refusals (`belief-bwd`, `belief-init`, `belief-port`, `belief-sum`, `port-unbound`,
  `level-type`). Each listing and exit code equals its golden, and every exact `V` line equals `--brute`'s,
  as a rational.
- **An independent check:** metispy's `ForwardProjection`, run on each world and mixed by hand, gives every
  fixture's number to binary64 (wgc's three, bridge 15/14/13, cook_a).

**The cost table** (CPU, one core; `--cost`; brute where it finishes):

| program | varied | states (`--evaluate`) | paths (`--brute`) | worlds | result digits | ms evaluate / brute |
|---|---|---|---|---|---|---|
| wgc reach solved, 3 groups | h = 8 / 14 / 20 / 30 | 94 / 191 / 290 / 455 | 66 / 397 / 1,194 / 14,770 | 8 | 4 / 5 / 5 / 6 | 0.9 / 1.2 … 2.4 / 71.8 |
| same | h = 40 / 60 / 80 | 619 / 950 / 1,279 | — | 8 | 9 / 14 / 18 | 2.7 / 4.1 / 5.3 |
| wgc risk gone(_) within 20 | groups 0 / 1 / 2 / 3 | 90 / 126 / 203 / 207 | 58 / 216 / 457 / 885 | 1 / 2 / 4 / 8 | 4 / 6 / 6 / 8 | ≤ 1.7 / ≤ 7.5 |
| bridge w15 reach solved | h = 5 / 10 / 20 / 30 | 161 / 290 / 312 / 312 | 367 / 1,349 / 1,408 / 1,408 | 2 | 1 / 21 / 21 / 21 | ≤ 5.2 / ≤ 14 |
| coins: K beliefs read in ONE stage | K = 4 / 6 / 8 | 256 / 4,096 / 65,536 | 896 / 108,672 / 24,350,720 | 2^K | 6 / 8 / 11 | 2.9 / 4.3; 47 / 245; 1,134 / 66,093 |
| same | K = 10 / 12 / 14 | the budget (500,000): cut to [lo, hi] | — | 2^K | — | 9,471 / 6,675 / 5,507 |
| walk, rule weights 0.7 / 0.3 | h = 25 / 50 / 100 / 200 / 400 | 364 / 1,132 / 2,682 / 5,782 / 11,982 | 10,674,093 at h = 25 | 2 | 22 / 48 / 99 / 201 / 403 | 3.1 (brute 38,181) / 17 / 71 / 348 / 2,220 |

- **Merging is what pays.** Paths grow exponentially in h; states grow about linearly on these programs.
- **Groups read in one stage multiply the worlds.** R2 cannot defer them, and the cost is 2^K worlds times
  the program's own states. Deferral pays only when the groups are met in different stages or not at all.
- **The digits grow linearly in h under non-dyadic weights** (about one per step for 0.7 / 0.3), and the time
  per state grows with them: 11,982 states in 2.2 s at 403 digits. That is the price of the rational referee,
  and the reason for a binary64 fast path later.
- **A cut interval's upper end is weak** when misses are known only at h: wgc's `win_cut` at budget 60 is
  [1/16, 1], its exact value 1/12. The lower end is the work done; the width is what the budget hid.
