# PROPOSAL 20 — surprise kinds: the open world, the four kinds and their responses, what a weight means, what is certified

**Status: DRAFT 2026-11-05, amended the same day with the CONFUSION kind (the user: a person marks an event, hears the narration, agrees = pass, disagrees = a fragment with no surprise of its own but a misalignment: "either user or domain has confused the interpretation of state of affair") (the architect, at the user's ask: "An atom not existing in your domain does not necessarily mean the corresponding thing does not exist in the world. It means your current ontology cannot represent it. This is an open-world problem, and I think your surprise mechanism is a natural way to handle it … I would distinguish at least four types of surprise"; with three questions to answer in the design: how an unknown concept is told from a known one poorly observed; what a weight on a clause means when proofs combine; what the compiler certifies and what it does not). Nothing here changes a runtime or the grammar: the kind is a field of the surprise record, decided by a replay-time triage over the trace's three columns (§4), and it ROUTES the record (§5). The worked examples are the six records of road-scenarios s-e23be780 (§9), where this session answered every kind by hand before it had the names.**

## 0. In one table

| kind | what the trace shows | the response | who writes it |
|---|---|---|---|
| **ontological** | the thing is in the world's truth; no atom of the member's unit can name it | new vocabulary: a pred and its host contract, then clauses over it | the host contract by hand with the architect's word; the clauses through the judge |
| **structural** | every atom the words need exists and holds at the window; no rule's guard is met, or one is a guard away | a new clause or a widened guard: the pack | the loop (the paid one for a non-obvious pack, the agent through the judge for an obvious one) |
| **probabilistic** | the atoms exist and flip inside the window, a belief level is low, or two hosts disagree on one scene | the fold's bounds, a weight, a belief or a sensor parameter; never a rule | a port value or a host parameter, a person's word |
| **computational** | a budget was the stopping reason | the grounding form, a role count, a horizon, the budget itself (spec 14) | the architect |
| *(world)* | the truth has no such thing either: the simulation cannot hold it | a world capability (a net rebuild, a body the director carries) | the world's owner, by hand |
| *(evidential)* | the record's own evidence is misread: two agents read one trace two ways | a sharper record: no filler facts, the three columns side by side | the triage (§4), no proposal |
| **confusion** | a person marked a fragment, heard the system's narration of it, and still disagrees; the columns hold no surprise of their own | the fragment kept with both readings; then §4 on the person's words: a misaligned person (the narration teaches) or a misaligned domain (one of the kinds above, found through the person's words) | the person marks and judges; the triage classifies; a law disagreement is the person's to rule |

The paid loop runs on ONE row, the structural one, which is also the only row where a rule is the answer. Every other row today ends as "another rule" unless the kind is named first.

## 1. Motivation: the open world, and this session's evidence

Spec 19 gave the loop its probabilistic half: a wrong RATE is a surprise. What is still missing is the kind that is neither a missing clause nor a wrong rate: the world holds a thing the ontology cannot name. The language reads the world through a PROJECTION (the host's facts over the family's vocabulary; rule 2: geometry in the host, classes in the rules), and a projection is a closed vocabulary by construction. A fact that is not stated is, to the rules, false. That is the closed-world reading, and it is right for the rules (a rule needs a decidable premise) and wrong for the record: the absence of an atom says the ontology could not place the thing, not that the thing was absent.

The user's framing (2026-11-05): the robot observes a new kind of door; the semantic map cannot classify it; the domain has no applicable predicate; the engine cannot derive the action; surprise. The larger model then decides WHICH of five things is needed: a new predicate, a refinement of one, a new clause, a change to the semantic map, a new perception capability. "This is much more useful than treating every failure as a request to generate another rule."

This session's six records are the evidence that the loop as built would have produced a rule for each, and that each wanted something else:

| record | what the loop would have written | what was needed |
|---|---|---|
| lane stay 463d7d (the ego stays in a bidirectional centre lane after a pass) | a rule "change back" over the atoms it had | the net's lane KINDS as vocabulary (the loader never read them), then three short clauses |
| priority taker 503be4 (the ego does not brake for a car that takes its priority) | a responder rule | nothing in the rules: the fold's rule 5 is there, its two bounds never overlap (§9) |
| the SUMO/exerciser disagreement on 503be4 | a rule for one world | a sensor range: 60 m against unlimited, now 100 m on both hosts |
| planner `brake_cross` never firing on 503be4 | a rule | a guard a fact away: `cross_overlap` wanted, `cross_unsettled * late * zprio(ego)` present |
| walkers (cards 8, 27, 30, 37) | — | the net has no sidewalks: a world capability (ruled: bodies the director carries) |
| the "typed late" reading of 503be4 (nina, one round) | — | the fact builder's FILLER for an unfilled role read as a typing (§2) |

## 2. The open-world principle, and the closed-world leak

**Principle.** An atom's absence from a member's facts means one of three things, and the record must say which: the thing was NOT OBSERVED (the host saw nothing there), the thing was observed and projected as NOT THIS (a class the ontology has, negatively), or the thing was observed and the ontology has NO CLASS for it. The rules may read all three as "the premise fails"; the triage may not.

**The leak, found this session.** `road_facts` states, for a role nobody fills, `type(a1, not_relevant)`, `safe_long(a1)`, `safe_lat*(a1)`: filler so the planner's rules have an atom to read. That is negative knowledge asserted where there is none. It cost a review round (a standing crosser read as "typed not relevant from t 0" when the host had never seen it) and it is exactly the sentence above: the car was there, out of the sensor's 60 m, and the ontology wrote "not relevant, safe".

**Rule (vocabulary, by hand).** A role the host does not fill gets NO class fact and no safety fact. If a rule needs an atom to read for the empty case, the atom is the honest one: `role_empty(a1)` (or `type(a1, none)` with `none` a kind the rules never read as safe). `not_relevant` is reserved for a mover the host SAW and classified as not interacting. The exerciser and the SUMO host state the same. This is a projection change (a vocabulary decision), the cheapest item in this spec, and it makes §4's first test decidable from the facts alone.

## 3. The kinds

**Ontological.** The world's truth holds a thing (an object, a relation, a situation) and the member's unit has no predicate whose extension could hold it. Marks: the surprise's words name it with a word no atom of the unit names; a pack for it is refused at the LINK on an unknown atom (today the refusal reads as a syntax error to the model, and the planned language RAG would answer it with the spec paragraph and the nearest well-formed rule, which is the wrong help for this kind); the host has no fact for the thing at any tick of the window while the truth (T10) has it. Two sub-kinds, both ontological: a NEW predicate (the lane kind, the emergency vehicle's "a vehicle from behind with priority", the oncoming lane "lent" for a pass) and a REFINED one (a predicate that exists but lumps: `type(…, not_relevant)` covering both "unseen" and "seen, not interacting").

**Structural.** The predicates are there and the facts hold at the window; no rule is enabled, or the wanted one is a guard away. Marks: the record's atoms are all declared in the unit; T8 `fired` shows no command rule at the window; a rule of the member's stage has every premise but one satisfied at some tick of the window (the "one guard away" listing, §7). This is the loop's home ground and the only kind a clause fixes.

**Probabilistic.** The predicates are there and the facts are UNSTABLE or UNDERDETERMINED: a fact flips within the window with no world event behind it (a one-tick safe history deciding blame), a level port reads its lowest level, two hosts disagree on the same scene (SUMO braking where the exerciser does not, on one card), a bound the fold holds the ego to is crossed (spec 19 §5: the shield's surprise), or spec 19's accumulator crosses log(1/δ) at a choice point. The response is never a rule: a weight (spec 19), a belief (spec 16), a fold bound or a sensor parameter (a port value, spec 18 §2.1), or the hidden-variable ladder's last step (spec 19 §4.2), which turns the record ontological.

**Computational.** The run stopped on a budget: the grounding bound Π|τ| over the domain's budget (spec 14 §1), the case's `steps`, the instrument's state budget (spec 16 §6), a proposal's spend cap, the loop's beats. The response is a form change (roles for cells, a static table for a pred, spec 14), a horizon, or the budget; the compiler can report the first (spec 14 P11, the cyclic-guard listing) and the runtime the rest.

**Confusion (the user, 2026-11-05).** The kinds above are read off the trace. This one is read off a PERSON. The road interface lets a person mark an event's beginning and end while the run plays (`world/mark` rows in the trace's `marks.jsonl`, with what the person said; `Workspace.marks` turns them into windows); the chat narrates a window (`narrate k0..k1`: the Tick table in prose) and explains it (`explain`: `trace_fired` and `trace_blame`, three lines). Two outcomes:

- the person hears the narration and AGREES: a pass. The mark closes with the narration attached; nothing is recorded as a surprise (the system's account of its own behaviour was accepted; the fragment may still be kept as a teaching example);
- the person still DISAGREES: the fragment is kept (`keep_window`, past the writer's ring) as a record of kind **confusion**: it holds no deterministic or probabilistic surprise of its own (no refused command, no flipped fact, no crossed bound), it holds a MISALIGNMENT between the person's reading of the state of affairs and the system's. Either the person or the domain has the interpretation wrong, and the record does not say which.

The response is the triage of §4 run on the PERSON'S WORDS instead of the system's: the words name a thing no atom names → ontological (the person's concept is missing: "it should have let the bus in" where the vocabulary has no bus lane); the words name atoms that hold and a response the rules do not give → structural (a law disagreement: the rules did what they say and not what the person expects; that is the person's to rule, through the human gate, and a candidate pack only after the ruling); the words contest a fact ("that car was never dangerous") → probabilistic (a bound or a belief) or perception; the words are answered by the facts and the law as narrated → the person was misaligned, and the record closes with the narration as its answer and a note for the narrator (what was unclear). Confusion is therefore the ENTRY kind for alignment: it is the only kind that originates from a person, and its triage ends in one of the others or in a better narration. A fragment that produces the same confusion from several people is a narration or vocabulary defect even when the domain is right.

**Outside the four.** A WORLD capability gap: the truth itself has no such thing, because the simulation cannot hold it (no sidewalks in the net, no occluders in a host). It is not a surprise of the domain and no proposal follows; the record names the world and stops. An EVIDENTIAL surprise: the record's readers disagree about what the trace shows; the response is a better record, and §4's columns are designed to make this one rare.

## 4. Classification: the three columns

**The question (the user's first).** How is an unknown concept told from a known one that is merely poorly observed? The answer is that the trace has THREE columns, and the kind is a comparison across them, never a judgment on one:

- **truth**: the world's own state (the host's snapshot, T10 `truth`; the exerciser's bodies, SUMO's vehicles), independent of what the ego perceives;
- **facts**: the member's facts at each tick (the projection: perception, then the fold, then the fact builder);
- **law**: the rules enabled and fired at each tick (T8 `fired`, and the "one guard away" listing).

**The procedure**, in this order, each step decided by a test on the columns, the first that fires names the kind:

0. **confusion**: the record comes from a person's mark and the columns hold no surprise of their own (no refused command, no flipped fact, no crossed bound, no budget). Narrate the window first; on agreement the mark closes as a pass. On disagreement the record is kept as confusion and the steps below run on the PERSON'S WORDS (§3), ending in one of the kinds or in "narration" (the person was misaligned).
1. **world**: the thing the words name is in NO column, truth included → a world capability gap. (The walkers.)
2. **ontological / perception**: the thing is in the truth and in no fact at any tick of the window. Then two cases, told apart by the unit's SIGNATURE: if the unit has a predicate whose type could hold the thing (a `mover` role for a car, a `side` for a lane), the host failed to PROJECT it → the semantic map or the perception (the sensor's range, an occluder, a relevance rule): a host parameter or a host fix, by hand; if no predicate's type can hold it → **ontological**, a new or refined predicate. (The 60 m range was the first case: `a1` can hold a car; the lane kind was the second: no predicate could hold "bidirectional".)
3. **probabilistic**: the thing is in the truth and in the facts, and the facts FLIP inside the window without a truth event between the flips, or a level is at its floor, or a second host's facts on the same truth differ, or a fold bound is crossed, or spec 19's S crosses. (Blame decided by one tick of safe history; the SUMO hold against the exerciser's collision.)
4. **structural**: truth and facts agree and are stable; no rule fires; the one-guard-away listing is non-empty or the words name a command the stage has no rule for. (`brake_cross`.)
5. **computational**: the run stopped on a budget before any of the above could be read.
6. Otherwise **evidential**: the record cannot be classified from its columns; the triage asks for the columns it lacks (a truth snapshot, a second host, a longer window) and makes no proposal.

**Why the signature decides step 2.** "Poorly observed" and "unknown" look the same in the facts column (nothing there). They differ in whether the ontology COULD have said it: a car beyond the sensor is an `a1` the host did not bind; a bidirectional lane is a `side` whose KIND no atom carries. The signature is static and the truth column is the world's, so the test needs no model's opinion. When the truth column is missing (a real car, no snapshot), step 2 cannot run and the record is evidential until a second observation (another run, another sensor) supplies it; the triage says so instead of guessing.

**The refinement case** (an existing predicate that lumps) shows at step 2 as a predicate that CAN hold the thing but whose value is the same for two things the words tell apart (`not_relevant` for the unseen and for the seen-but-passive). The test: two truths, one fact value, different outcomes → refine (split the kind). The leak of §2 is the instance.

## 5. Responses and routing

| kind | proposal form | gate | spend |
|---|---|---|---|
| ontological, new predicate | a `pred` declaration with its namespace and host contract (what the host states, when, from what), the host's projection, then the clauses as a pack over it | the architect's word for the vocabulary (projection by hand); the judge for the clauses; the catalog's cases | 0 USD for the vocabulary; the clauses as structural |
| ontological, refinement | a kind split (a type gains a value; the host states it) and the rules that read the old value re-read | the same | the same |
| perception / semantic map | a host parameter (sensor range, occluders, relevance of standing movers) or a host fix | the architect's word; both hosts move together; the tables rerun | 0 USD |
| structural, obvious | the pack, written by the agent directly, through the judge | the judge's cascade (L1–L12, T-verbs, family/invariant, goldens) | 0 USD |
| structural, non-obvious | the pack through the paid loop | the same | the loop's cap |
| probabilistic, rate | a weight port's value (spec 19 §7.3) | the composition replay, goldens | 0 USD |
| probabilistic, bound or belief | a fold bound, a belief parameter, a level threshold: a port value | the trace's T-verbs on the regression cards; a person's word where the bound is a safety bound | 0 USD |
| probabilistic, hidden variable | spec 19 §4.2's ladder; its last step is an ontological record | as above | — |
| computational | a form, a role count, a budget | spec 14's measured gains | 0 USD |
| world | a world capability, recorded; no proposal | the world's owner | — |
| confusion | the fragment kept with the person's words and the narration they rejected; then the row of the kind §4 finds on the words, or a narration fix (the narrator's words, the Tick table's vocabulary) | the person's agreement closes it; a law disagreement goes to the human gate before any pack | 0 USD (the narration is the loop's own words) |

**Routing rule.** The paid loop takes a record only when its kind is structural. A record of another kind that reaches the loop is returned with its kind and the response form; the loop never writes law around a hole in the vocabulary. The obvious-fix rule (the user, 2026-11-05) is the structural row's cheap half.

**Rule 2, restated for the kinds.** Geometry and perception belong to the host, so every ontological and perception response begins in the host and the architect's word is needed there; classes belong to the rules, so the clauses over a new predicate go through the judge like any pack. A kind decides WHERE the change starts, not who may skip the gate.

## 6. What a weight means (the user's second question)

**The semantics, as the paper has it.** A ground program denotes a stage-gated mass-action stochastic Petri net (paper Def., Theorem `image`): each rule instance is a transition with a rate constant w ∈ ℝ⁺ (`@w`, prior 1.0 when absent; a weight port makes w a function of what the port reads). At a marking, the transition's PROPENSITY is w times the mass-action count; the kernel draws one enabled instance with probability w / Σ w over the enabled set, per step, normalized (the choice point of spec 19 §2). A run's measure is the product of its steps' normalized choices, and for the class C it factorizes over the sites visited (Theorem `trace`): the measure lives on the occurrence net, not on the interleaving.

**So a weight is a RATE, and at a choice point a PREFERENCE.** It is not confidence in the clause, not the probability that the clause is true, not a likelihood of its premises. The clause's truth is linear and binary: a rule is enabled or it is not; a transition the world refutes outright is spec 19's q = 0, S = ∞ on one record. Two readings of the same number, by what competes:

- form (a), the program's own alternatives at a choice point (the planner's rules): w is the program's preference among what it may do; spec 19 fits it to how often each was the right thing;
- form (b), the effect rules of a host-acted world (which effect the world "chose" for an action): w is the world's rate, a likelihood in the ordinary sense; the same statistic fits it.

The two never mix in one choice point, because a stage's rules are one member's and the world's effects are the world's.

**Where confidence lives.** Confidence about the WORLD (what is there) is a belief, and the language keeps it out of the weights on purpose: spec 16's categorical port binds a distribution over a group of mutually exclusive facts, the instrument draws the world, and the program's weights act in the drawn world. The total probability of an outcome multiplies the two factors (Theorem `mixture`: a port is a mixture), in the instrument, never in the IR. A level port quantizes a belief into a finite atom the rules read. So "how sure am I that this is a door" is a belief fact with a level, and "what do I do at a door" is a rule with a weight; a weight that encodes doubt about a fact is a design error, and spec 19's hidden-variable test is how it shows (the rate depends on a column the rules do not read).

**Combining proofs.** Along one run, choices multiply (the measure of the run). Across runs that reach the same outcome, measures ADD: P(outcome) is the sum over runs, which is what the sum-product instrument of spec 16 §6 computes over the reachable support (Theorem `filter`: the forward filter equals the DBN's exact marginal). Two "proofs" of one outcome are therefore not two pieces of evidence to be weighed against each other; they are two paths whose masses sum. A rule's weight contributes to that mass exactly through the normalized choice at each step it wins, nothing else. Where a user wants Dempster–Shafer-style or Bayesian confidence combination over clauses, this language says: that is a belief over facts, state it as one.

**Consequence for the kinds.** A probabilistic surprise is never "the clause is less true than we thought". It is one of: a wrong rate (spec 19, a weight moves), a wrong belief (spec 16, the host's distribution or a level threshold moves), a wrong bound (the fold's RSS parameters, a port value), or a fact missing from the projection (spec 19 §4.2, which turns the record ontological).

## 7. What is certified, and what is not (the user's third question)

Three layers of guarantee, distinct in kind:

**A. Semantic (theorems, mechanized in `formal/`).** What the interpreter runs is what the theorems govern: run-level preservation (Theorem `preservation`), the forward filter is the exact marginal (`filter`), the denotation onto stage-gated SPNs is total and injective up to structural congruence (`image`), the measure factorizes over sites (`trace`), a port is a mixture (`mixture`). These say the probability the instrument reports is the probability of the program. They say nothing about any DOMAIN property.

**B. Structural, static (the compiler, every build).** Per catalog and entry: typing and containment (spec 00 §6: namespaces, consume/produce rights per layer, bwd never a resource, the Horn world closed, guards on bwd only); `family-produced` (a rule never writes a host family member: the host's exclusive readings are read-only to the law); `invariant-broken` (a declared linear P-invariant holds in every reachable marking once the init holds N: a theorem of the net, checked per rule as a token delta of 0; a pack is checked against its base's invariants); spec 15's interface checks I1–I7, of which I5 is the one that bears on actuators: EVERY RESOURCE OWNED ONCE, Δ(p) + Σ Δ(held) = 0 for every rule that mentions the resource or its holders, and only the direct member consumes it. The lints L1–L12 are warnings in this layer.

**C. Behavioural (the traces, every run).** A family's exclusivity (exactly one member holds each tick) is the HOST's property, checked on the trace (T3 `families`), never by the compiler. The shield's bounds (RSS: the responder's proper response, the undue and abrupt brake counts) are checked on the trace, and a crossing is a probabilistic surprise (spec 19 §5). The goldens (the catalog's cases) are replayed; a scenario card's expect is read against the summary. The budget cuts (spec 14, `steps`, the instrument's state budget) are RUNTIME cuts.

**Now the question.** "Does the compiler certify only termination and bounded resource consumption, or also invariants such as actuator safety and resource conservation?" Taken item by item:

- **Termination**: NOT certified. A stage runs its rules until quiescence and the `qui` links fire; nothing static bounds the number of steps, and a stage with a pumping pair of rules runs until the case's `steps` bound cuts it. The runtime bound is the guarantee; the pumping-rule gate of the exact-instruments audit is a lint, not a proof. (Open, §11: a `terminates` declaration with a ranking measure the compiler checks per rule, the way `invariant` checks a delta.)
- **Bounded resource consumption**: COMPUTED, not certified. Spec 14 §1 gives the grounding bound Π|τ| per rule and the compiler can report the form (static, pred, roles) and the cyclic-guard case; memory and time follow from the form and the type sizes, which the domain's manifest states. There is no static proof that a run stays under a budget; there is a measured bound and a runtime cut.
- **Resource conservation**: CERTIFIED, in the exact sense of layer B: a declared `invariant … : N` or a declared `resource` (I5) is a P-invariant checked per rule; it holds in every reachable marking given the init. This is the one domain property the compiler proves, and it is the right one to build actuator ownership on.
- **Actuator safety**: two different things, and only one is certified. OWNERSHIP is: the `controls` token (`tick__grant(planner, controls)` in every command rule of the road's planner) is a resource owned once (I5), so no two members command the actuator in one tick, and a member that commands without the grant does not compile. SAFETY IN THE WORLD (the ego never enters an unsafe state) is NOT certified and cannot be by this compiler: it depends on the fold's bounds (host code, continuous), the world's dynamics and the sensor. It is the responder's shield plus the trace checks: a law (the responder stays the shield whatever the weights say, spec 19 §5), a set of bounds in ports (certifiable as VALUES in the image, spec 18), and T-verbs on every run. Bozga–Sifakis's correct-by-design result (road research note §1) is the shape a static safety proof would take, assume-guarantee over the rules' speed limits; it is an architect's task, not a compiler feature today.

**Rule of the spec.** A claim of certification names its layer. "Certified" without a layer means B. The paper's theorems are A. Anything about termination, cost or world safety is C unless a declaration of layer B exists for it.

## 8. The record

The surprise record (metispy `metis.catalog.workspace`: `member`, `trace`, `window`, `k`, `words`, `reading`, `atoms`, `status`, `who`) gains:

```
kind: ontological | perception | structural | probabilistic | computational | world | evidential | confusion
        # perception: §4 step 2, the thing in the truth, a predicate that could hold it, no fact: the host did not project it
evidence:
  truth:  [what the world held at the window: ids, classes, places]      # T10, when the host has a snapshot
  facts:  [the member's atoms about it, per tick, or "none"]
  law:    [rules fired (T8); rules one guard away: {rule, missing premise, ticks}]
  hosts:  [a second host's reading of the same card, when there is one]
  budget: {what was exhausted}                                           # computational only
  mark:   {n, k0, k1, said}                                              # confusion: the person's mark and words
  narration: [the lines the person heard]                                # confusion: narrate + explain, verbatim
  verdict: agreed | disagreed                                            # confusion: the person's answer
  then:   the kind §4 finds on the words, or "narration"                 # confusion: where the triage ended
response: the row of §5 the kind selects, as a sentence
```

A record keeps its window: the drop copies the window past the writer's ring (`keep_window`), so a rerun under the same run name cannot empty the record's evidence (two of the six road records lost theirs that way). A confusion record whose verdict is `agreed` is a closed mark, not an open surprise; it is kept only when the person asks (a teaching fragment). One whose verdict is `disagreed` is open until its `then` kind is answered or the person accepts a later narration.

The triage that fills it is a replay-time instrument beside spec 19's (`metis.trace kind RECORD`): it runs §4's procedure over the columns and writes the kind and the evidence; the model may dispute the kind in the record's reading, never overwrite it. The `words` stay the person's; the `reading` stays the agent's.

## 9. Worked examples: the six records of road-scenarios

| record | truth | facts | law | kind | response (this session) |
|---|---|---|---|---|---|
| 463d7d lane stay | Town03's lane `65_2` is bidirectional | `adjacent(left)`, no kind | `change` on `change_reason` | ontological (new predicate) | `lane_kind` as host vocabulary; `change_pass / change_aside / change_back` through the judge, 25 cases; catalog 8f9d107 |
| 503be4 priority taker (exerciser) | a crosser at 60 km/h, 2.2 s out, able to stop while standing | `safe_before(a1,long)`, `xing_before(a1,able_to_stop)`, `resp none` | no responder rule fires; `brake_cross` a guard away | probabilistic (a bound) + structural (a guard) | the fold's rule 5 window is empty: `past_last_stop` at the crosser's brake_max 8 (18.4 m, t 1.0) against `ego_stops_short` at the ego's brake_min 4 (16.4 m, false from t 0.6); two bound choices for the user; the planner guard as a pack |
| 503be4 on SUMO | the same crosser, 98 m away at t 0 | no `a1` until the trigger; filler `type(a1,not_relevant)` | `guard[brake_min]` fires | perception (the sensor's 60 m) | range a run parameter of both hosts, 100 m |
| 40f229 / 87279b cut-ins | a car cuts in close | `dangerous(lead)`, `safe_before(lead,lat)`, `resp_side` only | no longitudinal rule asked | probabilistic (lateral-last blame) | the same bound family as 503be4; step 3 |
| 668e45 / 13b2f9 gap cards | an oncoming flow, an ambulance behind | no atom for "lent lane", none for "a priority from behind" | — | ontological (new predicates) | vocabulary first, then law; the paid loop only for the clauses |
| walkers 8/27/30/37 | the net has no sidewalk | — | — | world | bodies the director carries (ruled, step 1) |

The one row that was a pure pack (`brake_cross`) is also the only row the paid loop would have solved. Every other row would have cost a session of credit for a rule that the next scenario refuted.

## 10. What it needs in the toolchain

1. **The filler fix** (§2): `road_facts` states nothing for an unfilled role, or `role_empty`; both hosts; the planner's rules that read `not_relevant` re-read. Vocabulary, by hand.
2. **The truth column in the trace**: T10 `truth` is open (CHECKS.md: the world runner's); the exerciser and SUMO hosts snapshot the bodies the ego could have seen within the card's sensor range per tick. Without it, §4 step 2 cannot run and every such record is evidential.
3. **The one-guard-away listing**: a T-verb over the member's stage at the window: for each rule, the premises satisfied and the one that is not; built from the grounder's enabled set the replay regenerates (spec 19 §7.1).
4. **`metis.trace kind`**: §4's procedure over the columns, writing `kind` and `evidence` into the record; the judge refuses a pack whose record is not structural with the record's kind and §5's row (a refusal that teaches, like the link's, but in the right direction).
5. **The link refusal re-read**: an unknown atom at the link on a record whose kind is ontological is the expected outcome; the message says "the vocabulary has no atom for X; propose the predicate and its host contract", not the nearest well-formed rule. The language RAG design keeps its two first retrievals for the structural kind.
6. **The loop's hand-over conditions** (POLICY.md: budget, no progress, out of vocabulary, contradiction, the world says so) map onto the kinds: budget → computational; out of vocabulary → ontological (its probabilistic form is spec 19 §4.2); contradiction → structural (stage order, a law question); the world says so → world. The policy gains "kind not structural" as a hand-over before the first proposal.
7. **The mark's two endings** (confusion): today `/mark K0..K1 WORDS` and the road page's mark drop a surprise at once. The chat gains the narrate-first flow: a closed mark is narrated (`narrate` then `explain` on its window) and the person answers `agree` or `disagree`; `agree` closes the mark with the narration attached (kept on request); `disagree` keeps the window and writes the record with kind confusion, the mark, the narration and the verdict (§8), then runs §4 on the words. The road page shows the same two buttons on a closed mark. The narrator's vocabulary (the Tick table's words) is the thing a repeated confusion improves.

## 11. Open

- **A `terminates` declaration** (layer B): `terminates STAGE (measure) .` with a ranking the compiler checks as a strict decrease per rule, the way `invariant` checks a delta; the quiescence of a stage would then be a theorem of the net. Needs a measure vocabulary; the architect's.
- **A safety declaration** in the Bozga–Sifakis shape (research note §1): each rule's speed bound as a port, the free space as the nearest bound of all rules, an inductive invariant checked on the composition. Layer B for the rules' side, layer C for the fold's; the architect's.
- **The refinement test** (§4) when the two truths occur in different runs: the triage needs the catalog of records, not one record; the workspace already holds them.
- **Kinds of a chair's records**: the same procedure; the chair's truth column is the people simulator's.
- Whether a record may carry TWO kinds (503be4 is a bound and a guard): yes, ordered by §4; the response row is the first's, the second's is noted.
