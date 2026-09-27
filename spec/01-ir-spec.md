# Grounding, emission, wire — IR specification (rewrite exercise, phase 1)

Normative spec of the back half of the toolchain: ground → emit →
certify → serialize, extracted from `metis/kernel/{ground,horn,
factorize,ir}.py`. The C++ interpreter (`cpp/include/metis/ir.hpp`)
is the CONSUMER of this wire and is out of rewrite scope — it stays
a ~300-line table-ops loop; this spec is what it may rely on.

## 0. The determinism contract (the headline hidden knowledge)

Every byte of the wire is a function of the catalog text, the init
multiset, the horizon, the unknowns set, and NOTHING else. In
particular the artifact must be identical across processes, machines
and implementation languages. Every ordering below is therefore
normative, not incidental:

| order | rule |
| --- | --- |
| type constants | declaration order (grounding domain order) |
| clause schemas per stage | declaration order |
| ground instances per schema | Π-product, FIRST declared var slowest, LAST fastest |
| var table per schema | first-occurrence during inference (00-spec §5.3) |
| multiset keys | first-occurrence in pattern list (body order) |
| event table | stage order, then clauses in order, then links |
| site candidates (CPT rows!) | enabled-candidate order = event order within the stage |
| site parents | first-seen: all candidates' deps in order, then all candidates' varats |
| SSA writes per step | first-seen atom in candidates' consume++produce, candidate order |
| K-line varats | declared-scope order (= ground_reads output order, §3) |
| K-line base atoms | lexicographic (sorted) |
| V lines | lexicographic by variable name |
| G outcomes | ascending |
| P lines | lexicographic by unknown atom |
| min-fill | ties break by (fill, name) lexicographic |
| Horn solutions | SLD order: clause declaration order, depth-first, deduped |

Floats: weights print `%.17g` (bit-preserving); referee expectations
print `%.12g`. No other floats exist on the wire; the symbolic
toolchain performs NO float arithmetic (weights pass through).

Hash-order dependence is a BUG CLASS, not a style issue: any
iteration over an unordered container that reaches the wire must be
either explicitly ordered above or sorted. (Found the hard way:
min-fill tie-breaking by Python set order leaked PYTHONHASHSEED into
the artifact — fixed 2026-07-21, goldens regenerated.)

## 1. Horn solving (guards)

SLD resolution over (pred, args) patterns; variables in queries are
`?name`; clause vars rename apart as `?v@k` with a global counter.
Depth bound 256. `derivable(goal)` = first solution exists.
`solutions(goals)` = bindings of the SORTED set of ?-vars in goals,
SLD enumeration order, deduplicated on the walked value tuple.
Clause order within a predicate = catalog declaration order of
facts/rules. Domains encode all relations (arithmetic included) as
fact tables — no builtin evaluation in the kernel.

## 2. Grounding (Π-instantiation)

Per schema: enumerate substitutions over the var table (order:
00-spec §5.3) with each var ranging over its type's constants in
declaration order, cartesian product with the LAST var fastest.
Prune: any `distinct` pair equal; any guard not Horn-derivable
(guards then VANISH — never resources). Ground clause name:
`schema[X=c,Y=d]` (var-table order; bare `schema` when no vars).
Multisets accumulate duplicates (substitution collapse X=Y prices as
multiplicity 2 → falling factorial); key format `pred(a,b)`, no
spaces. All instances inherit the schema prior. Links ground
identically, keeping (pre, post).

Program = ordered stages (declaration order) with their ground
clauses, links list, init stage (first stage unless overridden),
init multiset.

## 3. Ground read-scopes (the `reads` contract, grounded)

For a clause instance bound to weight port f: substitute the port's
formal args with the instance's tag values; for each read pattern in
DECLARED order: no guards → render the atom; guards → enumerate
`solutions` of the guard conjunction (unbound vars as `?V`),
rendering one atom per solution in SLD order. Concatenate, dedup
keeping first occurrence. This LIST (not set) is the scope; its
order reaches the wire via K-line varats.

## 4. The symbolic emission (FactoredProgram, admission half)

Inputs: ground program, horizon (micro-steps), hooks (per-event:
factor, ground args, scope list, complement — pure data in the
rewrite; Python carries the binding closure too, used only at
evaluation), unknowns (init atoms lifted to variables).

Admission rejections (before any step): any multiset count > 1
anywhere (init or any event part) — the emitted class is 0/1.

State: env : atom → Const 0 | Const 1 | Var v. Init atoms → Const 1
(absent → Const 0), except unknowns → fresh `atom#i` (card 2), P
point factors carry their init values.

Per micro-step t (stage s active):

1. Candidates = clauses of s with deps ≠ ⊥, where deps(ev) walks
   consume++persist keys in order: Const 0 → ⊥ (disabled); Const 1 →
   no dep; Var v → dep v (dedup, keep order). If none: candidates =
   links with pre = s (same deps rule); if none → DONE (emission
   stops, counts frozen). Competing links must agree on post
   (else reject: branch-dependent stage schedule).
