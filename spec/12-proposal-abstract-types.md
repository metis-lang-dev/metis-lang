# PROPOSAL 12 — abstract types: `types (…)`, the forward
# declaration a lifted domain file needs to stand alone

**Status: PROPOSED 2026-10-24 (architect, from the user's finding on
metis-worlds alfworld/domains/director_domain.llp). Implementation in
BOTH toolchains (metis-lang authoritative, metispy at byte parity),
goldens, spec 00/08 amendments, then a sweep of every domain file an
instance completes. Step 1 (the language, both toolchains) IMPLEMENTED
2026-10-24 (opus); its decisions are §Implementation notes.**

## Motivation

A lifted domain file (spec 00 §4, RDDL-style) names types whose members
only its instance knows. `director_domain.llp` declares
`bwd handles(domain, kind).` and twenty more signatures over `kind` and
`domain`; the generated beat file includes it and adds
`type domain {nav access grasp place task}.` and `type kind {…}.`.
Alone, the domain file is refused:

    cannot serve metis-worlds/alfworld/domains/director_domain.llp:
      dyn/wake_for: var 'K' has unknown type 'kind'
      dyn/wake_for: var 'D' has unknown type 'domain'
      dyn/wake_for: var 'D0' has unknown type 'domain'

Three things are wrong with that, in the user's words: the file's
syntax is fine, so the refusal is a semantic one and should read as
one; the message points at a rule's variable when the fault is a
signature naming a type nobody declared; and nothing in the language
lets the author SAY that `kind` is a type an instance completes. The
REPL should load such a file (list its predicates, its rules, its
provenance) and refuse only to ground it; `metisc` should compile it
to a catalog that says it is incomplete, and refuse only `--run`.

## The two ways, and the choice

**(a) Forward declaration, C/C++ style.** The domain file declares the
type's NAME; members come later — further down the file or from the
file that includes it. In RDDL this is exactly the domain/instance
split: `types { kind : object; }` in the domain, `objects { kind :
{a, b, c}; }` in the instance. Metis already has the idiom for it:
`stages (main).` forward-declares the names that `stage main {…}`
defines, `layers (dyn).` the names rules carry.

**(b) A module contract, OCaml style.** The domain file states what
its includer must provide (`requires type kind, domain.`), a
signature the includer is checked against.

(a) is the fit. Metis has no module boundary to check a contract
against: `include` SPLICES declarations (spec 00 §4), the includer and
the included become one unit, so "who provides" is not a question the
compiler can ask after splicing — only "is every type complete?". A
contract adds a notion (interfaces, provision checks, errors at the
include site) for no gain over the one question. (a) follows the
existing `stages (…)`/`stage` pairing, mirrors RDDL (which the
lifting copies by design), and keeps one semantic check: a type that
is abstract when grounding starts. What (b) gets right is kept in the
wording of that check: the message says an instance supplies it.

## P1 — the declaration

    types       ::= "types" "(" ident* ")" "."

added to `decl` (spec 00 §2). Lookahead as for `stages`: `types` is
the declaration only when followed by `(`; elsewhere it is an
identifier. Each name becomes an ABSTRACT type: a type with no
members yet. Pretty/round-trip keeps the line as written (spec 00 §3).

- `types (kind domain).` and later `type kind {goto fetch done}.`
  in the same unit (the spliced unit, in any decl order): the
  definition COMPLETES the abstract type. Constant order is the
  definition's, as today.
- `type t {…}` twice is `decl-duplicate`, as today. `types (t)` twice,
  or `types (t)` beside a definition of `t`, is silent: the set of
  abstract names is a set.
- `type t {}` (empty members) is NOT the abstract form and stays
  whatever spec 00 says of it today; abstraction is spelled only by
  `types (…)`.

## P2 — static semantics (spec 00 §5)

Sweep 1 collects abstract types with the defined ones; the catalog
records them (`k_types` entry with no constants and an `abstract`
mark; the IR and the canonical key (spec 01, 03) carry the mark —
an abstract `kind` and a defined `kind {}` are different units).
For signatures, variable typing and range restriction an abstract
type is a type. CONSTANT MEMBERSHIP at an abstract-typed position is
skipped at compile time (no members to check against) and done by
the kernel typecheck when the type is complete, as for an undeclared
type today.

`compile_catalog` SUCCEEDS on a unit with abstract types still
abstract. It attaches the advisory (never a finding, same channel as
the once-only fact var, byte-identical across toolchains):

    advisory: type 'kind' is abstract (types (kind)): this unit
    grounds only through an instance that completes it

`metisc FILE` (compile, `--diagnostics-json`, the bundle) therefore
passes; the bundle's manifest lists `abstract: [kind, domain]`.

## P3 — the semantic check: grounding

Grounding a catalog with an abstract type still abstract is a
FINDING, code `type-incomplete`, at the `types (…)` line that
declared it:

    type 'kind' has no members: declared by `types (kind)`, completed
    by no `type kind {…}` — the instance that includes this file
    supplies it

