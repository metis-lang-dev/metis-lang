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
# installs (metis-worlds main bccfa7b, nina's gen_hier / mh_hier, each
# with its family interface package iface/<family>.llp; alfworld's task
# with its world model eval/*.llp, spec 16 §3), kitchen_pot
# (metis-catalog master 8f2bc93) and one deliberately broken composition
# per check; the
# listing (stdout and stderr) and the exit code, from corpus/iface so
# every path in it is relative; the iface/ units are the toolchain's
# standard units (iface/ at the root, spec/17 amendment 5): no METIS_HOME
n_if=0
for comp in $(cd "$ROOT/corpus/iface" && find . -name composition.yaml | sed 's#^\./##' | sort); do
  name=${comp%%/*}
  rc=0
  ( cd "$ROOT/corpus/iface" && \
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
# installed task over its eval/world.llp — model-path, and the lane: a
# port read as a table by step, by event or by tick (the crossing),
# spec 16 §10.1). The listing
# (stdout and stderr) and the exit code == the
# golden; every exact V line (`= p/q`) == the brute-force referee's, as
# rationals; a cut line's interval holds the referee's value through the
# fixture's own #expect
n_ev=0
ev_check() {   # $1 the file, relative to corpus/evaluate; $2 its golden's name
  rc=0
  ( cd "$ROOT/corpus/evaluate" && \
      "$ROOT/src/metisc" --evaluate "$1" ) > "$WORK/ev_$2.txt" 2>&1 || rc=$?
  echo "rc $rc" >> "$WORK/ev_$2.txt"
  diff -u "$ROOT/corpus/goldens/evaluate/$2.txt" "$WORK/ev_$2.txt"
  if [ "$rc" -eq 0 ]; then
    ( cd "$ROOT/corpus/evaluate" && \
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

echo "== 15. the link (spec 17 §4): metisc --link --check == goldens, the image hash; one image written, its tar round trip"
# corpus/iface: kitchen_pot (its capacity's type domain = the specialists, spec 17 L13), road (metis-worlds main
# e7bc8ba road/domains, the programs and manifests), the alfworld and minihack trees (their composition.yaml gains
# planner:, routing: and priority:, the facts their hand directors held), each with its HAND director (transitional,
# L17: the derived facts compared); kitchen_pot and alfworld again with a GENERATED director (composition_gen.yaml:
# a direct: with no package). The listing (stdout and stderr) and the exit code == the golden.
n_ln=0
for case in kitchen_pot:kitchen_pot/composition.yaml kitchen_pot_gen:kitchen_pot/composition_gen.yaml \
            road:road/composition.yaml alfworld:alfworld/domains/hier/composition.yaml \
            alfworld_gen:alfworld/domains/hier/composition_gen.yaml minihack:minihack/domains/hier/composition.yaml; do
  name=${case%%:*}; comp=${case#*:}
  rc=0
  ( cd "$ROOT/corpus/iface" && \
      "$ROOT/src/metisc" --link "$comp" --check ) > "$WORK/link_$name.txt" 2>&1 || rc=$?
  echo "rc $rc" >> "$WORK/link_$name.txt"
  diff -u "$ROOT/corpus/goldens/link/$name.txt" "$WORK/link_$name.txt"
  n_ln=$((n_ln + 1))
done
n_gold=$(ls "$ROOT/corpus/goldens/link" | wc -l)
[ "$n_ln" -eq "$n_gold" ] || { echo "link: $n_ln cases, $n_gold goldens"; exit 1; }
# written: the directory named by the golden's hash, its tar the same files
h=$(sed -n 's/^image kitchen_pot_gen v-\([0-9a-f]*\)$/\1/p' "$ROOT/corpus/goldens/link/kitchen_pot_gen.txt")
( cd "$ROOT/corpus/iface" && \
    "$ROOT/src/metisc" --link kitchen_pot/composition_gen.yaml -o "$WORK/img" --tar ) > /dev/null 2>&1
img="$WORK/img/kitchen_pot_gen.image.v-$h"
[ -f "$img/image.json" ] && [ -f "$img/image.lock" ] && [ -f "$img/members/tree_director/ground.wire" ] \
    || { echo "link: no image at $img"; exit 1; }
mkdir -p "$WORK/untar" && tar -xf "$img.tar" -C "$WORK/untar"
diff -r "$img" "$WORK/untar/kitchen_pot_gen.image.v-$h"
echo "LINK $n_ln/$n_gold (image v-$h written, tar identical)"

echo "== 16. metisc build (spec 17 §7): stale members compiled, the rest reused; the hash the link's; metisc check"
# a copy of corpus/iface/kitchen_pot: built twice (all compiled, then all reused, one hash), then one member's
# #init edited (compiler-invisible, yet in its wire): only that member recompiled, a new hash
cp -r "$ROOT/corpus/iface/kitchen_pot" "$WORK/bk"
bk() { ( cd "$WORK" && "$ROOT/src/metisc" build bk 2>/dev/null ) | grep -E '^(image|build)'; }
b1=$(bk); b2=$(bk)
echo "$b1" | grep -q 'build reused 0 \[\] compiled 3' || { echo "build 1: $b1"; exit 1; }
echo "$b2" | grep -q 'build reused 3 .* compiled 0 \[\]' || { echo "build 2: $b2"; exit 1; }
[ "$(echo "$b1" | head -1)" = "$(echo "$b2" | head -1)" ] || { echo "build: two hashes for one source"; exit 1; }
echo "#init idle 1" >> "$WORK/bk/cook_a/cook_a.llp"
b3=$(bk)
echo "$b3" | grep -q 'build reused 2 \[pot_director cook_b\] compiled 1 \[cook_a\]' || { echo "build 3: $b3"; exit 1; }
[ "$(echo "$b3" | head -1)" != "$(echo "$b1" | head -1)" ] || { echo "build: an edited member, the same hash"; exit 1; }
( cd "$ROOT/corpus/iface" && "$ROOT/src/metisc" check kitchen_pot ) > "$WORK/chk.txt" 2>&1 \
    || { tail -3 "$WORK/chk.txt"; exit 1; }
grep -q '^image kitchen_pot v-' "$WORK/chk.txt" || { echo "check: no image line"; exit 1; }
echo "BUILD 3/3 (compiled 3, reused 3, recompiled 1 of 3) + check"

echo "== 17. deployment plans (spec 17 §5): metisc --link --plan == goldens; the image's hash unchanged by a plan"
# kitchen_pot with response: 3 (composition_split.yaml: a socket's budget 1 + the director's latency 2): split
# {cook_a} | {cook_b, pot_director} (the protocol's reports one way, grants and cancels the other), the operator's
# shape (every member in the runtime; the agent process hosts the world's order and stop, amendment 2), and one
# plan of refusals (plan-member, plan-world, plan-tick-layer, L18 with the budget)
n_pl=0
for p in split operator bad unhosted; do
  rc=0
  ( cd "$ROOT/corpus/iface" && \
      "$ROOT/src/metisc" --link kitchen_pot/composition_split.yaml --check --plan "kitchen_pot/plans/$p.yaml" ) \
      > "$WORK/plan_$p.txt" 2>&1 || rc=$?
  echo "rc $rc" >> "$WORK/plan_$p.txt"
  diff -u "$ROOT/corpus/goldens/plans/$p.txt" "$WORK/plan_$p.txt"
  n_pl=$((n_pl + 1))
done
n_gold=$(ls "$ROOT/corpus/goldens/plans" | wc -l)
[ "$n_pl" -eq "$n_gold" ] || { echo "plans: $n_pl plans, $n_gold goldens"; exit 1; }
( cd "$ROOT/corpus/iface" && "$ROOT/src/metisc" --link kitchen_pot/composition_split.yaml \
    -o "$WORK/pimg" --plan kitchen_pot/plans/split.yaml --plan kitchen_pot/plans/operator.yaml ) > "$WORK/pimg.txt" 2>&1
h0=$(sed -n 's/^image kitchen_pot_split v-//p' "$ROOT/corpus/goldens/plans/split.txt")
h1=$(sed -n 's/^image kitchen_pot_split v-//p' "$WORK/pimg.txt")
[ "$h0" = "$h1" ] && [ -f "$WORK/pimg/kitchen_pot_split.image.v-$h1/plans/split.json" ] \
    && [ -f "$WORK/pimg/kitchen_pot_split.image.v-$h1/plans/operator.json" ] \
    || { echo "plans: the image v-$h1 (the golden's v-$h0) or its plans/ missing"; exit 1; }
echo "PLANS $n_pl/$n_gold (image v-$h1 with plans/split.json and plans/operator.json, its hash unchanged)"
# a world command's port (spec/17 amendment 6): corpus/iface/plan_ports has a command named for its rule (load) and one only in
# a rule's head (push, the rule named reply). L16 reads both; the plan's ports must too, or the head's command passes the
# link and never crosses
( cd "$ROOT/corpus/iface" && "$ROOT/src/metisc" --link plan_ports/composition_ports.yaml --check --plan plan_ports/plans/bridge.yaml ) \
    > "$WORK/plan_ports.txt" 2>&1 || { echo "plan_ports: does not link"; cat "$WORK/plan_ports.txt"; exit 1; }
grep '^  transport ' "$WORK/plan_ports.txt" | diff -u "$ROOT/corpus/iface/plan_ports/ports.golden" -
echo "PLAN PORTS 3/3 (a command by its rule's name, a command by its rule's head, a reading back)"

echo "== 18. the sidecars (spec 17 ruling 6): metisc's sidecar.json == metispy's, byte for byte, every corpus member"
# the four corpus images linked; each member's sidecar.json against corpus/goldens/sidecar/sidecars.sha256 (made by
# metispy's artifact.build, linker step 3); tools.json at the image root against the golden constant
n_sc=0
for c in kitchen_pot/composition.yaml road/composition.yaml alfworld/domains/hier/composition.yaml minihack/domains/hier/composition.yaml; do
  ( cd "$ROOT/corpus/iface" && "$ROOT/src/metisc" --link "$c" -o "$WORK/sc" ) > /dev/null 2>&1 \
      || { echo "sidecars: $c does not link"; exit 1; }
done
while read -r h b name; do
  img=${name%%/*}; m=${name#*/}
  f=$(ls -d "$WORK"/sc/"$img".image.v-*/members/"$m"/sidecar.json | head -1)
  got=$(sha256sum "$f" | cut -d' ' -f1)
  [ "$got" = "$h" ] || { echo "sidecar $name: $got, the golden $h"; exit 1; }
  n_sc=$((n_sc + 1))
