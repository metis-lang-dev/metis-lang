# PROPOSAL — structured diagnostics (findings as certified slices)

**Status: steps 1-2 IMPLEMENTED 2026-10-04 (user go-ahead); steps 3-4
open.** Amendments agreed in review are recorded in §A at the end.

Origin: the REPL readability track (line:column diagnostics, metisc
d1fb730 / metispy 707c489) meets the loop's token problem: the
formalize repair loop today ships FINDINGS AS PROSE plus the whole
base source as vocabulary, so the model's context cost is
O(catalog) per round, and every other seat (console, narrator,
coworker) re-parses ad-hoc strings. The user's requirement, which
this proposal takes as the acceptance test:

> send the inexactness in the code to an LLM **without sending all
> the premises and source code**.

## D0 — the object

One diagnostic shape, identical in both toolchains and on every
surface (compiler findings, gate reports, runtime instruments, REPL
validation):

    Diagnostic:
      code      stable kebab ident (the registry, below)
      severity  error | warning | note
      loc       { file, line, col, decl }
                decl = the owning path: catalog/stage/rule,
                catalog/fact, catalog/weight ...
      subject   the offending construct pretty-printed ALONE —
                one rule, one fact, one decl, in canonical
                parse(pretty) form, with its %% doc
      context   the minimal closure that makes the subject readable
                WITHOUT the catalog: one line per declaration the
                subject references (pred signatures, the type's
                name+cardinality, the namespace row, the layer
                list). Mechanically derived from the subject's AST
                references; bounded (<= 12 lines, truncation is a
                diagnostic defect to fix, never silent)
      data      code-specific key->values (atom, namespace, the two
                conflicting types, budget numbers, duplicate name,
                scenario key ...) — everything a tool branches on
      hint      one imperative repair sentence (today's prose tail)

**The slice is the contract.** `subject + context + data + hint`
must be enough for a competent reader — human or model — to propose
the repair with no other material. That is checkable: the D5 gate
below runs the repair loop on diagnostics alone and it must converge
on the fixture suite as well as the full-source prompt does.

Renderings, both deterministic:

- wire/JSON: the object verbatim (loop reports gain `diagnostics:`
  beside the existing `findings:` strings, which become the text
  rendering and stay byte-identical across toolchains, as today);
- text (what the REPL and metisc stderr print):

      error containment-produce @ packmark.llp:9 (note/obs)
        %% pack observes heads: reads base state, writes only its own.
        obs [pack] : mkt * $heads -o seen * heads.
        | namespace st produce (dyn).
        | pred heads : st.
        | layers (dyn pack).
        -> packs may not produce base atoms: read it with $heads, or
           declare vocabulary in a namespace of your own

## D1 — the registry

Codes are API: stable, kebab-case, one per distinct inexactness.
Initial registry, from the strings both compilers emit today:

| code | severity | today's string (abbreviated) |
| --- | --- | --- |
| doc-missing | error | "missing %% doc (mandatory)" |
| containment-produce / -consume | error | "layer 'pack' may not produce 'heads'" |
| fact-not-bwd | error | "fact ...: predicate not declared bwd" |
| fact-var-conflict | error | "var X typed both nat and color" |
| var-untypable | error | "var N untypable" |
| fact-var-singleton | warning | (new, approved 2026-10-04) |
| const-not-in-type | error | (new, approved 2026-10-04) |
| rule-name-collision | warning | "rule name 'catch' appears 2x..." |
| provenance-shape | warning | "provenance is not `text ...`" |
| reads-undeclared | warning | ports reads outside declared scope |
| state-budget | note | "exact filter retained N states..." |
| horn-nonground | error | "non-ground Horn solution..." |
| exact-unreachable | note | trace's "exact=(out of exact reach)" |
| llm-endpoint | note | "ollama UNREACHABLE / model not pulled" |

Severity doctrine is unchanged: errors gate, warnings ride the
report, notes are instruments speaking. No silent promotion.

## D2 — parity as a golden

`corpus/diagnostics.llp`: one catalog violating every code once
(sectioned, commented). Both toolchains compile it and emit the
full diagnostic list; the JSON (minus file paths) and the text
rendering are committed goldens, and the parity gate diffs both.
A new code without a fixture row fails the gate — the registry
cannot drift from the implementations, in either direction.

## D3 — who emits what

- compilers (metisc compile.ml, metispy lang/compiler.py + typing):
  all structural findings/warnings;
- the gate cascade (formalize.admit_text_pack): wraps compiler
  diagnostics; classification and scenario budget overruns become
  diagnostics too (code `state-budget`, data carries step/support);
- runtime instruments (filter budgets, horn-nonground, exact
  unreachable): already structured exceptions — they gain their
  code and render through the same path;
- the REPL prints the text rendering; `version`/`llm` notes join.

One constructor per toolchain; no diagnostic is assembled ad-hoc
at the call site any more.

## D4 — REPL surface

`findings` (new verb) lists the serving catalog's current
diagnostics; `findings N` shows one in full (subject + context +
hint); the wire returns the JSON objects. Gate/revise reports print
diagnostics through the same renderer, so the console shows exactly
what the shell shows.

## D5 — the payoff gate (why this exists)

The formalize repair prompt becomes:

    system (prompts/formalize.txt)
    + the approved TEXT
    + the candidate's OWN source (it is being repaired)
    + the diagnostics — slices, not the base catalog

The base source leaves the prompt; vocabulary arrives only as the
context lines of the diagnostics that actually fired. Acceptance:
on the fixture suite (meadow + packmark + a diagnostics.llp-derived
repair set), the diagnostics-only prompt converges in <= the rounds
of today's full-source prompt, at a fraction of the tokens
(measured and recorded in the commit). If a repair fails for want
of context, the fix is a better slice for that code — never
"send the whole catalog again".

## Non-goals

- No change to WHAT is checked — this is plumbing for how findings
  travel, not new judgments (fact-var-singleton and
  const-not-in-type land through the normal review, this registry
  just names them).
- No severity changes to existing findings.
- No LSP protocol work beyond mapping loc 1:1 onto the existing
  line:col output (the dev server already speaks positions).

## Order of work

1. D0+D1 in both toolchains, migrating three codes end to end
   (doc-missing, containment-produce, fact-var-conflict) + D2
   golden.
2. Migrate the remaining compiler findings; gate report carries
   `diagnostics:`.
3. Runtime notes (budgets, horn-nonground) join; REPL `findings`
   verb + rendering.
4. D5: switch the repair loop, measure, record.

## A — amendments (step 1, agreed in review 2026-10-04)

A1. **Positions.** loc points at the DECLARED NAME's token: rule/link/
type/pred/bwd/namespace/port name; a fact's or Horn rule's head
predicate. Docs excluded. Non-semantic: metispy `compare=False`
fields (line, col, file); metisc `rloc` on rules plus `cdecl_locs`
aligned 1:1 with `cdecls` (beside the decl variants, so match sites
are untouched); `--roundtrip` compares through `Ast.strip_locs`.
`resolve_includes` splices locations with their decls, so an
included declaration keeps ITS file.

A2. **Context order (normative, byte parity):** the subject's preds
in source order (rule: body atoms then head, `one` dropped; link:
pre then post atoms; fact: its atom), first occurrence only, each as
its canonical `pred …`/`bwd …` line -> the namespaces of those preds
(pred decls only), first occurrence -> the types their signatures
name, first occurrence, as `type T: k constants` -> `layers (…)`
only for codes that concern layers (containment-*). Cap 12; overflow
raises a defect, never truncates. Own declarations win over a pack
base's.

A3. **Subject** = the doc lines (`%% …`) + ONE canonical line from the
shared single-declaration printers (`rule_line`, `decl_line`), which
`pretty` itself now calls, so subject and pretty cannot drift.

A4. **`text`** is the LOCATION-FREE finding string (metispy's legacy
`line N:` prefix stays on its findings list, not in the diagnostic).

A5. **Text header:** `<severity> <code> @ <basename>:<line>:<col>
(<decl>)` (matching d1fb730's lex/parse format); `<input>` when the
source has no file. JSON carries the full path; goldens normalize it
to the basename. JSON = compact, fixed key order, non-ASCII raw
(python `json.dumps(ensure_ascii=False, separators=(",",":"))`,
mirrored by hand in metisc).

A6. **Kernel findings** (containment) are emitted where they fire:
the compiler precomputes each rule's/link's slice and threads it
through `Entry` (metispy `Entry.src`, `compare=False`; metisc
`e_src`), so admission copies it verbatim — no name lookup.

A7. **Surfaces.** metispy: `LangError` / `CatalogError` gain
`.diagnostics`, `CatalogDoc.diagnostics`, `compiler.diagnose(path)`;
metisc: `Compile.diagnostics ()` (exception payloads unchanged),
`metisc --diagnostics[-json] FILE`, `metisc --diag-registry`.

A8. **D2 is two fixtures**, because both compilers stop at
compiler-phase errors before the kernel typecheck (checking more
would change WHAT is reported — a non-goal): `corpus/diag/
diag_compile.llp` (compiler phase) and `diag_kernel.llp` (kernel
phase; its containment-produce subject lives in the included
`diag_dom.llp`, pinning include splicing). Gate 11 diffs text, JSON
and the registry; the registry's `migrated|pending` flag (every
migrated code must have a fixture row) is step-1 scaffolding,
removed when step 2 lands.

A9. **Codes migrated in step 1:** doc-missing (rules and links),
containment-produce, containment-consume (split: one code per
direction), fact-var-conflict (facts; rule var conflicts stay
strings until step 2).

## B — step 2 (2026-10-04)

B1. **The registry is code -> (severity, phase)**; the step-1
`migrated` flag is gone. phase says WHERE a code fires: compile |
kernel | admission (a D2 fixture row is REQUIRED — gate 11) | loop |
runtime (fixtures land with the REPL surface, step 3) | internal
(defensive kernel invariants unreachable from source: guard-not-bwd,
guard-var-undeclared, comment-missing, var-untyped, kind-unknown —
metispy unit tests on hand-built catalogs; their metisc parity is BY
CONSTRUCTION ONLY. Named item: metispy's kernel `untyped var` check
(var-untyped) has no metisc counterpart at all; harmless while
unreachable). The OCaml registry and hints are GENERATED from
metispy's (diag.ml says so); gate 11 and test_diagnostics diff both.

B2. **All compile, kernel and admission findings are diagnostics**
(registry rows), each emitted beside its legacy string at the same
point. fact-var-conflict / var-type-conflict are SIBLINGS (facts vs
rules/links), kept apart on purpose (codes are API). arity-mismatch
covers atom, reads and weight-call arity (the site is in data).

B3. **Decl slices beyond rules**: the kernel Catalog carries a
decl-source table (metispy `Catalog.srcs`, compare=False; metisc
`k_srcs`) keyed pred/x, bwd/x, namespace/y, type/t, filled by the
compiler, for catalog-level and admission findings. A decl-level
slice's context cites only what the decl references (a pred's
namespace, its arg types). pack-adds-stage's subject is the pack's
`stages (...)` line (decl `stages`, no source position);
extends-no-base's is `extends X.` (decl `catalog/<name>`).

