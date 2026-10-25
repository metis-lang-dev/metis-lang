#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
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
k_inc=$(awk '$1=="K" && $2=="cascade-inc"{print $3}' "$WORK/keys.txt")
k_one=$(awk '$1=="K" && $2=="cascade"{print $3}' "$WORK/keys.txt")
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
"$CXX" -std=c++17 -O2 -I"$ROOT/runtime/include" \
    "$ROOT/runtime/tools/sample_run.cpp" -o "$WORK/sample_run"
"$WORK/sample_run" "$ROOT/corpus/goldens/sample_goldens.txt" \
    > "$WORK/sample.out" || true
awk '/SAMPLE PARITY/ { split($3, s, "/");
                       if (s[1] == s[2] && s[2] > 0) found = 1 }
     END { exit !found }' "$WORK/sample.out" \
    || { cat "$WORK/sample.out"; exit 1; }
grep "SAMPLE PARITY" "$WORK/sample.out"

echo "== 8. embedded directives: '#' lines are compiler-invisible; --run replays them (#interactive: EOF -> the sampler)"
# the corpus love triangle (corpus/ceptre/: the Ceptre port, under
# interactive-lp's license) carries the origin's trace as '#'-directives;
# it must still roundtrip (gate here, not 3: it is not a manifest case)
# and --run must reproduce the committed seeded traces byte-for-byte.
printf 'case love-triangle-rt\nllp love_triangle.llp\nsteps 1\nend\n' \
    > "$WORK/rt_directives.txt"
cp "$ROOT/corpus/ceptre/love_triangle.llp" "$WORK/"
"$ROOT/src/metisc" --roundtrip "$WORK/rt_directives.txt"
"$ROOT/src/metisc" --run "$ROOT/corpus/ceptre/love_triangle.llp" > "$WORK/run.txt"
diff -u "$ROOT/corpus/goldens/run_goldens.txt" "$WORK/run.txt"
# '#interactive go' with stdin closed (spec 07 P2; agent-no-intent
# s-7fd29000 B): one menu, then the sampler for every later choice —
# the same seeded wire as the plain run, and a hang fails in 20 s
mkdir -p "$WORK/ia"
cp "$ROOT/corpus/ceptre/love_triangle.llp" "$WORK/ia/"
echo "#interactive go" >> "$WORK/ia/love_triangle.llp"
timeout 20 "$ROOT/src/metisc" --run "$WORK/ia/love_triangle.llp" </dev/null \
    > "$WORK/ia/run.txt" 2> "$WORK/ia/err.txt" \
    || { echo "--run on an #interactive program, stdin closed: rc $?"; exit 1; }
diff -u "$ROOT/corpus/goldens/run_goldens.txt" "$WORK/ia/run.txt"
[ "$(grep -c 'choose an event' "$WORK/ia/err.txt")" = 1 ] \
    || { echo "a menu after EOF"; cat "$WORK/ia/err.txt"; exit 1; }

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

echo "== 11. structured diagnostics (spec 08 D2): text + JSON goldens, registry"
# corpus/diag, one run per phase: diag_compile.llp (compile),
# diag_kernel.llp (kernel; its containment-produce SUBJECT lives in the
# included diag_dom.llp — pins include-path location splicing),
# diag_pack.llp against diag_pack_base.llp (admission), and the fatal
# compile rows diag_cycle_a.llp (include-cycle), diag_extends.llp
# (extends-no-base), and diag_abstract.llp (ground: a lifted file that
# compiles alone, its abstract type refused at grounding, spec 12). JSON
# is compared with loc.file -> basename.
diag_runs() {
  ( cd "$ROOT/corpus/diag"
    "$ROOT/src/metisc" "$1" diag_compile.llp
    "$ROOT/src/metisc" "$1" diag_kernel.llp
    "$ROOT/src/metisc" "$1" diag_pack.llp --base diag_pack_base.llp
    "$ROOT/src/metisc" "$1" diag_cycle_a.llp
    "$ROOT/src/metisc" "$1" diag_extends.llp
    "$ROOT/src/metisc" "$1" diag_abstract.llp )
}
diag_runs --diagnostics > "$WORK/diag.txt"
diff -u "$ROOT/corpus/goldens/diag_goldens.txt" "$WORK/diag.txt"
diag_runs --diagnostics-json \
  | sed -E 's#"file":"([^"]*/)?([^"/]*)"#"file":"\2"#' > "$WORK/diag.jsonl"