done < "$ROOT/corpus/goldens/sidecar/sidecars.sha256"
cmp "$(ls -d "$WORK"/sc/kitchen_pot.image.v-*/tools.json | head -1)" "$ROOT/corpus/goldens/sidecar/tools.json"
echo "SIDECARS $n_sc/16 byte-equal + tools.json"

echo "== 19. the one-member image (spec 17 §2): metisc --link PKGDIR == golden; its sidecar the composition's"
# corpus/iface/kitchen_pot/cook_a linked alone (a package that runs alone is the one-member composition of itself):
# the listing == the golden, and its sidecar.json == the corpus golden's for kitchen_pot/cook_a (the same program)
rc=0
( cd "$ROOT/corpus/iface" && "$ROOT/src/metisc" --link kitchen_pot/cook_a -o "$WORK/pk" ) \
    > "$WORK/pk.txt" 2>&1 || rc=$?
echo "rc $rc" >> "$WORK/pk.txt"
grep -v '^wrote ' "$WORK/pk.txt" | diff -u "$ROOT/corpus/goldens/package/cook_a.txt" -
want=$(awk '$3 == "kitchen_pot/cook_a" {print $1}' "$ROOT/corpus/goldens/sidecar/sidecars.sha256")
got=$(sha256sum "$(ls -d "$WORK"/pk/cook_a.image.v-*/members/cook_a/sidecar.json | head -1)" | cut -d' ' -f1)
[ "$got" = "$want" ] || { echo "package cook_a: sidecar $got, the golden $want"; exit 1; }
echo "PACKAGE 1/1 (cook_a alone: one member, its sidecar byte-equal)"

