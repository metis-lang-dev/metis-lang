# PROPOSAL 17 — the image and the link step: one deployable object per composition

**Status: RULED 2026-10-28 (image-spec s-ae3cee35 step 2, the architect; from metis's link-time inventory,
steps/step1-inventory.md, revised on metis's review steps/step2-review-metis.md: L23–L25, the planner and the
routing block, the transport line form, per-runtime host bindings). Step 3 = the implementation brief (A2). Nothing here changes the grammar: a package compiles as before to its wire and
bundle; the composition and its manifests are the same files. What is new is the object the link step makes
from them, the IMAGE, and the rule that a runtime reads that object and nothing else. The linker is
`metisc --link`, in the OCaml toolchain, the only implementation (the user, 2026-10-28); metispy's
`metis.catalog build` calls it.**

The user's framing (2026-10-28): the bundle compiler gives one deployable per package; the tick runtime
(spec 15) runs several packages in parallel with message passing; so a bundle that comprises several packages
deserves its own linker, and a project can have a Makefile that recompiles and relinks on change. And: the same
bundle must be deployable to two runtimes — one image loaded by two processes, with a transport between them,
emulated first over two sockets and a message-to-atom parser, ROS 2 only when behaviour tests on a simulator
need it.

## 0. In one table

| piece | where | what it means | § |
|---|---|---|---|
| bundle | `domains/<m>/build/<m>.metis.v-<h12>/` (exists) | one package compiled: ground.wire + sidecar.json + tools.json | 2 |
| image | `build/<c>.image.v-<h12>/` (new) | one composition linked: the members' bundles, the resolved tables, the derived director, the lock | 3 |
| link | `metisc --link composition.yaml` | resolution of every port, token, type, role, clock and host NAME against the members' wires; errors L1–L14 | 4 |
| lock | `image.lock` in the image | member → bundle hash, iface file hashes, include places, toolchain version | 3.4 |
| deployment plan | `plans/<p>.json` beside the image, not inside its hash | member → process; the transport ports derived; the transport budget | 5 |
| transport port | derived by the link from a plan | a shared pred whose producer and consumer sit in different processes; finite atoms only | 5 |
| loader contract | §6 | what a runtime reads from the image and nothing else; config no longer names members, director, clocks | 6 |
| driver | `metis build` / `metis check` | compile the changed members, link, write the image; a Makefile target | 7 |

## 1. What is wrong today

The inventory found that **no runtime reads composition.yaml**; only `metisc --interface` does. The py Live
takes its member list, its director and its clocks from the agent's config file; the Go agent takes hosts and
beats from a compiled-in registry; the C++ loader reads one wire. The composition is checked (I1–I12) and then
left behind: what runs is assembled again, by hand, in three places, and nothing compares the three with the
composition. The gaps, each a thing checked nowhere:

1. the running members and director vs `specialists` / `direct`;
2. `type domain` and `type resource` in the capacity vs the member list and the resources;
3. `response` ρ vs the members' `period`;
4. `priority(P, Q)` as a strict order;
5. `world.in`;
6. that every member includes the capacity;
7. the protocol's natures, read by the Live from the toolchain's own `iface/`, not from the composition's
   `protocol:`;
8. the director's role facts, scanned by a regular expression over the top file, so facts in includes are
   missed;
9. the Go host registry and beats vs the manifests' `host:` and `clock:`;
10. the sidecar key vs the wire (`Wire.Key` has no caller), and neither bundle key vs the interface's keys;
11. include resolution: `metisc` without `METIS_HOME` has no home, py and Go default one, so one source can
    resolve two ways and no bundle records which;
12. level, belief and evaluate port names, checked only when a host builds its hook.

Every one of these is a LINK-TIME fact: it is decided by the composition and the members' compiled programs,
before any process starts, and it does not change while they run. That is what a linker checks and records.

## 2. The objects

