# formal — the Lean 4 mechanization

Machine-checked proofs (Lean 4 + mathlib) of the metatheory of the
paper (`../paper/metis.tex`, draft 0.3). The paper contains no Lean
code; this development is the reference for every statement the paper
marks **[mechanized]**.

| file | paper statement | main results |
| --- | --- | --- |
| `Formal/Spn.lean` | **Theorem 3** (equivalence onto the image), in full | `denote_congr` (invariance on congruence classes), `denote_readBack` + `wellFormed_readBack` + `denote_surjective` (surjectivity via an explicit fresh-naming section), `congr_of_denote_eq` (injectivity up to structural congruence on well-formed programs), `denote_eq_iff_congr` (the bijection) |
| `Formal/Counting.lean` | **Theorem 1**, counting kernel | `card_instance` (instances of a clause at a marking are equinumerous with the mass-action count φ — token individuation forces the falling factorials), `pushforward_weight` (the instance→clause pushforward carries weight w·φ = W_r(m)) |
| `Formal/Filter.lean` | **Theorem 2** (exact filtering) | `filterStep_eq_marginalStep`, `filter_eq_marginal` (the forward filter over the reachable support equals the DBN slice marginal) |
| `Formal/Trace.lean` | **Theorem 4**, descent skeleton | `weight_exec_swap` (adjacent transposition of independent events changes neither run weight nor final state), `traceEquiv_weight_eq` / `traceEquiv_exec_eq` (invariance on Mazurkiewicz trace classes) |

Design principle, mirroring the compiler's: formalize the *content* of
a theorem at the level of abstraction where its mathematical difficulty
lives, and leave the bookkeeping the implementation already pins
(parsers, hashing, wire formats) to the golden gates of `make check`.
Concretely: Theorem 3 is formalized in full (programs as name-carrying
lists, the SPN class as multiset-valued tuples, congruence as a
renaming injective on the program's names plus list permutations);
Theorems 1, 2 and 4 are formalized at their combinatorial /
measure-recursion cores, with the routine surrounding inductions and
the concrete site/scope instantiation remaining on paper (see paper
§Mechanization for the exact split).

## Build

```sh
cd formal
lake exe cache get   # fetch the mathlib build cache (first time only)
lake build
```

Requires [elan](https://github.com/leanprover/elan); the toolchain is
pinned by `lean-toolchain`. The development is `sorry`-free, and the
main theorems depend only on Lean's three standard axioms
(`propext`, `Classical.choice`, `Quot.sound`) — verify with
`#print axioms Metis.denote_eq_iff_congr` etc. in any file importing
`Formal`.

## Next targets

(paper §Open problems) The trajectory-level statement of Theorem 1
(product induction with normalization over enabled sets); the concrete
site/scope instantiation of Theorem 4 over a formalized emission;
verifying the Bayesian-proof-net artifact checker (Proposition 6)
against a formalized IR; the Di Guardia compositional typing
(Conjecture 7).
