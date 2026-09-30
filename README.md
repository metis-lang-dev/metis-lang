# metis-lang

**LLP** is a small language for behavior catalogs: typed, weighted
linear-logic clauses over finite domains. One catalog, ground per
situation, is read three ways —

- **proof theory** — typing, containment admission, a proof-net normal
  form giving canonical program identity (`program_key`);
- **derivations** — staged multiset rewriting: the space of candidate
  futures (a portable seeded reference sampler pins the wire);
- **denotation** — the induced probability measure: the compiled IR
  artifact is a factor graph with shipped elimination schedules, and
  exact filtering/conditioning/decision scoring is table operations
  along them.

This repository is the language product, self-contained:

| dir | what |
| --- | --- |
| `src/` | **metisc** — the compiler. OCaml, stdlib only, one static binary: lex/parse, typecheck, includes, packs + containment admission, grounding, symbolic factorization, proof-net certification, elimination ordering, IR emission, canonical key (own SHA-256), reference sampler. |
| `runtime/` | header-only C++17 runtime: the IR interpreter (`ir.hpp`), ground-program filter (`kernel.hpp`), evaluator/blackboard/registry/plan surfaces, and the self-checking golden CLIs under `tools/`. |
| `corpus/` | the parity corpus: `.llp` fixtures, manifests, and **committed goldens**. The goldens' M/Z expectation floats are produced by an independent exact-inference referee (the `metispy` toolkit); everything symbolic is reproduced here byte-for-byte, and the interpreter must reproduce every expectation by table ops alone. |
| `spec/` | the language spec, IR wire spec, canonical-key spec, sampler wire spec, compiler contracts. |
| `contrib/` | editor tooling: VS Code extension (grammar + LSP client) and Emacs `llp-mode`. |
| `paper/` | the paper (draft 0.3, LaTeX): *Behavior Programs as Measures over Proofs*. `make paper` (needs [tectonic](https://tectonic-typesetting.github.io)). |
| `formal/` | the Lean 4 mechanization of the paper's metatheory (Theorem 3 in full; the cores of Theorems 1, 2, 4). `make formal` (needs [elan](https://github.com/leanprover/elan); mathlib is fetched by `lake exe cache get`). Optional — the language build stays OCaml + C++ only. |

## Build & check

Requirements: `ocamlopt` (4.14+), a C++17 compiler. Nothing else.

```sh
make check     # builds metisc, runs every gate (ci/check.sh)
```

The gates: SHA-256 selftest, `parse (pretty a) = a` roundtrip over the
corpus, byte-level symbolic parity against the goldens, canonical-key
coverage + include-invariance, the interpreter gate (metisc artifact +
committed expectations through the C++ interpreter), and the seeded
sampler wire in both implementations.

## Using the compiler

```sh
src/metisc corpus/manifest.txt          # emit the IR corpus
src/metisc --keys corpus/manifest.txt   # canonical program keys
src/metisc --roundtrip corpus/manifest.txt
src/metisc --sample corpus/sample_manifest.txt
src/metisc --run corpus/love_triangle.llp   # replay a file's embedded
                                            # '#'-directive case (spec §8)
```

## Status

Skeleton cut from the research tree; pre-release. Pending before
going public: license, LSP served by `metisc` itself (the editor
clients currently auto-detect a python dev server), spec scrub pass.