- A **package** is a directory under a catalog root (spec 00 §2.4): program, host, manifest, goldens.
- A **bundle** is a package compiled: `ground.wire` (the N/B/E/I/S lines), `sidecar.json` (the events' names and
  lines, the init order, the key), `tools.json`. Hashed by content, `v-<h12>`. Unchanged by this proposal.
- A **composition** is `composition.yaml` with its members' manifests, the capacity, the protocol file and the
  direct member (spec 15 §2).
- An **image** is a composition linked: the bundles of its members, the DERIVED DIRECTOR's bundle, and
  `image.json`, the resolved tables of §3.2, under one content hash. One image per composition. A package that
  runs alone is the one-member composition of itself, so the agent's `--pkg NAME` loads a one-member image and
  nothing is special about it.
- A **deployment plan** assigns members to processes. It is not part of the image: one image, any number of
  plans, the same hash. A plan's derived transport ports are recorded beside the image (§5).

## 3. The image

### 3.1 Layout

```
build/<c>.image.v-<h12>/
  image.json          the resolved composition (§3.2), metis-image/1
  image.lock          what the link resolved from where (§3.4)
  members/<m>/        each member's bundle, copied by hash (ground.wire, sidecar.json, tools.json)
  members/<d>/        the direct member's bundle, GENERATED at link (§4.3), same layout
  plans/<p>.json      zero or more deployment plans with their transport tables (§5); outside the hash
```

The hash `h12` is the first twelve hex digits of sha256 over the canonical `image.json`, followed by every
member's `ground.wire` in `members` order. The sidecars and tools are inside the bundles' own hashes, which
`image.lock` records, so they are covered through the lock without being hashed twice.

### 3.2 image.json

```
{ "format": "metis-image/1",
  "name": "kitchen_pot", "composition_key": "<sha256 of canon_comp, as --interface>",
  "toolchain": {"metisc": "<version>", "spec": [15, 16, 17]},
  "capacity": {"domain": ["cook_a", "cook_b", "pot_director"], "resource": ["pot"], "key": "<h>"},
  "protocol": {"file": "iface/protocol_domain.llp", "key": "<h>",
               "tokens": {"tick__want": "signal", "tick__grant": "level", ..., "tick": "injected", "tick_s": "injected", "changed": "injected"}},  # the natures; the injected three named
  "planner": "cook_a",                           # the member whose results the director routes (§3.3)
  "members": [
    {"name": "cook_a", "role": "specialist", "bundle": "members/cook_a", "bundle_key": "<h12>",
     "wire_key": "<program_key>", "program": "cook_a.llp",
     "host": {"py": "cook_host.py:make", "go": "cook"},            # one binding per runtime that can host it
     "clock": {"beats": 1, "period": null},
     "shared": {"tick__want": "out", "tick__grant": "in", "pot": "resource", "hand_free": "world-private", ...},
     "status": {"success": ["tick__done"], "failure": []}, "gating": "program",
     "resources": {}, "levels": {...}, "beliefs": {...}, "evaluate": {...},
     "display": "cook_a", "line": "...", "voice": "third"},
    ...,
    {"name": "pot_director", "role": "direct", "generated": true,
     "roles": {"specialist": ["cook_a", "cook_b"], "handles": {...}, "result": {...}},
     "priority": [["cook_a", "cook_b"]], "resources": {"pot": {"count": 1}}, ...}
  ],
  "ports": [                                     # every shared pred, resolved
    {"pred": "tick__want", "nature": "signal", "producers": ["cook_a", "cook_b"], "consumers": ["pot_director"]},
    {"pred": "pot", "nature": "resource", "owner": "pot_director", "count": 1, "holders": ["cook_a", "cook_b"]},
    {"pred": "order", "nature": "world-private", "members": ["cook_a", "cook_b"]},
    ...
  ],
  "world": {"out": [...], "in": [...]},          # out: the world's readings; in: the members' commands
  "response": 2,
  "director_statuses": {"cook_a": {"success": ["tick__done"], "failure": []}, ...}
}
```