diff -u "$ROOT/corpus/goldens/diag_goldens.jsonl" "$WORK/diag.jsonl"
"$ROOT/src/metisc" --diag-registry > "$WORK/diag_registry.txt"
diff -u "$ROOT/corpus/goldens/diag_registry.txt" "$WORK/diag_registry.txt"
# a pack's BASE that fails to compile is an ERROR (exit != 0), never
# listed as the pack's diagnostics (metispy diagnose() raises alike)
if ( cd "$ROOT/corpus/diag" && "$ROOT/src/metisc" --diagnostics \
       diag_pack.llp --base diag_compile.llp ) > /dev/null 2>&1; then
  echo "--diagnostics with a failing base exited 0"; exit 1
fi
# a lifted file grounds only through an instance that completes it:
# --run refuses diag_abstract.llp's abstract type (spec 12 P3), exit 1,
# with the committed finding (metispy test_abstract_types reads it too)
if ( cd "$ROOT/corpus/diag" && "$ROOT/src/metisc" --run diag_abstract.llp ) \
     > /dev/null 2> "$WORK/abstract_run.txt"; then
  echo "--run grounded an abstract type"; exit 1
fi
diff -u "$ROOT/corpus/goldens/abstract_run_goldens.txt" "$WORK/abstract_run.txt"
# metisc FILE.llp compiles only (spec 12 step 2): the lifted file passes
# with its advisory; a failing compile lists each error as
# `file:line: text` and exits 1 — the metis shell's cannot-serve lines
# (metispy test_abstract_types reads the same golden)
( cd "$ROOT/corpus/diag"
  for f in diag_abstract.llp diag_compile.llp diag_kernel.llp; do
    "$ROOT/src/metisc" "$f" && echo "rc 0" || echo "rc $?"
  done ) > "$WORK/compile_file.txt" 2>&1
diff -u "$ROOT/corpus/goldens/compile_file_goldens.txt" "$WORK/compile_file.txt"
# every compile/kernel/admission/ground code has a D2 fixture row (loop
# and runtime codes get theirs with the REPL surface; internal codes are
# unreachable from source; retired codes have no emitter)
for code in $(awk '$3 == "compile" || $3 == "kernel" || $3 == "admission" \
                   || $3 == "ground" {print $1}' "$WORK/diag_registry.txt"); do
  grep -qE "^(error|warning|note) $code " "$WORK/diag.txt" \
    || { echo "code $code has no D2 fixture row"; exit 1; }
done

echo "== 12. product wires: metisc --wire == metispy's bundle wire, every catalog package"
# bundle-compiler step 1: corpus/catalog holds the catalog packages' served
# sources and corpus/goldens/catalog_wires the ground.wire metispy's emitter
# makes of them (metispy tools/gen_catalog_wires.py: commit + generator hash
# on line 1); metisc --wire (program + extensions, #init/#steps, the B port
# manifest, the w sections, repr doubles) must reproduce each byte for byte.
# wire_ports.llp is the synthetic case: every port kind, a complement, doubles
# whose shortest text is not trivial.
n_wires=0
while read -r name program exts; do
  case "$name" in ''|'#'*) continue ;; esac
  set -- --wire "$ROOT/$program"
  for e in $exts; do set -- "$@" --extension "$ROOT/$e"; done
  "$ROOT/src/metisc" "$@" > "$WORK/wire_$name.txt"
  tail -n +2 "$ROOT/corpus/goldens/catalog_wires/$name.wire" \
    | diff -u - "$WORK/wire_$name.txt"
  n_wires=$((n_wires + 1))
done < "$ROOT/corpus/catalog/manifest.txt"
n_gold=$(ls "$ROOT/corpus/goldens/catalog_wires" | wc -l)
[ "$n_wires" -gt 0 ] && [ "$n_wires" -eq "$n_gold" ] \
    || { echo "product wires: $n_wires checked, $n_gold goldens"; exit 1; }
echo "PRODUCT WIRES $n_wires/$n_gold"

