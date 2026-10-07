# CI — the GitHub toolchain for the four repos

**Status: ACCEPTED 2026-10-07 (designed on user request, handed to
the opus seat to implement and test; the choices D1–D6 below are the
architect's, open to veto at landing review).**

Repos: `metis-lang` (PUBLIC — free minutes), `metispy`,
`metis-loop`, `metis-catalog` (PRIVATE — metered minutes).

## Principles

1. **Green = certifiable.** CI runs exactly the gates the review
   cycle runs locally: `ci/check.sh` (metis-lang), the fast pytest
   suite (metispy), the metis-loop suite. No weaker, no "lint-only"
   jobs pretending to be gates.
2. **Deterministic green.** A known-flaky test must never redden a
   run, and a real failure must always fail: flakes are quarantined
   behind a scoped rerun, never skipped silently (D2).
3. **Parity is first-class.** Two toolchains exist to check each
   other; CI must catch cross-repo drift without manual replay (D3).
4. **Frugal.** Private minutes are metered: one `ubuntu-latest`
   runner per job (D5), `concurrency` with cancel-in-progress,
   `timeout-minutes: 15`, pip/elan caches, path filters where a job
   is expensive.

## Per-repo workflows (`.github/workflows/`)

### metis-lang — `ci.yml`
- Trigger: push + PR (master).
- Steps: `apt-get install ocaml-nox g++` (D1 — the Makefile is
  stdlib-only `ocamlopt`, no opam/dune); `make -C src metisc`;
  `ci/check.sh` (all gates; it owns corpus, goldens, diag registry);
  if check.sh does not already compile/run the C++ smoke tools
  (`runtime/tools/*_smoke.cpp`), a smoke step does (g++ -std=c++17,
  run each).
- `formal.yml` (separate — Lean is slow): elan + `lake build` in
  `formal/`; triggers: `paths: formal/**`, weekly cron,
  workflow_dispatch; `~/.elan` + lake packages cached. Allowed to
  take its time; never gates ci.yml.

### metispy — `ci.yml`
- First landing item: **declare `numpy` in `[project.dependencies]`**
  (the long-known undeclared-dep gap; CI makes it impossible to
  ignore).
- Steps: setup-python 3.12 (pip cache), `pip install -e .`, run the
  review recipe verbatim:
  `pytest -m "not slow" --ignore=tests/kitchen -k "not sumo"`.
- **Flake policy (D2)**: the bus-FIFO ENXIO tests get a `flaky`
  marker and a SCOPED rerun (pytest-rerunfailures, `--reruns 2`
  limited to that marker or `--only-rerun OSError`) — the root-cause
  fix stays on the metis-exact-audit backlog; everything else runs
  with zero reruns. Model/net-dependent tests (ollama, overcooked,
  sumo) stay excluded exactly as the local recipe excludes them.
- `parity.yml` (D3): checkout `metis-lang@master` beside the repo,
  apt ocaml-nox, `make metisc`, then the parity suite
  (`tests/test_ocaml_parity.py` and parity-marked tests) and a
  `tools/gen_metisc_registry.py` drift check (regenerate, diff
  clean). Triggers: push + **nightly cron** (a metis-lang push
  cannot trigger a private sibling's workflow without a PAT — the
  cron bounds drift detection at one day) + workflow_dispatch.

### metis-loop — `ci.yml`
- setup-python 3.12, `pip install -e .[console]` (websockets in;
  the agent extra deliberately NOT installed), `pytest -q tests/`.
- Requirement: the gateway's real-socket tests run on the runner as
  they do locally; agent tests must skip cleanly BOTH without a
  Claude login AND without claude-agent-sdk installed (ImportError
  = skip, never error).

### metis-catalog — `ci.yml`
- The catalogs' gate is the toolchains: checkout metis-lang (build
  metisc) and metispy (pip install) beside it; for EVERY `.llp` in
  the repo run `metisc --diagnostics` and metispy's diagnose and
  fail on any `error`-severity diagnostic or toolchain disagreement;
  replay committed manifests/goldens where present. Triggers: push +
  weekly cron + workflow_dispatch.

## Shared conventions

- `actions/checkout@v4`, `actions/setup-python@v5` (pip cache on),
  `concurrency: {group: ci-${{ github.ref }}, cancel-in-progress:
  true}`, `timeout-minutes: 15` everywhere.
- Badges: each README gains its workflow badge (parity and formal
  badges beside the main one where they exist).
- Branch model: everything runs on master pushes and PRs; no
  release workflows yet (nothing is released).

## Implementation + test protocol (the implementer's half)

- Implement per repo; **test for real on GitHub**: push, then
  `gh run watch` / `gh run view --log-failed`; iterate until every
  workflow is green on an actual run (not `act`).
- Prove the gates BITE: one scratch branch per repo class with a
  deliberately broken test/catalog must produce a RED run (then
  delete the branch). A CI that cannot fail is decoration.
- Report: run URLs (green ones and the deliberate red), minutes
  consumed per private-repo run (frugality check), and any test that
  needed quarantining beyond the bus-FIFO pair — each such test is a
  finding, not a silent skip.

## Decisions (architect's, veto at review)

- **D1** apt `ocaml-nox`, no opam/setup-ocaml (stdlib-only build).
- **D2** flakes: scoped rerun via marker, never skip, never global
  reruns; root-cause stays on the backlog.
- **D3** parity lives in metispy (it owns the parity tests), nightly
  cron bounds cross-repo drift; no PAT-based cross-triggering.
- **D4** Lean formal/ is its own slow workflow (paths + weekly), and
  never gates the main CI.
- **D5** ubuntu-latest only; no macOS/Windows runners.
- **D6** paper/ (LaTeX) and contrib/vscode get NO workflows for now
  — they change rarely and gate nothing.
