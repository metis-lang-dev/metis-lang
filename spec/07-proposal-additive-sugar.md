# PROPOSAL — additive-connective sugar (⊕ / & / ⅋ audit)

**Status: PROPOSAL, not implemented. Under review; nothing here is
part of the v2 surface or the freeze until accepted.**

Origin: connective audit against the LL operator table (par ⅋, plus
⊕, with &) and a syntax-surface comparison with the Ceptre lineage —
Martens et al., *Generative Story Worlds as Linear Logic Programs*
(INT 7, 2014; Celf-era syntax) and the current
`interactive-lp/examples/tragedy.cep`. The audit's conclusion: all
three additive-flavored mechanisms already exist in metis
*semantically*; two deserve surface sugar, one must stay out of the
type system. The identity element 0 (empty internal choice) is
already load-bearing: a stalled site / `Z = 0` **is** the additive
zero, and it is the surprise signal.

## P1 — `⊕` internal-choice heads (sugar, recommended)

A clause with alternative weighted outcomes:

    flirt [story] : $at(C,L) * $at(D,L) * eros(C,D)
      -o ( eros(D,C) @w 3
         | anger(D,C) @w 1 ).

**Desugaring (AST-level, like range sugar):** n clauses sharing the
body, named `flirt#1 .. flirt#n`, each with its branch's head and
weight. Expansion happens in the parser exactly as type-range sugar
does: round-trip (`parse(pretty(a)) == a`), the compiled catalog and
`program_key` see only the expanded clauses — **zero freeze impact,
zero kernel/semantic change**. Because the branches share the body,
they share the anchor token and form one CHOICE site by construction:
the factored emission and Theorem 4 are untouched; the site's CPT is
the ⊕.

Grammar delta (if accepted):

    rule ::= [docs] ident "[" ident "]" ":" body "-o" althead "."
    althead ::= head ["@w" weightexpr]
              | "(" head "@w" weightexpr ("|" head "@w" weightexpr)+ ")"

Weights mandatory per branch in the alternative form (the point of ⊕
here is the weighted internal choice; an unweighted branch would
silently default and hide the measure).

## P2 — `&` external choice as an interpreter directive (recommended)

Ceptre marks a stage interactive with `#interactive stagename.` — the
environment, not the engine, resolves the choice among enabled rules.
metis already has the semantics (the policy hook: prune/reweight the
enabled tier, measure renormalizes) and already has the syntax class:
`#` interpreter directives (spec §8, compiler-invisible, canonical
key unaffected).

**Proposal:** adopt Ceptre's directive verbatim as a new directive
line:

    #interactive go

Driver semantics: when the active stage is marked interactive,
`metisc --run` / the REPL present the enabled events (with their
normalized weights) and read the selection from the interaction
channel instead of the sampler; the recorded trace notes the choice
was external (conditioning, not sampling). This is the `&` of the
operator table — environment-resolved choice — delivered at the
driver level where it semantically lives. No grammar change, no
freeze impact, bonus: byte-level Ceptre compatibility for ports.

Later, if conditioning-on-external-choice needs to appear in
*certified* artifacts (not just dev runs), revisit as a stage
attribute; not now.

## P3 — `⅋` : no surface syntax (explicit non-goal), parallel
schedules instead

⅋ as a type former would leave the Horn/MSR fragment (CLF/Lollimon
territory) and break the site discipline that the factored emission
and class F depend on (paper §7). Where ⅋ already lives: the
polarized reading of every clause (`A ⊸ B = A⊥ ⅋ B`, the box typing
of Prop 6) and Mazurkiewicz concurrency of footprint-disjoint events
(Thm 4). The actionable item is not syntax but **runtime
parallelism**: Theorem 4 licenses evaluating independent sites /
disjoint junction-tree branches concurrently, and the Foata layering
already computed for `run_key` is the parallel schedule. If/when an
artifact outgrows ~ms query times, emit the layer structure into the
wire (new optional record) and thread the C++ table-ops loop per
layer. Not before: the road artifact runs ~1 ms/query single-threaded.

