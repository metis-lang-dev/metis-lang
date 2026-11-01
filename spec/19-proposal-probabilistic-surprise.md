# PROPOSAL 19 — probabilistic surprise: the per-choice-point accumulator, the rate test, aleatoric and epistemic

**Status: DRAFT 2026-11-01 (the architect, at the user's ask: "non-matching probabilities are also a surprise … I cannot define the rule or distance that says the model's output is surprising in the probabilistic sense"; "a per-state accumulator would be a good metric of our model's fitness"; "on which state are we doing the probability fitting?"). Nothing here changes a runtime or a writer: the statistic is a REPLAY-TIME instrument over the trace (spec 17 am.7, trace-replay s-c111ff41), the proposal it leads to is a port reparametrization (spec 18 §2.1), and the hand-over conditions of the loop's policy (metis-loop POLICY.md: out of vocabulary, contradiction) get their probabilistic form. Mechanization: §8, a Lean statement to follow in `formal/`.**

## 0. In one table

| question | answer |
|---|---|
| what is surprising, probabilistically | not a low-probability outcome but MORE evidence against the stated rates than the model itself expects: the accumulated log Bayes factor at a choice point exceeds log(1/δ) |
| on which state | the CHOICE POINT: the set of enabled rule instances at a draw and what their weights read; never the whole fact multiset (it never repeats) |
| the statistic | S = log P(counts \| rates unknown, Dirichlet(α)) − Σ n_x log q_x, per choice point, since the last accepted change |
| the one parameter | δ, the false-surprise rate; S ≥ log(1/δ) is a surprise; valid at any stopping time (a test martingale under q) |
| the deterministic surprise | the same rule with q_x = 0: S = ∞ on one record |
| what the surprise does NOT say | wrong rate or hidden variable; §4's residual test tells |
| the proposal it leads to | first a reweighting (a weight port's value, no rule moves), then a conditioning on a declared fact, then a new fact (a person's) |
| the fitness of a domain on a run | Σ over choice points of S, beside the deterministic surprise count; §6 |
| aleatoric vs epistemic | relative to the projection: aleatoric is the residual no conditioning over the host's facts removes; §5 |

## 1. Motivation: the second half of the loop

The loop's policy (POLICY.md) handles the LINEAR half: a refused command or an effect the facts contradict is a surprise record, one proposal per record, and two conditions hand over to a person: out of vocabulary (the same before-facts, different after-facts: no rule over the observed facts fits both records) and contradiction (two accepted rules consume one goal in one state: stage order decides, not law).

The language's other half samples. Where competing rules carry weights (`@w`, weight ports, spec 00 §3; categorical ports, spec 16), two rules enabled in one state is a MIXTURE, not a contradiction: the kernel draws among the enabled instances by their weights and the data decide the rates. Then "non-matching probabilities" is a surprise too, and a weight that the world refutes is as much a model error as a missing premise. What was missing is the DEFINITION: which quantity, on which state, over which threshold, that fires on a wrong rate but not on one unlucky draw, under the loop's habit of looking after every beat.

The contradiction hand-over keeps its place for the linear reading: law rules with no weight, where stage order silently picks (the road's safety stage sits before progress for that reason). For weighted rules the honest move is a weight port, and fitting its rate is a proposal the loop can make itself, gated like a rule.

## 2. The choice point

**Definition.** At a beat the kernel has the set E of enabled rule instances (rule name and binding). The weights w(e) of e ∈ E are functions of what the weight ports read at that beat (facts, readings). The draw is one e ∈ E with probability q(e) = w(e) / Σ w. The CHOICE POINT c is the pair (E up to the bindings the weights depend on, the values the weights read). It is the state at which q is DEFINED, so it is the state at which counts mean anything.

**Why not the state.** A linear state (the whole multiset) never repeats; counts stay at one. The kernel's draw does not depend on it: given c, the draw is independent of everything else. That is the model's conditional-independence claim, and §4 tests exactly that claim.

**Granularity.** c is coarse enough to repeat (the same yields compete at every junction approach; the same cook's alternatives at every pot) and fine enough to localize: each term of the accumulator names the weight to move. Two draws are "the same choice point" when E matches after renaming the bindings the weights do not read.

**Two things are fitted, both at choice points.** (a) The model's own choice among its rules (the planner's alternatives). (b) The world's answer given an action: which effect rule the world "chose" (the host-acted worlds of rddl-watch, the belief's hazard table on the road). Form (b)'s choice point is the action instance and the effect rules enabled for it. The statistic is the same.

## 3. The statistic

For a choice point c, since the last accepted change of any rate it reads, N draws with counts n_x over the alternatives x (k of them) against the stated q:

```
S(c) = log P(n | θ ~ Dir(α))  −  Σ_x n_x log q_x
     = log [ Γ(kα) / Γ(kα + N) · Π_x Γ(n_x + α) / Γ(α) ]  −  Σ_x n_x log q_x
```

The first term is the marginal likelihood under a Dirichlet prior with symmetric α (α = 1/2, the Krichevsky–Trofimov estimator of universal coding: no fitted parameter). The second is the log-likelihood under the stated rates.

**The rule.** S(c) ≥ log(1/δ) is a probabilistic surprise at c. δ is the one parameter, the false-surprise rate a domain accepts (δ = 0.01: one false surprise in a hundred choice points that are in fact right).

**Properties.**
1. *Unifies the two kinds.* An outcome with q_x = 0 gives S = ∞ on one record: today's deterministic surprise is the special case. A wrong rate gives S growing as N · KL(p ‖ q) − O(log N): a badly wrong weight is caught in a few draws, a slightly wrong one takes many.
2. *Honest under constant looking.* The loop checks after every beat. A fixed-sample test lies under that (repeated looking always finds a crossing). exp(S) is a nonnegative martingale under q with expectation 1, so by Ville's inequality P_q(sup_N S ≥ log 1/δ) ≤ δ: the threshold holds at ANY stopping time, including the loop's.
3. *Additive and local.* S of a run is Σ_c S(c): the total splits into the choice points, and each term names the weight port, the rule set and the bindings.
4. *Resets on acceptance.* A reweighting accepted at c starts c's counts afresh (the old counts are the evidence that produced the new rates; counting them again is double use).
5. *A single draw cannot fire it* unless q_x = 0: for N = 1, S = log(1/q_x) − log k at most, below log(1/δ) for any q_x > δ/k.

## 4. After the surprise: wrong rate or hidden variable

S says the stated rates are refuted; it does not say why. Two causes, told apart by the RESIDUAL after refitting:

1. Refit θ̂ = (n + α) / (N + kα) at c. If the draws at c are exchangeable under θ̂ (no column of the trace predicts them: not the previous draw, not the tick, not another member's fact, not the beat's inputs), the world is random there and the weights were the fix: a **reweighting** proposal, the weight port's value in the plan (spec 18 §2.1: a port value, no rule moves; the receipt shows no program hash moved).
2. If some column z of the trace predicts the draw at c beyond θ̂, the same statistic says so: S(c, z) = the Bayes factor of "rates depend on z" against "rates do not", i.e. §3's formula on the counts split by z against the pooled θ̂. A crossing names z. Then:
   - z is a fact the projection already has: a **conditioning** proposal, the weight port reads z (a rule's weight becomes a function of a declared fact; the loop can propose it, the gate judges it on the composition replay);
   - z is not in the vocabulary (the trace's tick, a world column the host does not project, another member's fact): **out of vocabulary**, the hand-over, in its probabilistic form; a person adds the fact to the projection (a class-layer change that touches every consumer of a family).

**The ladder, each step only on evidence:** constant rate per choice point → rate conditioned on a declared fact → a new fact. The linear policy's "refused twice → explore" has its counterpart: a reweighting refused by the goldens twice at c sends the loop to §4.2 before another guess.

## 5. Aleatoric and epistemic, relative to the projection

The split is not absolute. **Aleatoric** is the residual that the best conditioning over the facts the host projects cannot remove (§4.1: exchangeable under θ̂). **Epistemic** is everything conditioning removes (§4.2). The hidden-variable test is the instrument that moves mass from one side to the other as the vocabulary grows. With that, the four places where uncertainty lives in a running domain (the road as the example):

| place | kind | treatment | fitted how |
|---|---|---|---|
| perception (where a mover is, under occlusion and misses) | epistemic | the cell belief (semantic-world `road`, `bayes`) | calibration: a track's prediction at t scored by its own later detection at t+h; needs no truth, runs on the trace and on a real car |
| the others' choices (what the other driver will do) | aleatoric to us | twice, on purpose: the planner side keeps the intent belief and the hazard readings (a probability, spec 16's categorical port); the shield side uses NO probability: RSS bounds the worst the other can do within its class's dynamics | the readings by §3 on the belief's groups (form (b)); the bounds as QUANTILES of the observed decelerations per class; a bound crossed in the log is the shield's surprise (the undue/abrupt brake counts) |
| the law and the car's own rules | epistemic | deterministic surprise, the loop's on the trace; no probability wanted (a yield fires, it is not sampled) | POLICY.md as it stands |
| the car's choices among alternatives | the gate of §2 | the accumulator | §3, §4 |

A rule that bounds (RSS) and a rule that weighs (the planner) coexist because they answer different questions: the bound answers "what must never happen", the weight "what to prefer". The responder stays the shield whatever the weights say.

## 6. Fitness of a domain on a run

The fitness report of a run (a trace) has two numbers and a list:

```
fitness: {deterministic: <count of surprise records>, probabilistic: Σ_c S(c),
          worst: [(c, S(c), N, q, θ̂, z?) …]}            # the choice points over log(1/δ), worst first
```

Σ_c S(c) is in nats of evidence against the model; 0 is a model whose rates the run does not refute. It is comparable across runs of one composition at one image, not across images (the choice points differ). The certificate (spec 17 am.7) gains the line `rates: Σ S, k choice points over δ` beside open-loop and closed-loop.

## 7. What it needs in the toolchain

1. **The draw in the trace.** The trace records fired rows (the drawn instance) but not the enabled set E nor the weights' values. The composition replay REGENERATES both (it reruns the kernel on the image with the recorded inputs and the checkpoint's RNG), so the accumulator is a replay-time instrument in `metis.trace` (`metis.trace rates TRACE --delta 0.01`): no writer change, no protocol change, old traces serve.
2. **Choice-point identity.** The kernel exposes, per draw, E with bindings and each weight's read values; the instrument canonicalizes (§2) and keys the counts.
3. **The proposal.** A reweighting is a plan value (spec 18 §2.1): `pi propose --pack` with a `weight` line (no rule) judged on the composition replay like any pack: the receipt shows no program moved, the goldens hold (a golden that pins a seed replays with its RNG, so a changed rate shows as a fired difference there: a golden written on a sampled path is a question, a person may overrule, as ruled). A conditioning (§4.2a) changes the weight's `reads`: a program change, one member, the receipt as for a rule.
4. **The categorical ports** (spec 16) are the same counts over a belief group: the host binds a distribution, the world shows one outcome per beat; §3 on (group, read values) is the belief's calibration. The one-tick instrument of spec 16 §10 already evaluates f once per horizon; the accumulator keys on the group's read values.
5. **A family** (spec 18) is fitted PER CONSUMER: the weights are the consumer's plan values, the choice points are the consumer's compositions'. A rate that both consumers refute in the same direction is a family default to move; the gate is both consumers' goldens, as for a rule.

