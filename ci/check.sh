#!/bin/sh
# metis-lang standalone gates — no python, no framework: ocamlopt + a
# C++17 compiler. The committed goldens carry the referee expectations
# (M/Z trailing floats, produced by the metispy referee); everything
# symbolic is reproduced here byte-for-byte and the C++ interpreter
# must then reproduce every expectation by table ops alone.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
CXX=${CXX:-g++}
WORK=${TMPDIR:-/tmp}/metis-lang-check.$$
mkdir -p "$WORK"
trap 'rm -rf "$WORK"' EXIT

echo "== 1. build metisc (stdlib-only ocamlopt)"
make -s -C "$ROOT/src" metisc

echo "== 2. metisc --selftest (FIPS 180-4 vectors)"
"$ROOT/src/metisc" --selftest | grep -q "selftest ok"

echo "== 3. roundtrip: parse (pretty a) = a over the corpus"
"$ROOT/src/metisc" --roundtrip "$ROOT/corpus/manifest.txt"

echo "== 4. symbolic parity: emitted corpus == goldens minus referee floats"
"$ROOT/src/metisc" "$ROOT/corpus/manifest.txt" \
    | grep -v '^#' > "$WORK/emitted.txt"
grep -v '^#' "$ROOT/corpus/goldens/ir_goldens.txt" \
    | awk '/^[MZ] /{NF--; print; next}{print}' OFS=' ' > "$WORK/gold_sym.txt"
diff -u "$WORK/gold_sym.txt" "$WORK/emitted.txt"

echo "== 5. canonical keys: every case keyed; include-splitting is identity-invariant"
"$ROOT/src/metisc" --keys "$ROOT/corpus/manifest.txt" > "$WORK/keys.txt"
n_cases=$(grep -c '^case ' "$ROOT/corpus/manifest.txt")
n_keys=$(grep -c '^K ' "$WORK/keys.txt")
[ "$n_cases" -eq "$n_keys" ] || { echo "keys: $n_keys/$n_cases"; exit 1; }
k_inc=$(awk '$2=="cascade-inc"{print $3}' "$WORK/keys.txt")
k_one=$(awk '$2=="cascade"{print $3}' "$WORK/keys.txt")
[ -n "$k_inc" ] && [ "$k_inc" = "$k_one" ] \
    || { echo "include-invariance broken"; exit 1; }

echo "== 6. the interpreter gate: metisc artifact + committed expectations -> C++"
# merge: symbolic lines from metisc, referee floats from the goldens.
grep -v '^#' "$ROOT/corpus/goldens/ir_goldens.txt" > "$WORK/gold_full.txt"
awk 'NR==FNR { gold[FNR]=$0; next }
     /^[MZ] / { n=split(gold[FNR], g, " "); print $0, g[n]; next }
     { print }' \
    "$WORK/gold_full.txt" "$WORK/emitted.txt" \
    > "$WORK/merged.txt"
"$CXX" -std=c++17 -O2 -I"$ROOT/runtime/include" \
    "$ROOT/runtime/tools/metis_run.cpp" -o "$WORK/metis_run"
"$WORK/metis_run" "$WORK/merged.txt" > "$WORK/run.out" || true
awk '/IR PARITY/ { split($3, s, "/");
                   if (s[1] == s[2] && s[2] > 0) found = 1 }
     END { exit !found }' "$WORK/run.out" \
    || { cat "$WORK/run.out"; exit 1; }
grep "IR PARITY" "$WORK/run.out"

echo "== 7. sampler wire: metisc --sample == goldens; C++ replays them"
"$ROOT/src/metisc" --sample "$ROOT/corpus/sample_manifest.txt" \
    > "$WORK/sample.txt"
grep -v '^#' "$ROOT/corpus/goldens/sample_goldens.txt" > "$WORK/sample_gold.txt"
grep -v '^#' "$WORK/sample.txt" > "$WORK/sample_mine.txt"
diff -u "$WORK/sample_gold.txt" "$WORK/sample_mine.txt"
"$CXX" -std=c++17 -O2 "$ROOT/runtime/tools/sample_run.cpp" \
    -o "$WORK/sample_run"
"$WORK/sample_run" "$ROOT/corpus/goldens/sample_goldens.txt" \
    > "$WORK/sample.out" || true
awk '/SAMPLE PARITY/ { split($3, s, "/");
                       if (s[1] == s[2] && s[2] > 0) found = 1 }
     END { exit !found }' "$WORK/sample.out" \
    || { cat "$WORK/sample.out"; exit 1; }
grep "SAMPLE PARITY" "$WORK/sample.out"

echo "== 8. embedded directives: '#' lines are compiler-invisible; --run replays them"
# the corpus love triangle carries the origin's trace as '#'-directives;
# it must still roundtrip (gate here, not 3: it is not a manifest case)
# and --run must reproduce the committed seeded traces byte-for-byte.
printf 'case love-triangle-rt\nllp love_triangle.llp\nsteps 1\nend\n' \
    > "$WORK/rt_directives.txt"
cp "$ROOT/corpus/love_triangle.llp" "$WORK/"
"$ROOT/src/metisc" --roundtrip "$WORK/rt_directives.txt"
"$ROOT/src/metisc" --run "$ROOT/corpus/love_triangle.llp" > "$WORK/run.txt"
diff -u "$ROOT/corpus/goldens/run_goldens.txt" "$WORK/run.txt"

echo "== 9. Horn facts: vars quantified (spec 5); singleton vars warn (advisory)"
# fact_vars.llp: eq(X,X) must admit the rule (quantified reading), and
# plus(n0,N,M) must warn twice on stderr — byte-identical to metispy
# (tests/lang/test_fact_vars.py reads the same golden).
"$ROOT/src/metisc" --run "$ROOT/corpus/fact_vars.llp" </dev/null \
    > "$WORK/fv_run.txt" 2> "$WORK/fv_err.txt"
diff -u "$ROOT/corpus/goldens/fact_vars_run.txt" "$WORK/fv_run.txt"
grep '^warning' "$WORK/fv_err.txt" > "$WORK/fv_warn.txt" || true
diff -u "$ROOT/corpus/goldens/warn_goldens.txt" "$WORK/fv_warn.txt"

echo "== 10. constants: argument constants are members of the declared type"
# const_check_bad.llp is a NEGATIVE fixture: compilation must fail with
# exactly the committed findings (metispy test_fact_vars.py reads the
# same golden, modulo its 'line N: ' prefix on rule/link findings).
if "$ROOT/src/metisc" --run "$ROOT/corpus/const_check_bad.llp" \
    </dev/null > /dev/null 2> "$WORK/cc_err.txt"; then
  echo "const_check_bad.llp compiled — the membership check is missing"
  exit 1
fi
diff -u "$ROOT/corpus/goldens/const_check_goldens.txt" "$WORK/cc_err.txt"

echo "ALL GATES GREEN"