echo "== 20. the standard units (spec/17 amendment 5): root, std, METIS_HOME; L20 a name resolving nowhere"
# iface/ at the root is the toolchain's standard units: every gate above runs with no METIS_HOME. Here: a metisc
# copied away from the checkout finds them compiled in (the same image); the lock records each include's place and
# key, and places.std; an include name resolving nowhere is L20 (and --diagnostics-json's failure, exit 1)
unset METIS_HOME
mkdir -p "$WORK/std/bin" && cp "$ROOT/src/metisc" "$WORK/std/bin/metisc"
want=$(grep '^image ' "$ROOT/corpus/goldens/link/kitchen_pot_gen.txt")
got=$(cd "$ROOT/corpus/iface" && "$WORK/std/bin/metisc" --link kitchen_pot/composition_gen.yaml --check | grep '^image ')
[ "$got" = "$want" ] || { echo "std: a copied metisc links '$got', the golden '$want'"; exit 1; }
lock=$(ls -d "$WORK"/img/kitchen_pot_gen.image.v-*/image.lock | head -1)
grep -q "\"std\": \"$ROOT/iface\"" "$lock" || { echo "std: the lock has no places.std $ROOT/iface"; exit 1; }
n_std=$(grep -c '"place": "std"' "$lock")
n_key=$(grep -c '"key": "[0-9a-f]\{64\}"' "$lock")
[ "$n_std" -gt 0 ] && [ "$n_key" -gt "$n_std" ] || { echo "std: the lock's includes: $n_std std, $n_key keyed"; exit 1; }
cp -r "$ROOT/corpus/iface/kitchen_pot" "$WORK/std/kp"
printf 'include "iface/nowhere.llp".\n' >> "$WORK/std/kp/cook_b/cook_b.llp"
rc=0
( cd "$WORK/std" && "$ROOT/src/metisc" --link kp/composition_gen.yaml --check ) > "$WORK/std/l20.txt" 2>&1 || rc=$?
[ "$rc" -ne 0 ] && grep -q "^error L20 link-places: cook_b: include 'iface/nowhere.llp': not under " "$WORK/std/l20.txt" \
    || { echo "std: an include resolving nowhere is not L20 (rc $rc)"; cat "$WORK/std/l20.txt"; exit 1; }