Everything in it is either copied from a manifest after the link checked it, or DERIVED by the link (the
`ports` table, the director's roles and handles, the natures, the keys). A runtime never derives any of it
again. The manifests' shape checks that live in metispy's `manifests.py` today become link checks and stay
there in one place (the OCaml linker); metispy keeps its shape checks only as the REPL's early diagnostics.

### 3.3 The derived director

The direct member is GENERATED at link from the toolchain's lifted base (`iface/director_tree_domain.llp`,
`director_tree_wake.llp`, and the routing base `iface/director_domain.llp` of policy-tuning-2's ruling) plus
the composition's facts, written as a generated `.llp` and compiled like any member:

- `specialist(S)` for every specialist; `planner(P)` for the member `planner:` names in `composition.yaml`
  (or, absent, the one member that consumes every `result` kind; two candidates or none is `link-planner`);
  `handles(S, K)` ONLY for a `K` the planner produces and S consumes (planner `out` → S `in`); `result(K)` for
  every `K` a specialist produces and the planner consumes — results are the planner's alone, never routed to
  another specialist (the DIRECT defect metis found: `handles(place, carrying)` sent grasp's result to place);
  `end(P)` / `finished` from the planner's `status`; `nohandler(K)` for a goal kind no specialist handles;
- `priority(P, Q)` from `composition.yaml`'s `priority:` list (today they sit in a hand-written director
  file; the link accepts a hand file only as a transitional `direct:` with a warning, and compares its facts
  with the derived ones);
- `#init free(R)` for every resource, with its count;
- `type kind {...}` from the handled goal kinds, `{none}` when no cross-member port exists (road);
- the POLICY facts the Live's director reads and no rule can derive — `detour(K1, K2)`, `escalate(K, S)`,
  `rename(K1, K2, G)` — from a `routing:` block in `composition.yaml` (`routing: {detour: [[K1, K2]],
  escalate: [[K, S]], rename: [[K1, K2, G]]}`), generated as facts; a hand-written `direct:` file stays a
  transitional form, accepted with a warning and compared fact by fact (L17).

### 3.4 image.lock

```
members:   {cook_a: {bundle: <h12>, source: <sha256 of the resolved AST>, includes: [{name, place: dir|root|home, path}]}, ...}
iface:     {protocol_domain.llp: <h>, director_tree_domain.llp: <h>, director_tree_wake.llp: <h>, director_domain.llp: <h>}
capacity:  {file: tick_types.llp, key: <h>}
places:    {root: <path>, home: <path or null>}
toolchain: {metisc: <version>, git: <sha>}
```

The lock is what `metis build` (§7) compares to decide what to recompile, and what two processes compare in
their handshake (§5.4).

## 4. The link step

`metisc --link composition.yaml [-o build/] [--bundles DIR] [--plan plans/x.yaml ...]`

Inputs: the composition, its manifests, the capacity and protocol files, and the members' bundles (built by
`metisc --wire` as today; `--build` builds the missing or stale ones first, by the lock's source hashes).
Output: the image directory, or the errors. `--interface` stays as the dry run: every I-check is an L-check.

### 4.1 Resolution

For every pred named in any member's `shared`, in `world`, or by the protocol:

- **nature**: from the protocol file named by the composition (`signal`, `level`, `report`, `resource`,
  `state`); never from the toolchain's own copy (closes gap 7). A pred with no nature is `state`.
- **producers / consumers**: from the members' `shared` directions and the world's `out` / `in`; the direct
  member's grants, goals, revokes and stops count as its `out` (spec 15 amendment 4).
- **world-private**: one copy per member, the host's sync; recorded, never routed.
- **resource**: owner = the direct member; count from the direct member's `resources`; holders = the members
  that declare it `resource`.
- **levels / beliefs / evaluate**: each name resolved against the member's wire (`I` atoms and `B` ports);
  the thresholds and names copied (closes gap 12).

### 4.2 Checks (L-checks; I1–I12 of spec 15 are L1–L12 unchanged, then:)

| check | rule | error |
|---|---|---|
| L13 members | the composition's `specialists` + `direct` = the set of members with bundles; `type domain` of the capacity = the SPECIALISTS exactly (the director is not a domain: road's `{responder planner}` is right, kitchen_pot's listing of its director is a corpus fix in A2); `type resource` = the resources the direct member owns | `link-members`, `link-types` (gaps 1, 2) |
| L14 capacity | every member's resolved AST includes the capacity file (by the lock's source hash) | `link-capacity` (gap 6) |
| L15 priority | `priority` is a strict partial order over the specialists: no self pair, no cycle, both ends declared | `link-priority` (gap 4) |
| L16 world.in | every `world.in` pred is produced by some member (a command) and consumed by no member | `link-world-in` (gap 5) |
| L17 roles | the derived `handles` / `result` / `specialist` facts agree with a hand-written director's, when one is given | `link-roles` (gap 8) |
| L18 clocks | every `clock.period` ≤ ρ − the plan's transport budget (per plan; with no plan, ≤ ρ) | `link-response` (gap 3; the end-to-end bound, checked per plan) |
| L19 keys | each member's `sidecar.key` = the wire's key (`Wire.Key` recomputed); the bundle hash = the directory's | `link-key` (gap 10) |
| L20 places | an include name resolves to one file across all members; `METIS_HOME` is recorded, and a link with the home unset while a member needs it is an error, not a silent miss | `link-places` (gap 11) |
| L21 host | `host:` names a `file:symbol`; recorded; the runtime's registry must match it or refuse (§6) | `link-host` (gap 9, the half the link can do) |
| L22 beliefs | a belief (continuous) pred is never `in`/`out`/`resource`; only its level atoms may be shared | `link-belief-shared` (spec 16 §8 preserved across members) |
| L23 levels | for each `levels:` / `beliefs:` / `evaluate:` entry: the weight port is declared in the member's wire (`B`), the level pred is level-first over `type level`, no belief pred appears in a count — LevelHook's refusals, moved to the link | `link-levels` (gap 12) |
| L24 protocol | every member's resolved AST includes the composition's `protocol:` file, by the lock's key; the injected `tick`, `tick_s`, `changed` are recorded in `protocol.tokens` as `injected` | `link-protocol` (gap 7, the other half) |
| L25 planner | exactly one planner (§3.3) | `link-planner` |