B4. **D2 = five runs**, one per phase: diag_compile.llp,
diag_kernel.llp (+ included diag_dom.llp), diag_pack.llp against
diag_pack_base.llp (`metisc --diagnostics FILE --base BASE`;
metispy `diagnose(path, base=)` compiles AND admits), and the fatal
rows diag_cycle_a.llp/diag_cycle_b.llp (include-cycle) and
diag_extends.llp (extends-no-base). Every gated code fires EXACTLY
once (metispy asserts uniqueness).

B5. **Gate report**: the loop gate (formalize.admit_text_pack ->
`gate`/`revise`) carries `diagnostics:` (the JSON objects) beside
`findings:`.

B6. **Parity fixes found on the way** (both now byte-identical):
metisc named Horn entries `horn/<pred>`, metispy `horn/<head atom>` —
metisc now uses the head atom (clauses of one predicate stay
distinguishable); a namespace's layers were iterated in frozenset
order (metispy, nondeterministic) vs declaration order (metisc) —
both now SORTED. Open, not fixed: metispy's include resolution
accumulates `seen` across SIBLING includes, so a diamond (one file
included twice by siblings) is falsely a cycle in metispy, not in
metisc.

B7. `metisc --diagnostics*` LIST and exit 0 even when errors are
listed (stated in the usage text): a listing, not a compile.