rc=0
"$ROOT/src/metisc" --diagnostics-json "$WORK/std/kp/cook_b/cook_b.llp" > "$WORK/std/d.txt" 2>&1 || rc=$?
[ "$rc" -eq 1 ] && grep -q "nowhere.llp" "$WORK/std/d.txt" \
    || { echo "std: --diagnostics-json on a nowhere include: rc $rc"; cat "$WORK/std/d.txt"; exit 1; }
echo "STD UNITS 4/4 (a copied metisc: compiled in; the lock's places and keys; L20; the diagnostics' failure)"

echo "== 21. generated level declarations (spec/16 amendment 1): metisc --levels == goldens; the level package builds"
# corpus/levels: one program (the alfworld_view level of policy-tuning-2 2f, standalone) and a manifest per case:
# alf_view generates type level, the belief's weight port (its variables the rule's) and the level pred, and agrees
# with a hand-declared evaluate level (fetch_risk over type risk); the others are the refusals (names that differ,
# an evaluate level undeclared, a hand pred that disagrees, a belief level over no belief), each naming the
# manifest line. metispy's metis.lang.levels is held to the same goldens (tests/test_levels_parity.py). Then the
# package's wire with its manifest == the golden, and it links as a one-member image (the program alone does not
# compile: its level declarations are the manifest's)
n_lv=0
for d in $(cd "$ROOT/corpus/levels" && ls -d */ | tr -d / | sort); do
  rc=0
  ( cd "$ROOT/corpus/levels" && "$ROOT/src/metisc" --levels "$d/domain.yaml" ) > "$WORK/lv_$d.txt" 2>&1 || rc=$?
  echo "rc $rc" >> "$WORK/lv_$d.txt"
  diff -u "$ROOT/corpus/goldens/levels/$d.txt" "$WORK/lv_$d.txt"
  n_lv=$((n_lv + 1))