2. Per candidate with a hook: base = scope atoms with env = Const 1
   (serialize sorted); varats = (atom, v) for scope atoms with env =
   Var v, scope order.
3. parents = dedup(all candidates' deps ++ all candidates' varats
   vars), first-seen order.
4. DETERMINISTIC FOLD: exactly one candidate ∧ no parents ∧ clean
   (every produced atom has env = Const 0 or is also consumed) →
   apply (consume → Const 0, produce → Const 1), advance stage (link
   post / same), NO emission. This is how control tokens (chain,
   stage) vanish: branch-independence itself is the criterion, no
   control/state annotation exists.
5. Else emit site X{t}, card = #candidates. Stall analysis: depvars
   = dedup all deps; if |depvars| > 16 → maybe-stall := true; else
   exhaustively check all 2^|depvars| assignments — any assignment
   enabling NO candidate → maybe-stall := true. (Maybe-stall is
   evaluation-relevant only: zero-mass rows + the Z = 1 check turn
   REACHABLE stalls into errors — reject, never approximate.)
6. SSA writes: for each atom in dedup(candidates' consume++produce,
   candidate order): old = env(atom); per candidate j: produce ∧ not
   consume ∧ old = Const 1 → REJECT (double production); produce ∧
   not consume ∧ old = Var v → guard (X{t}, card, v) ∋ j and
   maybe-stall := true; produce → val 1; consume → val 0; neither →
   keep. old Const: fold kept vals; all equal → env := that const,
   no write; else Write(new, X{t}, card, old = ⊥, folded vals).
   old Var: all keep → no write; else Write(new, X{t}, card, old,
   vals with keep = ⊥). New var `atom#t`, card 2; env := Var new.
7. Advance stage (link post when link tier, else unchanged).

Emitted structure (what certificate, jtree, wire all read):
scopes = per site {parents ∪ {X}}, per write {X, new} ∪ {old},
per guard {X, old}, per unknown {v}.

## 5. Certificate (admission-time cost)

Min-fill elimination replay over the emitted scopes with per-var
cardinalities; keep = query var (marginal) or ∅ (evidence mass).
fill(v) = #non-adjacent neighbor pairs; pick min (fill, name) — the
lexicographic tie-break is normative (§0). width = max cluster size;
ops += card(v)·Π card(neighbors); order = elimination sequence (the
schedule the wire ships). Zero binding calls, zero tables — a
counting registry observes none at admission.

## 6. The wire (golden line format)

Whitespace-separated; atoms/vars contain no spaces. Comment lines
(`#`) permitted between cases.

    C <name>                           case start
    V <var> <card>                     (sorted by var)
    S <xvar> <np> <parents...> <ncand>
    K <w:%.17g> <nd> <deps...> <hook>  one per candidate, row order
      hook = 0
           | 1 <factor> <compl:0|1> <na> <args...>
               <nb> <base...(sorted)> <nv> (<atom> <parentvar>)...
    W <xvar> <card> <new> <old|-> <vals...>   val - = keep
    G <xvar> <card> <oldvar> <n> <outcomes...(ascending)>
    P <var> <0|1>                      unknown point factor
    O <qvar> <n> <vars...>             per-query elimination schedule
    M <atom> <qvar> <expected:%.12g>   referee expectation
    Y <n> <vars...>                    full-elimination schedule
    Z <n> (<var> <val>)... <expected:%.12g>   evidence-clamp mass
    .                                  case end

Symbolic/referee split: every line EXCEPT the trailing float of
M and Z is computed by the symbolic toolchain and must be
byte-identical across implementations. The M/Z expectations are
REFEREE data (require tables + registry bindings + calibration) and
remain the Python evaluator's product — this is the two-referee
architecture: OCaml compiler ≙ Python referee ≙ C++ interpreter,
meeting at this wire. A query atom whose env folded to a constant is
a serialization ERROR (corpus queries must be variables); likewise
likelihood clamp atoms.

Before any line is written the emitter runs the Bayesian-proof-net
typing gate (kernel/bpn.py; paper Prop 6): box rule, SSA
single-writer, no dangling premise, polarized acyclicity. No
ill-typed artifact ships.

## 7. Interpreter obligations (C++, unchanged, for reference)

The consumer may assume: vars declared (V) before use; one S/W/G
producer per var; schedules (O/Y) contain every non-query var
exactly once; site CPT rows normalized or zero; writes one-hot;
guards 0/1; evidence via point factors; Z ≠ 1 after clamping =
reachable stall = reject. It re-implements NOTHING symbolic: no
grounding, no min-fill, no typing — table ops along shipped
schedules only.

## 8. Magic numbers (all of them)

| value | where | meaning |
| --- | --- | --- |
| 256 | Horn | SLD depth bound |
| 16 | emission §4.5 | exhaustive stall-check cutoff (depvars) |
| 1e-6 | evaluation | Z = 1 tolerance (referee side) |
| 1e-9 | tests | parity tolerance; bpn CPT row tolerance |
| %.17g / %.12g | wire | weight / expectation formatting |
