# OCaml toolchain — package contracts (rewrite exercise, phase 2)

The authoring-side compiler in OCaml; Python keeps the referee role
(evaluators, learning, simulators) — see the boundary decision in
01-ir-spec §6. One binary, stdlib only (a certifier should have zero
dependencies), OCaml 4.14, plain ocamlopt + Makefile.

## Module map (ocaml/, dependency order)

| module | contract (.mli) | mirrors |
| --- | --- | --- |
| `Ast` | lossless AST + canonical `pretty` | lang/ast.py |
| `Lexer` | text → token list (hand-rolled; no regex dep) | parser.py `_TOKEN` |
| `Parser` | tokens → `Ast.catalog`; `ParseError` | parser.py |
| `Catalog` | kernel types: patterns, schemas, entries, catalog; `typecheck` | kernel/{schema,catalog,typing}.py |
| `Horn` | SLD: `derivable`, `solutions` (ordered, deduped) | kernel/horn.py |
| `Compile` | `Ast.catalog` → `Catalog.t * Ports.t`; findings accumulate; `LangError` | lang/compiler.py |
| `Ports` | ports table, `ground_reads`, symbolic hook table | compiler.py (ports half) |
| `Ground` | Π-instantiation → `program` | kernel/ground.py |
| `Factorize` | symbolic emission → sites/writes/guards/cards; admission rejections | kernel/factorize.py (symbolic pass ONLY — no tables, no numpy) |
| `Bpn` | Bayesian-proof-net typing gate over the emitted net | kernel/bpn.py (structural pass) |
| `Elim` | min-fill width/ops/order, lex tie-break | factorize.`_elim_cost` |
| `Ir` | emitted structure → wire lines (symbolic prefix of M/Z) | kernel/ir.py |
| `Sha256` | FIPS 180-4, pure stdlib (`--selftest` pins vectors) | hashlib |
| `Nets` | neutral canonical serialization + `program_key` (03-canonical-key.md) | kernel/nets.py |
| `Refsample` | portable seeded sampler: splitmix64 + canonical event order (06-sampler-wire.md) | kernel/refsample.py |
| `Main` | case-manifest driver: emit / `--keys` / `--roundtrip` / `--sample` / `--selftest` | cpp/parity/gen_ir_goldens.py |

THE SLICE IS COMPLETE (stage 39): includes resolution
(`Compile.resolve_includes` — literal splice, layers/stages
adoption, cycle rejection), packs (`Compile.compile ?base` with
deferred typecheck) and admission (`Catalog.admit` — containment by
construction) are implemented and corpus-gated; the `parse (pretty
a) = a` contract runs via `metisc --roundtrip`. The stage-37
`program_key` portability finding is RESOLVED: the key hashes the
language-neutral canonical bytes (03-canonical-key.md), both
toolchains implement it, and gate 3 pins equality on the corpus —
including include-invariance (the split-file instance keys equal to
its single-file twin). The JSON pack artifact (`lang/pack.py`)
stays python-side: it is the ship format for the python runtime,
not part of the compiler chain.

## The parity gate (phase 3 acceptance)

`ocaml/parity/` carries the corpus manifest + fixture .llp files —
the manifest is the SINGLE SOURCE of the corpus: `tests/corpus.py`
parses it, `cpp/parity/gen_ir_goldens.py` (Python goldens), the
OCaml driver and all parity gates consume it. Registries (native
callables) are named in the manifest and resolved python-side only;
the OCaml driver ignores the `registry` line by design.
`metisc parity/manifest.txt` emits the corpus; gate 1 strips the
referee floats (M/Z trailing value) from `cpp/parity/ir_goldens.txt`
and requires byte equality on everything else — every V/S/K/W/G/P/
O/Y line, every ordering, every %.17g weight. Gate 2 (the triangle)
merges Python's referee expectations onto the OCaml-emitted artifact
and runs it through the C++ interpreter, which must reproduce every
expectation by table ops along the OCaml-shipped schedules:

    OCaml compiles  ≙  Python referees  ≙  C++ interprets
        (artifact)      (expectations)      (execution)

tests/test_ocaml_parity.py runs both gates when the respective
compilers are present (slow-marked, skipped otherwise).