It is raised by: `metisc --run` / `--wire` / any ground, the REPL's
run, step, `#init` application, state after grounding, the kernel's
`ground()` in both toolchains. The REPL LOADS the file (serve, the
listings, `explain` of a rule, `doc`) and refuses only those. One
finding per abstract type, in `types` order.

## P4 — the diagnostic for a type nobody declared

A type named in a `pred`/`bwd`/port signature that is neither defined
nor abstract is a FINDING, code `type-unknown`, at that signature (the
first declaration naming it; one finding per type):

    pred seen: 'kind' is not a type — declare it: `types (kind).`
    when an instance completes it, or `type kind {…}`.

`var-type-unknown` is RETIRED: every variable's type comes from a
signature, so the rule-level finding was always this one, reported
three times too late. Spec 08's registry keeps the code as retired
(no emitter), the D2 table gains `type-unknown` (compile) and
`type-incomplete` (ground); the naming_type context slice (spec 08
A2) is no longer needed and goes with it. Goldens regenerated in
metis-lang, metispy parity byte-equal (gate 9/10 texts).

The REPL's `cannot serve FILE:` listing prefixes every finding with
its location, `file:line:`, as `metisc` does — the user's "without
line indicator".

## P5 — mapping

- RDDL: `types { t : object; }` ↔ `types (t).`; `objects { t : {…} }`
  ↔ `type t {…}.` (spec 00 §4 gains the sentence).
- Ceptre: no counterpart (Ceptre types are open, `succ nat : nat`).
- `extends` (a pack over a base): a pack may complete the base's
  abstract type (one definition in the pair) and may declare its own
  abstract types for a further instance.

## P6 — the sweep

Every domain file that an instance completes gets its `types (…)`
line, so that `metis FILE` serves it alone and `metisc FILE` compiles
it: metis-worlds alfworld/domains/director_domain.llp (`kind domain`),
the hierarchy bases gen_hier.py lifts (`object`, `receptacle` …
where the instance supplies them), web/domains/world_ui; metis-loop
domains/ui; metis-catalog domains/nav, road, xtraffic and the goldens
cases — found by compiling each included file on its own. Generators
(gen_hier.py) keep writing the completing `type … {…}` lines in the
instance; nothing else changes for them.

## Acceptance

1. `metis director_domain.llp` serves the file with `types (kind
   domain).` in it; `run` answers with the `type-incomplete` text;
   the beat instance that includes it runs as before (alfworld tests,
   the demo's 35/35 check).
2. `metisc director_domain.llp` compiles with the advisory; `metisc
   --run` refuses with the finding; `--diagnostics-json` carries
   `type-incomplete` with the `types` line's location.
3. A file naming an undeclared type gets one `type-unknown` at the
   signature, with `file:line:` in the REPL's listing; no
   `var-type-unknown` anywhere in the goldens.
4. Both toolchains byte-equal on the new texts; ci/check.sh green;
   the sweep's files compile alone; the editor shows the finding on
   the signature's line.

## Implementation notes (step 1, opus, 2026-10-24)

- **The advisory has its own code**, `type-abstract` (warning,
  compile): the channel of the once-only fact var is a registered
  warning code, so the advisory needs one. Its location and slice are
  type-incomplete's.
- **Location.** A `types (…)` decl's loc is its FIRST name's token
  (spec 08 A1, the declared name; `(` when the list is empty); every
  type it declares reports at that loc (one decl, one loc).
- **The texts name the decl as written**: `types (kind domain)`, not
  `types (kind)`, in both the advisory and the finding.
- **Port argument lists are not checked** for type-unknown: only
  `pred`/`bwd` signatures. A weight port's arguments are its formals
  (`weight w(N)`) or loose names (`weight move(cell)`), and no var is
  typed from them; checking them would refuse `weight bad(n0)` (the
  reads-formal-not-var fixture) for the wrong reason.
- **Stricter than before, by design.** var-type-unknown fired only
  where a RULE VARIABLE sat at a position of the undeclared type; a
  signature whose undeclared type held only constants (`pred
  done(water)` with `done(water)`) compiled. type-unknown refuses it.
  The committed sweep (metis-catalog, metis-worlds, metis-loop, the
  toolchains' corpora, metispy's domains: 623 files) has 17 files
  that compiled before and do not now: metis-catalog plant (fixed in
  step 1, `type water {water}.` `type soil {moist dry}.` — the ground
  program and wire unchanged; its artifact sidecar now lists the two
  types as slots) and 15 metis-loop policy-run records whose bases
  the loop's world adapters write without types (step 3: the base
  generators gain their `types (…)` line). 83 files that failed with
  var-type-unknown now fail with type-unknown, once per type.
- **The canonical key and the IR need no mark**: both are of a GROUND
  program, and a unit with an abstract type never grounds (P3).
- **Packs** complete a base's abstract type at admission (P5); the
  base's own constants at those positions are not checked again (a
  pack compiles against the base, it does not recompile it). An
  instance that includes the file compiles the whole unit and checks
  them.
- **Hand-built kernel catalogs** lose the kernel's var-type check
  with var-type-unknown's retirement: the compiler is the only door
  (spec 12 P4).