## P4 — small Ceptre-compatibility items surfaced by the comparison

- **`-o ()` as alias for `-o one`** (trivial lexer alias, expands in
  AST): accept for port friction; `pretty()` prints `one`.
- **`!A` in heads (Ceptre's persistent production, e.g. `!dead C`)**:
  NOT sugar — producing onto a maybe-present atom is exactly what the
  emission's double-production analysis guards, and latching
  (produce-if-absent) changes the measure. Defer; model as today
  (produce the atom, write no consumer, let the guard machinery
  police it). Revisit only with a worked semantics.
- Everything else in `tragedy.cep` already has a direct LLP spelling
  (see table).

## Appendix — syntax surface: Celf (2014) → Ceptre (today) → LLP

| aspect | Celf (INT 7 paper) | Ceptre (`tragedy.cep`) | metis LLP v2 |
| --- | --- | --- | --- |
| rule | `name : A -o {B}.` (monad braces) | `name : A -o B.` in stage block | `name [layer] : body -o head [@w w].` (layer tag + mandatory doc comment) |
| tensor | `*` | `*` | `*` |
| persistent read | `!A` premise | `$A` prefix | `$A` (same reading) |
| persistent produce | `!A` head | `!A` head | — (P4: deferred, guard-policed) |
| unit head | `{1}` / `()` | `-o ()` | `-o one` (P4: accept `()` alias) |
| types | open constants, `c : character.` | same | **finite enumerated** `type character {...}.` + range sugar (Π-grounding bound — by design) |
| predicates | `pred : t -> type.` | `at character location : pred.` | `pred at(character,location) : namespace.` (namespaces carry layer rights) |
| backward chaining | full Celf | `: bwd.` preds | `bwd` preds + Horn `fact.` / `head :- body.` |
| stages | none (proposed as "phases") | `stage s {...}`, quiescence transitions | `stages (...)` declared order + `stage s {...}` + `qui` links (first-class, weighted) |
| interactivity | future work | `#interactive s.` | — today (policy hook / REPL); **P2 adopts Ceptre's directive** |
| weights / measure | none ("fair" nondeterminism) | none | `@w` static prior or weight **port** with declared `reads{}` — the measure is the product |
| choice among enabled | uniform/unspecified | uniform or interactive | weighted CHOICE = the ⊕ (P1 sugars multi-headed form) |
| multiplicity | repeated premises | repeated premises | same, **priced**: falling-factorial counts (Thm 1) |
| distinctness | neq fact tables | neq fact tables | `C <> A` sugar |
| init / cases | `context init = {...}.` + `#trace _ s init.` | same | `#init/#steps/#seeds/#query` directives (compiler-invisible) + certified manifests |
| quantification | explicit `Forall L.` | implicit uppercase vars | implicit uppercase vars |
| extension | — | — | `extends` + containment admission (packs only ADD) |
| external world | — | — | `weight/guard/input/output` ports, `reads{}` contract |
| identity / provenance | rule names | rule names | names + provenance records + canonical `program_key` (Thm 3) |
| traces | proof terms, let-bindings, concurrent equality | run traces | event sequences + `run_key` (Foata normal form) — same quotient, now measured (Thm 4) |

Reading of the lineage: Celf's proof-term "concurrent equality" and
the let-binding dependency analysis are exactly what metis turned
into `run_key`/Foata and the occurrence-net measure; Ceptre's
`#interactive` is the one surviving surface feature metis dropped and
should take back (P2); weights, ports, typing-as-bound, packs and
canonical identity are the metis additions on top of an operational
core kept deliberately identical (Thm 1).

## Review checklist (fill in at review)

- [ ] P1 accepted? (grammar delta + `#k` naming of expanded clauses)
- [ ] P2 accepted? (directive vocabulary addition: `interactive`)
- [ ] P3 non-goal confirmed; parallel-schedule wire record deferred
- [ ] P4 `()` alias accepted; `!`-head stays out
- [ ] Acceptance test: port `tragedy.cep` to `metis-catalog/domains/fiction/`
      using P1/P2, diff the ergonomics against the Ceptre original