Warnings as today (listed, not judged): `iface-report-unsent`, a hand director's self-withdrawal, a
transitional producer.

### 4.3 What the link writes

`image.json`, `image.lock`, the copied bundles, the generated direct member's source and bundle, and for each
`--plan` the plan's table (§5). The image's hash is printed; `--check` prints it without writing.

## 5. Deployment plans and transport ports

### 5.1 A plan

```
processes:
  runtime: [cook_a, cook_b, pot_director]      # the domain runtime (Go today, Rust to come)
  agent:   []                                  # the metis agent / LLM process: a consumer of statuses and goals
transport: {carrier: socket, budget: 1}        # ticks of latency the link charges to ρ (L18)
```

A member belongs to exactly one process. The world host belongs to the process of the member that binds it
(a world shared by members in two processes is an error: `plan-world-split`).

### 5.2 Derived transport ports

For each entry of `ports` whose producers and consumers are not all in one process, the link derives a
TRANSPORT PORT: `{pred, nature, from: process, to: [process], latch: beat}`. The rules:

- only FINITE atoms cross: signals, levels, reports, resources' grant/release tokens, state preds, and
  quantised level atoms; a belief never crosses (L22), nor a weight;
- a transport port has one producing process (I4 across the boundary);
- the consumer latches at its next beat boundary, as a shared atom is latched within a process (spec 15's
  Moore latch); the stop is the one exception, director-first, and crosses with the same priority;
- the director's statuses and forwards cross when the direct member and a specialist are split; the
  director's own state (`free`, `priority`, `roles`) never does.