echo "== 13. interface check (spec 15 §6): metisc --interface == goldens, every composition"
# corpus/iface/<case>/…/composition.yaml: the alfworld and minihack tree
# installs (metis-worlds main bda52e4, nina's gen_hier / mh_hier, each
# with its family interface package iface/<family>.llp; alfworld's task
# with its world model eval/*.llp, spec 16 §3), kitchen_pot
# (metis-catalog master 8f2bc93) and one deliberately broken composition
# per check; the
# listing (stdout and stderr) and the exit code, from corpus/iface so
# every path in it is relative; METIS_HOME is the corpus-local package
# root (corpus/iface/_home: metispy master 1d0a4d6's iface/ packages, unchanged at 9c7330c)
n_if=0
for comp in $(cd "$ROOT/corpus/iface" && find . -name composition.yaml | sed 's#^\./##' | sort); do
  name=${comp%%/*}
  rc=0
  ( cd "$ROOT/corpus/iface" && METIS_HOME="$ROOT/corpus/iface/_home" \
      "$ROOT/src/metisc" --interface "$comp" ) \
      > "$WORK/iface_$name.txt" 2>&1 || rc=$?
  echo "rc $rc" >> "$WORK/iface_$name.txt"
  diff -u "$ROOT/corpus/goldens/iface/$name.txt" "$WORK/iface_$name.txt"
  n_if=$((n_if + 1))
done
n_gold=$(ls "$ROOT/corpus/goldens/iface" | wc -l)
[ "$n_if" -gt 0 ] && [ "$n_if" -eq "$n_gold" ] \
    || { echo "interface: $n_if compositions, $n_gold goldens"; exit 1; }
echo "INTERFACE $n_if/$n_gold"

echo "== 14. the one-tick instrument (spec 16 §6, §7): metisc --evaluate == --brute == goldens"
# corpus/evaluate/*.llp with #evaluate lines: wgc and bridge-torch
# (metis-catalog master 8f2bc93, copied) and kitchen_pot's cook_a
# (corpus/iface) with beliefs, the wick sweep 15/14/13, one fixture per
# refusal. Then every case YAML (…/cases/*.yaml, spec 16 §5, with its
# manifest): the same fixtures as cases, whose listing must be the
# embedded form's golden byte for byte, and the case-only ones (a lone
# belief, the cases/ manifest convention, port-function, port-unknown,
# a bad key, queries over a world model — wgc_world, and alfworld's
# installed task over its eval/world.llp — and model-path). The listing
# (stdout and stderr) and the exit code == the
# golden; every exact V line (`= p/q`) == the brute-force referee's, as
# rationals; a cut line's interval holds the referee's value through the
# fixture's own #expect
n_ev=0
ev_check() {   # $1 the file, relative to corpus/evaluate; $2 its golden's name
  rc=0
  ( cd "$ROOT/corpus/evaluate" && METIS_HOME="$ROOT/corpus/iface/_home" \
      "$ROOT/src/metisc" --evaluate "$1" ) > "$WORK/ev_$2.txt" 2>&1 || rc=$?
  echo "rc $rc" >> "$WORK/ev_$2.txt"
  diff -u "$ROOT/corpus/goldens/evaluate/$2.txt" "$WORK/ev_$2.txt"
  if [ "$rc" -eq 0 ]; then
    ( cd "$ROOT/corpus/evaluate" && METIS_HOME="$ROOT/corpus/iface/_home" \
        "$ROOT/src/metisc" --evaluate "$1" --brute ) > "$WORK/br_$2.txt"
    grep '^V .* = ' "$WORK/ev_$2.txt" | sed 's/ worlds .*//' > "$WORK/ev_$2.v"
    sed 's/ worlds .*//' "$WORK/br_$2.txt" | grep -F -x -f "$WORK/ev_$2.v" \
      > "$WORK/br_$2.v" || true
    cmp -s "$WORK/ev_$2.v" "$WORK/br_$2.v" \
      || { echo "evaluate: $1: --evaluate and --brute differ"; \
           diff "$WORK/ev_$2.v" "$WORK/br_$2.v"; exit 1; }
  fi
  n_ev=$((n_ev + 1))
}
for f in $(cd "$ROOT/corpus/evaluate" && grep -l '^#evaluate' *.llp | sort); do
  ev_check "$f" "${f%.llp}"
done
n_case=0
for c in $(cd "$ROOT/corpus/evaluate" && find . -path '*/cases/*.yaml' | sed 's#^\./##' | sort); do
  ev_check "$c" "$(basename "$c" .yaml)"
  n_case=$((n_case + 1))
done
n_gold=$(ls "$ROOT/corpus/goldens/evaluate" | wc -l)
n_names=$( (cd "$ROOT/corpus/evaluate" && grep -l '^#evaluate' *.llp | sed 's/\.llp$//'; \
            find . -path '*/cases/*.yaml' -exec basename {} .yaml \;) | sort -u | wc -l)
[ "$n_ev" -gt 0 ] && [ "$n_names" -eq "$n_gold" ] \
    || { echo "evaluate: $n_names fixtures, $n_gold goldens"; exit 1; }
echo "EVALUATE $n_ev/$n_ev ($n_case case YAMLs, $n_gold goldens)"

echo "ALL GATES GREEN"