done
n_gold=$(ls "$ROOT/corpus/goldens/levels"/*.txt | wc -l)
[ "$n_lv" -eq "$n_gold" ] || { echo "levels: $n_lv cases, $n_gold goldens"; exit 1; }
( cd "$ROOT/corpus/levels" && "$ROOT/src/metisc" --wire alf.llp --manifest alf_view/domain.yaml ) \
    | diff -u "$ROOT/corpus/goldens/levels/alf_view.wire" -
! ( cd "$ROOT/corpus/levels" && "$ROOT/src/metisc" --wire alf.llp ) > /dev/null 2>&1 \
    || { echo "levels: alf.llp compiled without its manifest"; exit 1; }
( cd "$ROOT/corpus/levels" && "$ROOT/src/metisc" --link alf_view -o "$WORK/lvimg" ) | grep -q '^result 0 error' \
    || { echo "levels: alf_view does not link"; exit 1; }
# the diagnostics with the manifest list nothing for the level package; without it, the generated pred is undeclared
[ -z "$(cd "$ROOT/corpus/levels" && "$ROOT/src/metisc" --diagnostics-json alf.llp --manifest alf_view/domain.yaml)" ] \
    || { echo "levels: --diagnostics-json --manifest lists something"; exit 1; }
( cd "$ROOT/corpus/levels" && "$ROOT/src/metisc" --diagnostics-json alf.llp ) | grep -q '"code":"pred-undeclared"' \
    || { echo "levels: --diagnostics-json without the manifest found no undeclared level pred"; exit 1; }
echo "LEVELS $n_lv/$n_gold (+ the package's wire, its link, its diagnostics with and without the manifest)"

echo "== 22. the director's stop (the standard unit, toolchain-units s-ddaed776): no grant mid-stop, over 10 seeds"
# corpus/stop: a stop while d2 holds r and d1's ticket waits (stop_waiter), and with nobody waiting (stop_nowaiter).
# iface/director_tree_domain.llp's stop_release frees r only when no ticket is left (serving at issue): every seed
# has exactly one stop_release (one revoke); with the waiter, one stop_dequeue and no grant_on_want (before the
# guard, a sampler's draw granted the waiter mid-stop and revoked it again: seeds 3, 6 and 10 here)
n_st=0
for sc in waiter nowaiter; do
  ( cd "$ROOT/corpus/stop" && "$ROOT/src/metisc" --run "stop_$sc.llp" ) > "$WORK/stop_$sc.txt" 2>&1 \
      || { echo "stop_$sc: metisc --run failed"; cat "$WORK/stop_$sc.txt"; exit 1; }
  bad=$(grep '^T ' "$WORK/stop_$sc.txt" | awk -v sc=$sc '{g = 0; r = 0; d = 0
          for (i = 3; i <= NF; i++) { if ($i ~ /^grant_on_want/) g++; if ($i ~ /^stop_release/) r++; if ($i ~ /^stop_dequeue/) d++ }
          if (r != 1 || g != 0 || (sc == "waiter" && d != 1) || (sc == "nowaiter" && d != 0)) print $2 }')
  [ "$(grep -c '^T ' "$WORK/stop_$sc.txt")" = 10 ] && [ -z "$bad" ] \
      || { echo "stop_$sc: seeds with a grant mid-stop or not one release: ${bad:-the run has no 10 seeds}"; exit 1; }
  n_st=$((n_st + 10))
done
# the committed action (spec/15 amendment 9): the counts per seed, by scene: a stop leaves a committed holder alone and
# passes the waiter over; a yield after it revokes and serves the next; a yield with no stop keeps r; preemption beats
# it; a commit and a stop in one beat are one or the other, never both
for sc in committed yield yield_nostop preempt race; do
  ( cd "$ROOT/corpus/stop" && "$ROOT/src/metisc" --run "stop_$sc.llp" ) > "$WORK/stop_$sc.txt" 2>&1 \
      || { echo "stop_$sc: metisc --run failed"; cat "$WORK/stop_$sc.txt"; exit 1; }
  bad=$(grep '^T ' "$WORK/stop_$sc.txt" | awk -v sc=$sc 'function n(r,   i, c) { c = 0
          for (i = 3; i <= NF; i++) if (index($i, r "[") == 1) c++
          return c }
        { ok = 0
          if (sc == "committed") ok = n("stop_committed") == 1 && n("stop_dequeue") == 1 && n("stop_release") == 0 && n("grant_on_want") == 0
          if (sc == "yield") ok = n("yield_owing") == 1 && n("owed_release") == 1 && n("grant_on_want") == 1 && n("stop_release") == 0
          if (sc == "yield_nostop") ok = n("commit_off") == 1 && n("owed_release") == 0 && n("yield_owing") == 0
          if (sc == "preempt") ok = n("preempt") == 1
          if (sc == "race") ok = (n("stop_release") == 1 && n("stop_committed") == 0) || (n("stop_release") == 0 && n("commit_on") == 1 && n("stop_committed") == 1)
          if (!ok) print $2 }')
  [ "$(grep -c '^T ' "$WORK/stop_$sc.txt")" = 10 ] && [ -z "$bad" ] \
      || { echo "stop_$sc: seeds off its counts: ${bad:-the run has no 10 seeds}"; sed -n 1,4p "$WORK/stop_$sc.txt"; exit 1; }
  n_st=$((n_st + 10))
done
echo "STOP $n_st/70 seeds (one revoke, the waiter passed over, no grant mid-stop; the committed action's five scenes)"

echo "== 23. the grounding budget (metispy's METIS_GROUND_BUDGET, the sw-s2 OOM): unset as before; set, refused with the rule's words"
# corpus/budget: take reads a pair of terms nothing else binds, 2 x 40 x 40 = 3200 events. Unset, and at 3200, it
# grounds; at 3199 and 1000 it is refused, exit 1, while it enumerates; the refusal at 1000 == budget.refused, the
# text metispy's GroundBudget gives the same file (tests/test_ground_budget.py)
n_gb=0
for b in "" 3200; do
  ( cd "$ROOT/corpus/budget" && METIS_GROUND_BUDGET=$b "$ROOT/src/metisc" --run budget.llp ) > "$WORK/budget.txt" 2>&1 \
      && grep -q '^F 1 (done)' "$WORK/budget.txt" \
      || { echo "budget '${b:-unset}': did not ground"; cat "$WORK/budget.txt"; exit 1; }
  n_gb=$((n_gb + 1))
done
for b in 3199 1000; do
  if ( cd "$ROOT/corpus/budget" && METIS_GROUND_BUDGET=$b "$ROOT/src/metisc" --run budget.llp ) > "$WORK/budget.txt" 2>&1; then
    echo "budget $b: grounded past it"; exit 1
  fi
  grep -q "^error: ground-budget: take grounds more than $b events" "$WORK/budget.txt" \
      || { echo "budget $b: not refused with the rule's words"; cat "$WORK/budget.txt"; exit 1; }
  n_gb=$((n_gb + 1))
done
grep '^error' "$WORK/budget.txt" | diff "$ROOT/corpus/budget/budget.refused" - \
    || { echo "budget: the refusal differs from budget.refused"; exit 1; }
echo "BUDGET $n_gb/4 (unset and 3200 ground, 3199 and 1000 refused; the refusal == metispy's)"

echo "ALL GATES GREEN"