The plan's table is `plans/<p>.json`: the member assignment, the transport ports, and the plan's own hash.

### 5.3 The transport contract (carrier-independent)

A message is one tick's worth of atoms from one process to one port set:

```
M image=<h12> plan=<h12> from=runtime tick=<n>
+ tick__grant(cook_a,pot) 1
- tick__want(cook_a,pot) 1
.
```

One `M` header, then one line per atom: a `+`/`-` sign, the atom exactly as the wire's `I` line writes it
(`p(x,y)` with its multiplicity), then `.`. The receiver parses the atom lines with the wire's atom reader,
which both toolchains have; only the `M` header and the `.` are new (about twenty lines per toolchain). The
trace records the sender's tick and the receiver's latch beat for every message, so an interleaving replays.
The receiver
latches them at its beat, and refuses a message whose `image` or `plan` hash is not its own (§5.4). Ordering:
a process commits tick n, then sends tick n's atoms; a receiver applies tick n's message only after its own
tick n−1 is committed; a missing message past the transport budget is a `stuck` report to the director (spec
15 §9), never a silent wait.

The first carrier is two sockets (one per direction), line-delimited text, exactly the format above. ROS 2 is
a later carrier: one topic per transport port, the same lines in the message body, when a simulator behind ROS
2 is really needed (the user, 2026-10-28). The contract does not change between carriers.

### 5.4 The handshake

Each process, at load, sends `H image=<h12> plan=<h12> lock=<h> process=<name>` and refuses to tick until the
peer's `H` matches on all three. A mismatch is reported in the words of the lock: which member's bundle, which
iface file, or which toolchain differs.

## 6. The loader contract

A runtime loads an image and a plan (or the plan `all: [every member]`). It reads, and reads ONLY:

