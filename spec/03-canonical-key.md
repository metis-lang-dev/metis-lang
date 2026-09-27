# Canonical key — the language-neutral serialization (phase 3+)

The stage-37 finding, resolved: `program_key` used to hash a
python-repr of the canonical payload — unreproducible from any other
language, blocking a second toolchain from sharing the artifact
cache (jtree/factored AOT structures, projection cache, surprise
records all key on it). The key now hashes CANONICAL BYTES with a
fixed hash; both toolchains implement it and a corpus gate pins
equality.

## The canonical bytes (normative)

UTF-8 text, `\n`-terminated lines:

    metis-canonical 1
    stage <name>              per stage, DECLARED ORDER (semantics)
    c <cons> ; <prod> ; <pers> ; w <weight>    clauses of the stage,
                                               lines sorted BYTEWISE
    l <pre> <post> ; <cons> ; <prod> ; <pers> ; w <weight>
                              all links, lines sorted bytewise
    init-stage <name>
    i <atom>:<count>          init entries, lines sorted bytewise

- A multiset renders as `atom:count` items sorted bytewise, joined
  by `,`; empty renders `-`. A zero count is absence (dropped), so
  {a:0} and {} serialize identically — semantically equal, now also
  identically keyed.
- Weights print `%.17g` (C printf semantics; bit-preserving; both
  languages produce identical bytes for identical doubles).
- Clause/link NAMES do not appear (presentation, not content);
  stage names, atoms and counts do (semantics).
- Atoms never contain whitespace, `;` or `:`; they DO contain commas
  inside parentheses (`pred(a,b)`), so multiset items separate on
  TOP-LEVEL commas only (a consumer splits at paren depth 0 — found
  by the first real consumer, the C++ sampler rung; the serializer
  side was always unambiguous).
- Sorting is bytewise on the RENDERED lines/items — no
  implementation-specific collation anywhere.

## The key

    program_key = lowercase hex SHA-256 of the canonical bytes

SHA-256, not the runtime language's default digest: canonical
identity is the soundness of AOT compilation — collision resistance
is load-bearing. Implementations: python `hashlib` in
`kernel/nets.py` (`canonical_bytes` + `program_key`); OCaml
`ocaml/sha256.ml` (FIPS 180-4, pure stdlib, pinned by the standard
vectors via `metisc --selftest`) + `ocaml/nets.ml`.

## Invariants (inherited from the stage-3 discrimination suite)

Invariant under presentation shuffles and clause/link renaming;
discriminates weight, multiplicity, stage-wiring, init and
dropped-clause mutations; stage ORDER retained. `canonical()` (the
event-table presentation used for policy indexing) is UNCHANGED —
only the key's byte payload moved to the neutral form. `run_key`
stays python-internal (run identity never crosses toolchains).

## The gate

tests/test_ocaml_parity.py gate 3: `metisc --keys manifest` must
equal python's `program_key` on every corpus program, after
`--selftest` passes the FIPS vectors.
