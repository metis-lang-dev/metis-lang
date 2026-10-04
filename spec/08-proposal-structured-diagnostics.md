# PROPOSAL — structured diagnostics (findings as certified slices)

**Status: DRAFT 2026-10-04, for user review. Nothing implemented.**

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