## 8. Mechanization

Statement for `formal/`: for a fixed choice point with stated q and the KT mixture M_N(n) = ∫ Π θ_x^{n_x} Dir(θ; α) dθ, the process Z_N = M_N(n) / Π q_x^{n_x} is a nonnegative martingale under i.i.d. draws from q with Z_0 = 1; hence P_q(∃N: Z_N ≥ 1/δ) ≤ δ (Ville). The draws at a choice point are i.i.d. under the model by §2's conditional-independence claim, which is what §4.2 tests. A `Formal/Surprise.lean` with the martingale property and Ville's inequality follows the belief file's pattern (`Formal/Belief.lean`); the architect's task.

## 9. Open

- α: 1/2 (KT) by default; a domain with few alternatives and few visits may prefer α = 1 (Laplace); stated per domain in the manifest, never fitted.
- δ: per domain in the manifest (`surprise: {delta: 0.01}`), the same for every choice point; a per-rule δ is a design smell (it hides a known-bad rate).
- The columns z that §4.2 tries: the beat's recorded inputs, the previous draw at c, the tick modulo small periods, the other members' facts at the beat; bounded, listed in the report; anything else is a person's hypothesis.
- Sampling order inside a stage: where the kernel's choice is not a weighted draw but first-enabled, there is no q and §3 does not apply; that is the linear contradiction of POLICY.md, kept.