| from the image | the runtime does |
|---|---|
| `members` (its process's) | loads each bundle's wire and sidecar; the hosts by the recorded `file:symbol` — a Go registry must contain that name with that host, else refuse (`load-host-mismatch`) |
| `clock` | beats and period per member; a config file no longer names clocks (the py Live's `clocks` and `domains.names` and `v3.director` keys are removed; the config keeps the model, the console and the paths) |
| the direct member's bundle | runs the generated director in the process the plan puts it; never a hand-written one unless the image says `generated: false` |
| `protocol.tokens` | the natures, for latching and for the stop; the Live's literal token names become a table read from the image |
| `ports` and the plan's transport table | routing inside the process; the transport sender/receiver for the rest |
| `levels` / `beliefs` / `evaluate` | the hooks a host builds, from the image's tables, not from the manifest file |
| `image.lock` | the handshake |

What it never reads: `composition.yaml`, `domain.yaml`, `tick_types.llp`, the protocol `.llp`, the catalog
directory. A runtime that runs from source (the REPL, metispy's dev loop) builds the image in memory by the
same link function (metispy calls `metisc --link --check`, then loads the written image from a scratch dir);
there is no second resolver.

Consequence for the three runtimes today: the py Live drops its config-side assembly; the Go agent, which
has no tick layer, loads a one-member image through the same loader (the registry check is the new part);
the C++ loader is unchanged for the wire and gains `image.json` for the host check. The Rust runtime (r0.3
track B) is written against this contract from the start.

## 7. The driver and the project

`metis build [DIR]` (a subcommand of `metisc`, OCaml): read `DIR/composition.yaml`; for each member compare
the resolved AST's hash with the lock's; recompile the stale bundles (`--wire`); link; write the image; print
the hash. `metis check` = `--interface` + `--link --check`. A Makefile in a project is then one line:

```
build/kitchen_pot.image: composition.yaml $(wildcard */*.llp) $(wildcard */domain.yaml)
	metisc build .
```

Dependencies are packages, found by name by the include rule (the root, then `METIS_HOME`) and recorded in
the lock's `places`. Fetching a named package from a catalog release's bundle assets (`metis fetch NAME`) is
the registry half of the cargo model and is OUT of this proposal; the lock is shaped so it can hold a fetched
bundle's hash later.

The catalog's CI gate: `metisc build` on every composition in the catalog (kitchen_pot; road in
metis-worlds; alfworld hier and minihack mh_hier in metis-worlds), the image hash committed as a golden, and
the py Live loading each image for its goldens' cases.

## 8. Certification

The image is the certified object. The interface certificate (spec 15) and each member's cell table (spec 16
§8) are computed over bundles whose hashes the lock holds, so a certificate names an image hash and nothing
else. A plan does not enter the image hash, and the transport carries only finite atoms latched at beats, so
a split does not change what any member computes in a tick: the per-member proofs (the mixture theorem, the
cell bounds) hold unchanged, and the only new quantity the split adds is latency, bounded by L18 against ρ.
What a split does NOT preserve is the global tick order across processes beyond the latch rule; a property
that needs lockstep across the boundary must be stated against the message order of §5.3, which is what the
Lean lemma of track B2 (ordered commit on a logical clock) is for.

## 9. Rulings on the review's questions (metis, step 2; the architect)

1. The DIRECTORY is the image, hashed over a canonical file list (image.json, then members in order, each
   file by name), so `metis build --tar` writes an archive whose hash is the directory's.
2. The director is derived AT LINK; its wire is in the hash; a hand-written `direct:` is transitional (L17).
3. With no plan, an absent `response:` links with ρ = ∞ and a warning; a plan that derives a transport port
   REQUIRES `response:` (`link-response-required`).
4. TWO keys stay: the interface's member key hashes the resolved SOURCE AST (iface.ml:325), the sidecar's
   `key` hashes the GROUND program (nets.py:120; Go's `Wire.Key` recomputes it). The lock maps source key →
   program key per member; that pair is the build cache key of §7.
5. `METIS_HOME` unset at link is an ERROR (L20): the lock must say where the protocol came from.
6. `tools.json` once at the image root (`tools.json`), not per member; Go's orchestrator reads it from there.

## Amendment 1 (2026-10-28, wheelchair-design step 3): `hosts:` in composition.yaml

The world belongs to the composition, not to a member: a member consumed by name (road's responder in the
wheelchair image) must be hosted by the composition's world. `hosts: {member: <binding>}` in
`composition.yaml` overrides that member's manifest `host:` for this image; `image.json` records the
effective binding and its origin (`manifest` | `composition`); L21 checks the override as it checks a
manifest binding. A member not named in `hosts:` keeps its own.

## Amendment 2 (2026-10-28, wheelchair-design step 3 review)

- **L15 closes `priority` transitively**: the strict order the link checks and records is the transitive
  closure of the declared pairs; a cycle anywhere in the closure is `link-priority`.
- **An endpoint is a member.** A process with no member derives no transport port, because only shared preds
  between members cross (§5.2). A person, a console or a sensor bridge that must exchange atoms with the
  members is therefore a thin MEMBER (a manifest with `shared:` and a host, no program rules needed beyond
  its declarations), placed in its process by the plan. There is no world endpoint per process.
- A composition may set a member's parameters the link records (the planner's vru role count j in road):
  `params: {member: {name: value}}`, hashed into the image.

## 10. Plan rules the runtimes impose today (from the review's §5)

- A member with `levels:` / `beliefs:` / `evaluate:` sits in a process whose runtime builds the hook (py
  today); its level atoms cross as transport ports. `plan-levels-runtime` otherwise.
- A process that holds the direct member AND specialists needs a tick layer; Go has none, so until track B
  (the Rust runtime) lands, such a process is py. The wheelchair's runtime process depends on B.
- Go's registry beats (process.go:173) vs the image's `clock.beats`: `load-beats-mismatch`, refuse.
- The py Live's config → image move (svc:291, 293, 328, 383, the token literals at svc:580–952) touches every
  Live config: A2 carries it with the config files of the catalog's cases.
