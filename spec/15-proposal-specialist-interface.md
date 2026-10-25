# PROPOSAL 15 — the specialist interface: the static rule×pred graph, the manifest's directions, the composition contract

**Status: PROPOSED 2026-10-25, design only, no code (specialist-tree s-404d001f step 1b, metis). It writes down
what brief v2 §8 ruled: the tick is ONE program, built by a COMPOSER from separate specialist domains. Its
examples are the two hierarchies that exist: metis-worlds alfworld `domains/hier` and minihack `mh_hier`. The
manifest field names are nina's provisional ones (`shared`, `status`, `capacity`). This spec renames none of
them; it adds three fields, each with its reason (§2.3).**

**Amendment 1, 2026-10-25 (metis, from nina's review; ruled by the architect on s-404d001f, with ruling v3):**
- (a) A fourth direction, `world-private`: a world reading each stage or session holds through its own binding
  (§2.1). It is exempt from I3/I4, so the hands and the position are contention only when a composition shares
  them (§3, §5).
- (b) Statuses are derived from the trace rows' stage, and the host asserts `tick__status(S, k)`. There is no
  `tick__fired` head atom (§4.4).
- (c) Ruling v3: the runtime already EXISTS as N DomainAgent sessions, with the host's semantic map as the
  blackboard. §4 is therefore the COMPOSITION contract in two forms:
  - (S) today's sessions, the host relaying what the direct stage would link — step 2, incremental on today's
    Live;
  - (P) one program with stages, built by the composer — deferred.

  The checks I1–I7, the directions and the composition manifest are the same in both forms.

**Amendment 2, 2026-10-25 (metis, from the user's questions: brief v4 §9 on s-404d001f): §8.**
- A composition is ONE certifiable package. Its certificate is the package key, plus the I-checks, plus each
  domain's own key.
- The composite measure factorizes by the tick.
- Copies per port replace `!` for readings and signals; `!` (bwd) is kept for statics.
- A PROTOCOL module is a third kind of member: specialist → protocol ← director, a DAG checked by I8.
- The tick rules: change-or-clock beats, Moore-latched outputs, no beat on one's own echo, and hysteresis in
  the director's rules.

The composer stays shelved; everything in §8 is stated for form S and maps onto form P.

**Amendment 7, 2026-10-25 (metis, nina's step 3b rulings: design v8 §13 on s-404d001f):**
- §8.4: a STOP is a CANCEL, distinct from a REVOKE. A revoke takes the body and keeps the goal; a cancel takes
  the goal. The protocol gains `tick__stop`, the agent's one-tick signal that the person said stop (world
  `out`, director `in`), and `tick__cancel(D)`, the director's signal to the members on its path, sent by
  `stop_cancel` as it pops them. Every member carries a generated protocol stub, a begin and a cancel rule
  per goal kind, and one absorb rule for the done-and-stop race: the member gives back `idle` and drops the
  goal itself. The agent only relays `tick__cancel(D)`, like any director `out` to a member `in`; it reads no
  member state, withdraws nothing and reloads nothing.
- §10.4: a case binds the program's weight ports to constants, `ports: {look: 1.0}`: numeric only, an unknown
  port name refused by name.

**Amendment 6, 2026-10-25 (metis, the beast case rulings: design v7 §12 on s-404d001f):**
- §2.3: a composition declares its RESPONSE TIME ρ, `response:` in `composition.yaml`. A member whose trigger
  reads a world horizon derives the horizon from ρ. Declaration only for now, no I-check; ρ is in the
  package key.
- §8.4: requests are idempotent by key. A member already handling a thing absorbs a second request for it and
  still owes the requester's report; the director's forward to an already-active member pushes nothing.

**Amendment 5, 2026-10-25 (metis, specialist-tree step 3b rulings):**
- §8.4: the tree director's BASE is generic and lives in metispy's `iface/` beside the protocol module; a
  composition supplies only its instance.
- §8.5 rule 1: a member whose world changes without the ego is a CLOCK SOURCE and must declare a clock period;
  rule 1 binds composition members only.
- §8.5 rule 4: its one exception, preemption by a declared `priority(P, Q)`, and the ticket queue the
  generic base keeps.
- I5: the manifest's `gating: host | program`, checked against the member's reads of `tick__grant`.
- I8 allows a SHARED LIFTED DOMAIN FILE: a base of rules several members instantiate (kitchen_pot's
  `cook_domain.llp` for cook_a and cook_b). It must be no member's top file and lie in no member's package
  directory. A member including another member's program or package stays refused. The listing notes the
  sharing, and the base's key enters each instance's EI(S).
- I3 on protocol REPORT preds: a report no member sends (`tick__active`, `tick__stuck` in a sequential
  composition) is a warning, "a report nobody sends"; signals and resources keep the error.
- Includes resolve in three places (spec 00 §4); `protocol:` names `iface/protocol_domain.llp` under
  `METIS_HOME`.

**Amendment 4, 2026-10-25 (metis, the architect's rulings on step 1c, `metisc --interface`):**
- I3 counts two transitional producers: the director's relay facts, and the host's `tick__status`. Both are
  marked in the listing.
- I4 lets the direct member withdraw its own grants and goals, as a warning.
- `composition.yaml` gains an optional `interfaces: [...]`.
- Natures come from a sidecar `<package>.yaml`.
- §6's check is implemented.

**Amendment 3, 2026-10-25 (metis, from the user's deployment and modularity points: brief v5 §10, v6 §11):**
- **§9, the deployment view.** The BUNDLE is a composition package selected and sealed for a device, plus a
  runtime manifest, with OTA compatibility by interface keys. Further: the WAKE SET (form S only); actors with
  stamped messages, `age`, and grants as LEASES; F3 "deterministic given the message order", so the journal is
  the replay oracle.
- **§10, interface packages and a specialist's external interface.** Shared preds are owned by interface
  packages, each pred with a nature. New checks I10–I12. Testing a specialist alone uses a generic interface
  stub; a specialist's certificate never depends on a director.

## 0. Scope

- **In:**
  - §1: the STATIC rule×pred dependency graph of a catalog, and of a composition. This is not spec 09's graph,
    which is the causality of one run.
  - §3: the interface check on that graph, and the cut it reports.
  - §2: the manifest fields that carry the interface: a direction per shared pred per specialist, the
    optional status atoms, and the capacity instance.
  - §4: the composition contract. N specialist domains, a direct domain and a capacity instance compose,
    either as today's N sessions with the host relaying (form S), or as one program with a stage per
    specialist and a direct stage (form P, the composer, deferred). Both have a broadcast copy of each signal
    per consuming subscriber and requests/grants for resources. The flat-program equivalence is claimed only
    for the sequential special case (§4.6).
- **Out:**
  - The runtime itself (step 2: incremental on today's sessions, ruling v3).
  - Argument-level (ground) cuts (§7).
  - Any change to spec 09's run graph, or to the kernel's semantics. The composed program is an ordinary
    catalog; everything here is a compile-time transformation plus a check.

## 1. The static rule×pred graph

### 1.1 One catalog

For a catalog K, G(K) is the bipartite graph with:
- one node per rule and per link (the *rules*);
- one node per `pred` (the *preds*), and per `bwd`, which matter as guards only.

Each body atom of a rule gives an edge pred → rule, labelled with what the rule does to it:

| label | the body atom | example |
|---|---|---|
| `c` consume | a linear atom of a `pred` | `goto(R)` in nav's `go` |
| `r` read | a `$`-atom of a `pred` (persist: read, not consumed) | `$recat(R, L2)` |
| `g` guard | an atom of a `bwd` (the Horn world; never consumed) | `$target(O)` in task |

Each head atom gives an edge rule → pred, labelled `o` (produce).

A link contributes the same edges from its pre and post atoms. Its stage endpoints are not preds. `one` and `()`
add nothing.

**The role of a pred in K** is `roles_K(p) ⊆ {c, r, g, o}`, the union of its edge labels. It is a property of
the lifted rules, independent of any instance. The arguments are ignored: the graph is over predicate
symbols. Two consequences of that, both deliberate:
- `goto(R)` consumed and `goto(dest)` produced are the same node;
- the check is sound only up to that abstraction (§7).

Today the toolchains compute the run-level causality (spec 09: events and the atoms between them) but not this
graph. G(K) needs only the catalog (`k_entries`: `cs_consume`, `cs_persist`, `cs_guards`, `cs_produce`, and the
link schemas). It is linear in the rule text and needs no grounding.

### 1.2 What the two hierarchies look like (measured on their sources)

Role strings are `c`/`r`/`o`; `-` means declared but on no rule. bwd preds are omitted. The roles were
extracted from the committed sources: alfworld `domains/hier/*_domain.llp` and `domains/director_domain.llp`;
minihack `world/mh_hier.py` `base(spec)`. The director domain is byte-identical between the two worlds, apart
from comments.

**alfworld hier**

| pred | nav | access | grasp | place | task | director |
|---|---|---|---|---|---|---|
| `goto` | c | | | | o | |
| `reached` | o | | | | c | |
| `open` | | c | | | o | |
| `accessible` | | o | | | c | |
| `take` | | | c | | o | |
| `taken` | | | o | | c | |
| `put` | | | | c | o | |
| `placed` | | | | o | c | |
| `refused` | | **-** | o | o | c | |
| `elsewhere` | | o | o | o | | |
| `at` | **cor** | r | r | r | | |
| `recat` | r | r | r | r | | |
| `inrecep` | | | **cr** | **o** | r | |
| `objat` | | | **cr** | **o** | | |
| `holds` | | | **o** | **c** | r | |
| `holding` | | | **or** | **c** | | |
| `handsfree` | | | **c** | **or** | | |
| `opened` | | **or** | r | r | | |
| `closed` | | c | r | r | | |
| `openable`, `notopenable` | | r | r | r | | |
| `fetch` | | | | | c | |
| `done`, `stuck`, `wrong_dest`, `wrong_object` | | | | | o | |
| `absent`, `believed`, `lost` | | | | | r | |
| `want`, `start`, `carry`, `to` | | | | | co / co / co / or | |
| `checked` | | o | | | | |
| `active`, `inactive`, `fresh`, `sent` | | | | | | cor |
| `attention`, `pending`, `rerouted` | | | | | | co |
| `seen`, `idle` | | | | | | c |
| `wake`, `sleep`, `forward`, `ask`, `ended` | | | | | | o |

**minihack mh_hier**

| pred | nav | act | task |
|---|---|---|---|
| `goto` | c | | o |
| `reached` | o | | c |
| `closed`, `guarded` | o | | |
| `open` | | c | |
| `fight` | | co | |
| `opened`, `cleared` | | o | **-** |
| `refused` | | **-** | c |
| `agent_at` | **cor** | r | |
| `step`, `door`, `monster`, `next` | r | r | |
| `toward`, `stairs_down` | r | | |
| `said` | | c | |
| `tried`, `kicked`, `swung` | | co | |
| `reach` | | | c |
| `want` | | | co |
| `done`, `stuck` | | | o |

Today each specialist declares these preds in its OWN namespace (`pred at(location) : access.`), so in the
kernel they are distinct preds that happen to share a name. Sharing happens outside the language: the director
instance's `handles`/`result` facts, and the host forwarding an atom by its name (its *kind*). This spec moves
that sharing into declarations the composer and the check can read.

### 1.3 A composition

A composition Π = (S₁…Sₙ, D, W, C): n specialists Sᵢ, a direct domain D, the world W (the host's ports, §2.3)
and a capacity instance C.

G(Π) is the union of G(Sᵢ) and G(D), with the world as one more node set, after the renaming of §4.2.
- Private preds stay inside their specialist's subgraph.
- The **cut** is the set of preds whose edges touch two or more of {S₁…Sₙ, D, W}.

## 2. The manifest fields

### 2.1 Per specialist (nina's fields, unchanged)

```yaml
# nav's specialist manifest (the composition reads it; domain.yaml keeps its existing keys)
program: nav_domain.llp           # the LIFTED domain file (abstract types, spec 12)
shared:                           # every pred not listed here is PRIVATE to nav
  goto: in
  reached: out
  at: world-private               # read through nav's own binding (amendment 1a)
  recat: world-private
  motion: resource
status:                           # optional (brief §8 C)
  success: [reached]
  failure: []
```

- **`shared: {pred: in | out | resource | world-private}`.** The direction is per (pred, specialist), per ruling A1. The same
  pred may be `out` for one specialist and `in` for another.
  - **`in`**: the specialist reads (`r`) or consumes (`c`) the pred and never produces it for others. A head
    occurrence of an `in` pred in this specialist's own rules is a *self-continuation*: the composer renames it
    to the specialist's own copy (§4.3), as minihack act's `fight_on` re-produces `fight(P)`.
  - **`out`**: the specialist produces it (`o`). It may read it. It may consume it only as the pred's
    **single writer**: every rule of the specialist that consumes it also produces it (state, not a signal),
    and no other specialist consumes it (§3, I4). nav's `at` is such a case.
  - **`resource`**: the specialist's requests compete for this token (ruling A3). Its rules never consume or
    produce the resource itself. It emits request atoms (its own `out` preds), and the direct stage's grant
    rules consume a request together with the token (§4.5).
  - **`world-private`** (amendment 1a): a world reading the host syncs into THIS specialist's own copy,
    through this specialist's own binding.
    - In form S that is exactly today's per-session reading. In form P it is the private copy `S__p`, written
      by the host's sync of that stage.
    - The specialist may read, consume or produce its copy (its model's prediction); the next sync settles it.
    - It never crosses to another member, so I3 and I4 do not apply to it.
    - The reason it is not `in`: in alfworld's view mode each host reads the world through a different binding,
      frozen for a woken specialist and live for the planner. So nav's `at(lhere)` and task's `at(lhere)` can
      be different facts, and one shared atom would be wrong.
    - An `in` reading that is shared (one atom, §4.3) is only right when every consumer reads it through the
      same binding.
- **`status: {success: [...], failure: [...]}`**: optional atoms whose production this tick IS the
  specialist's success or failure (ruling C). Each listed atom must be one of the specialist's `out` preds.
  Without `status`, the specialist's status is only `running` (some rule fired this tick) or `idle` (none did).
  `stuck` versus `idle` is not derivable without it (objection C).
- **`capacity`**: the capacity instance this specialist was written against (§2.2). It is a reference, not a
  copy: the composer checks that every specialist names the same one.

### 2.2 The capacity instance and abstract types (spec 12)

A specialist is a LIFTED domain:
- `types (receptacle location object).` names the types it is written over (spec 12 P1);
- its committed instance today (`nav/nav.llp`) only includes the domain and `capacity.llp`.

The composer replaces those per-specialist instances with ONE capacity instance for the composition, so:
- **An abstract type name is an interface type.** `receptacle` in nav and `receptacle` in task are the same
  type in the composed program, and the capacity completes it once. Two specialists that declare the same
  abstract name and expect different members are a finding (I6). It cannot be resolved by renaming, because
  the shared preds' signatures range over it.
- **A concrete type declared by a specialist** (`type dir {…}` in minihack nav) is private unless a shared
  pred's signature mentions it. If a shared pred does mention it, every specialist that shares the pred must
  declare it identically (I6).
- **The capacity instance is the only place a type gets members.** A composition that leaves an abstract type
  incomplete is refused at grounding (spec 12 P3), as today.

### 2.3 Added: the composition manifest, the direct domain's resources, the world's ports

nina's fields are per specialist. The composer also needs three things no specialist can say. These are
**additions, not renames**:

```yaml
# the composition (one file per tree; nina's composer reads it)
capacity: capacity.llp
specialists: [task, nav, access, grasp, place]   # also the stage order within a tick (§4.4)
direct: director                                 # the direct domain (the tree, the path, the grants)
response: 2                                      # ρ, ticks from tick__want to the latched grant (amendment 6)
world:                                           # the host's ports, as a peer with directions
  out: [at, recat, openable, notopenable, opened, closed, inrecep, objat, absent, believed, lost, fetch]
  in:  [goto, open, take, put]                   # the commands the host executes
```

```yaml
# the direct domain's manifest (in addition to shared/status)
resources:
  motion: {count: 1, held_by: [moving]}          # §3 I5: motion + Σ moving(·) is invariant, = count
```

- **`specialists`.** The composition has to list its members and their order somewhere, and a specialist
  cannot list its peers. The order is the stage order of the tick (§4.4). Ruling A3 makes the order unable to
  decide a resource, but it still decides which specialist sees a signal first within a tick.
- **`interfaces`** (optional, amendment 4): the family interface packages (`iface/<family>.llp`, §10.1)
  besides the protocol module (`protocol:`). Paths are relative to the composition file.
- **`response`** (amendment 6): the composition's RESPONSE TIME ρ, the ticks from a member's `tick__want`
  to the latched grant. Under the generic tree director (§8.4) ρ = 2: the want at t, the preemption at t+1,
  the latch at t+2. A clock period (§8.5 rule 1) multiplies it in world turns. A member whose trigger reads a
  world HORIZON (a reach, a safe distance) derives the horizon from ρ, because a trigger that looks ahead by
  less gets the body after contact. (opus's beast case: with ρ = 1 the preemption landed after nav's
  `in_way` had met the newt.) Declaration only for now: it is checked against the director's measured
  latency later, with no I-check today. `metisc --interface` checks nothing on it, but the field is part of
  the canonical composition, so ρ enters the package key (§8.1): a composition re-sealed with another ρ is
  another package.
- **`world`.** Check I3 ("every `in` produced by a peer or by the world's ports") needs the world's ports by
  name and direction. Today the host projects into any pred it likes; a composition must say which. The
  default derivation is from the domains' `input`/`output` port declarations (spec 00 `port`) where they
  exist; neither hierarchy declares any today.
- **`resources`.** "Owned once" (I5) is a count invariant over the token and the atoms that hold it. Only the
  direct domain, which owns the grants, can name the holding atoms.

### 2.4 Reserved names

Composer-generated preds contain `__` (§4). So:
- a domain pred whose name contains `__` is refused (I7);
- the status kinds `running`, `success`, `failure` and `idle` are constants of the reserved type `tick__status`,
  never preds.

That is why dog's own `idle` atom (objection C) cannot clash: it is a pred of dog's, and the status is a
constant in another namespace. The lexer already allows `_` in identifiers, so no domain changes syntax; the
only rule is "no `__`". A search of the 175 committed `.llp` files (metis-worlds, metis-catalog, the corpus) finds no `pred` or `bwd` containing `__`.

## 3. The interface check

The check runs on G(Π) after the renaming of §4.2. Each failed condition is a structured diagnostic (spec 08)
of severity error unless marked. The codes are the `iface-*` family, added to the registry.

| | condition | on the examples |
|---|---|---|
| **I1** private stays private | A pred NOT in a specialist's `shared` map is renamed `S__p` (§4.2) and so cannot appear in another stage. The check refuses a pred that one specialist lists as shared and another declares without listing, because it is ambiguous whether they mean the same atom (`iface-shared-unlisted`). | `refused`: grasp, place and task must all list it; access declares it too, so access lists it or drops the declaration |
| **I2** direction agrees with the roles | `in` ⇒ no `o` except self-continuation; `out` ⇒ `o` ∈ roles; `resource` ⇒ the pred is absent from the specialist's rules (`iface-direction`). | alfworld access lists `refused: out` but no rule produces it (`refused: -`): finding; minihack act's `refused` is the same. minihack task declares `opened`, `cleared` (`-`): an `in` nobody reads, a warning (`iface-in-unread`) |
| **I3** every `in` has a producer | `world-private` preds are exempt (their producer is the host's sync). For each (S, p: in), some peer has p: `out`, or p ∈ `world.out`, or D produces p (`iface-in-unproduced`). **Transitional producers (amendment 4):** the direct member's relay facts (today's director: `detour(K1, K2)` sends K2, `rename(K1, K2, G)` sends G) count until §8.4's `goal(S, K)` replaces them; the host's `tick__status` (amendment 1b) counts as host-produced. The listing marks both `transitional`. **Amendment 5:** an unproduced `in` whose nature is `report` (a protocol report no member sends) is a warning, "a report nobody sends"; signals and resources keep the error. | alfworld `fetch`: task's `in`, produced by the world (the person's goal, `world.out`); minihack `reach` alike |
| **I4** one writer of a state pred | `world-private` preds are exempt: one copy per member, one writer per copy (the host's sync). A shared pred consumed by more than one member (specialist, D, or the world as writer) is a contention point. It must be a `resource` (I5) or a broadcast signal, one copy per consumer (§4.3) (`iface-multi-writer`). An `out` consumed by its producer must be conserved per rule (`c` and `o` in the same rule). **Amendment 4:** a director's grants and goals are LEVELS it may withdraw (as §9.3's revoke and expire do), so the direct member's self-withdrawal is a warning, not an error; specialists keep the rule. | alfworld `holds`/`holding`/`handsfree` (grasp writes, place writes) and `inrecep`/`objat` (grasp consumes, place produces): two writers of the body's state, the hands. Either a `hands` resource with grants, or world-owned readings (`world.out`) with grasp/place's writes turned into requests. alfworld `at` / minihack `agent_at`: nav consumes and re-produces (`cor`), and the host also asserts it. One writer must be chosen: the world (nav's `go`/`move` become requests for `motion`) or nav (the host stops asserting it). Under `world-private` (today's per-session reading, amendment 1a) neither set is contention; the finding fires only for a composition that SHARES these preds |
| **I5** every resource owned once | **Gating (amendment 5):** a member's manifest declares `gating: host` (the default: the agent holds a command until its grant, and the member never reads `tick__grant`) or `gating: program` (the member gates itself: its rules read `tick__grant` for every resource it declares). Each is checked against the member's rules. For each resource p with `count` n and `held_by` H: every rule of the composition that mentions p or an atom of H has Δ(p) + Σ_{h∈H} Δ(h) = 0 (a P-invariant of the net), and the direct domain's init holds exactly n of p and none of H. Only D's rules consume p (`iface-resource-*`). | `motion`, count 1: `grant: want_move(D) * motion -o moving(D)`, `release: moved(D) * moving(D) -o motion`; nav and act both list `motion: resource` (the beast case) |
| **I6** types agree | Same abstract name ⇒ same type, completed once by the capacity. A concrete type used by a shared pred is declared identically everywhere (`iface-type`). | minihack nav and act both declare `type dir {n e s w ne se sw nw}` for `next(cell, dir, cell)`: identical, OK |
| **I7** reserved names | No domain pred contains `__`. Status atoms are `out` preds of their specialist (`iface-reserved`, `iface-status-not-out`). | none today |

**The cut report**, always produced, never an error. The cut is the shared preds, each with:
- its producers and consumers (with the c/r split);
- its class: signal (consumed: broadcast), reading (only read: one atom), resource, or state (single writer).

It also gives two sizes: |cut| and the private remainder per specialist. It flags, as a note, the
**call/return smell** from brief §2 as amended by A5: a shared pair (p out of A and in of B, q out of B and in
of A) where neither p nor q is in `world` or read by D.
- In alfworld, `goto`/`reached` is not flagged, because `reached` is a world fact the host also asserts.
- In minihack, `goto`/`reached` between task and nav is flagged as a note: nobody but task reads `reached`.

The note is information for the author, not a refusal. A5 accepts the return address as intended.

## 4. The composition contract (amendment 1c: two forms)

The same contract holds in two forms. Every element below says what it is in each.

| element | form S: N sessions (today's runtime; step 2) | form P: one program with stages (the composer; deferred) |
|---|---|---|
| a specialist | its own DomainAgent session (its own Repl and RNG) | `stage S`, with its private preds renamed `S__p` |
| privacy | separate sessions: nothing crosses unless relayed | renaming (§4.2) |
| `world-private` p | the session's own reading, synced by the host through that session's binding (today's behaviour) | `S__p`, written by the host's sync of stage S |
| a shared `in` reading | the host syncs one fact into every subscribing session through ONE binding | one atom p, read by every subscriber |
| a broadcast signal | the host asserts one copy into each consuming session | `p__S` copies; producers emit their tensor (§4.3) |
| the tick | each session runs to quiescence (or to its beat) on the tick; then the director session | links at quiescence, `(S₁ … Sₙ direct)` (§4.4) |
| reports in | the host relays each specialist's `out` reports and status into the director session, as it relays chain goal/result today | `out` atoms consumed by `direct`, as copies |
| grants out | the director session's grant rules produce the holding atom; the host syncs the grant into the holder's session | `direct`'s grant rules (§4.5) |
| statuses | from each session's trace rows; the host asserts `tick__status(S, k)` into the director session | from the trace rows' stage; the host asserts `tick__status(S, k)` at the S→direct link |

The checks I1–I7 (§3), the directions (§2.1) and the composition manifest (§2.3) are the same for both forms.
In form S, what the host relays is exactly what form P's links and copies would carry. §4.1–4.6 give form P in
detail; form S reads them through this table.

### 4.1 Inputs

- The composition manifest (§2.3).
- n specialist domains, each a lifted domain file with its manifest (§2.1). Each must compile alone
  (`metisc FILE.llp`, spec 12 step 2).
- The direct domain D: a lifted domain with `shared`, `status` and `resources`. The director domain becomes
  D, with its instance facts DERIVED (§5).
- The capacity instance C: the only `type … {…}` source for abstract types.

### 4.2 Renaming (privacy)

For each specialist S and each pred p declared by S:
- **p private to S:** every occurrence in S's rules becomes `S__p`, declared in a namespace `S`
  (`namespace S produce (<S's layers>).`). Two specialists' private `at` become `nav__at` and `access__at`:
  distinct atoms, exactly as today's per-domain sessions have them.
- **p shared:** the occurrence keeps the name p, except a consumed `in` (§4.3). The pred is declared once, in
  the composition's shared namespace `tick`. Its signature must be identical across its declarations (I6).

The same applies to D (private preds become `direct__p`) and to the world's ports (which are shared by
definition).

### 4.3 Broadcast (ruling A1, A2)

For a shared pred p:
- **Read-only subscribers** (role `r` in S, `in`): read the single atom p. One atom suffices because reading
  does not consume, so nothing needs to be copied (no contraction). By A2 such a p must be a *reading* the
  world or a single writer owns. A peer's signal read with `$` is refused (`iface-signal-read`), because
  nothing would ever retract it and the reading rule would re-fire every tick (objection A2).
- **Consuming subscribers** (role `c` in S, `in`): each gets its own copy `p__S`.
  - S's body occurrences become `p__S`, and so do its self-continuation heads.
  - Every producer's head occurrence of p (a peer's `out`, D's, or the world's assertion) becomes the tensor of
    all copies, `p__S₁ * … * p__Sₖ`, in the composition's specialist order.
  - The world's assertion of p is mapped by the host onto the same copies. The composer emits that port map.

The composite's meaning for such a p is the product with explicit broadcast. It is not the flat program's
single atom, which is objection A1 and why §4.6 is restricted.

### 4.4 Stages and links

- **The stage order** is `stages (S₁ … Sₙ direct)`, from `specialists` plus `direct`.
  - Each S's rules go to `stage S`.
  - D's rules go to `stage direct`.
  - A domain's own `stages (act)` header collapses into its composed stage. A specialist with more than one
    stage keeps them as `S__<stage>`, in its own order, with its own links.
- **Links at quiescence.** `qui S_i__next [dyn] : S_i -o S_{i+1}.` for i < n, `qui S_n__next [dyn] : S_n -o
  direct.`, and `qui tick [dyn] : direct -o S_1.` The links tier fires only when the stage has no clause
  enabled, so "to quiescence" is the kernel's own notion. A stage with nothing enabled passes through without
  a draw: an inactive specialist costs no randomness (ruling D's "inactive stages guarded with no draws").
- **For worlds that never quiesce** (RDDL), the beat boundary of `domain.yaml`'s clock replaces quiescence
  (ruling B). The composer emits the same links, and the clock bounds the beats per stage. That is the host's,
  as today.
- **Status (amendment 1b).** No instrumentation: the specialist's rows stay untouched (ruling D).
  - The status of S this tick derives from the trace rows whose event belongs to S's stage (form P) or session
    (form S):
    - `success` if one of them produced a `status.success` atom;
    - `failure` if one produced a `status.failure` atom;
    - `running` if any row fired;
    - `idle` if none fired.
  - The host asserts `tick__status(S, k)` into the direct stage at the S→direct link (form P), or into the
    director session (form S). For D, that atom is a world-in reading written by the host.

### 4.5 Requests and grants (ruling A3)

- A specialist with `motion: resource` has acting rules that produce a request (`want_move(D)`, an `out`) and
  never `motion`.
- D's grant rules consume a request and the token, and produce the command for the world (`world.in`) plus a
  holding atom from `held_by`.
- D's release rules consume the holding atom on the world's acknowledgement, or on a status, and return the
  token.

Arbitration is therefore D's rules, a CHOICE in one measure (objection A3 dissolved). A specialist without the
grant keeps its request, so its state is never ahead of the world (A4 dissolved). The priority between two
requests is D's rule weights or guards, never the stage order: requests from S₁ and S₂ are both present when
D's stage runs.

### 4.6 Output, and the one equivalence claimed

The output is one ordinary `.llp` catalog. It compiles with today's metisc and grounds through the capacity,
with nothing new in the kernel. It comes with:
- the port map (the world's ports → atoms and copies);
- the cut report (§3);
- the diagnostics.

**Equivalence is claimed only for the sequential special case**, when all of these hold:
- exactly one specialist is active per tick, the others' stages passing through with no draw;
- every broadcast pred has exactly one consuming subscriber, so no copies exist;
- no resource is contended;
- D's rules are the director domain's derived instance (§5).

In that case, the composed run's world-facing stream (commands, lines, map, card) equals today's
DirectorHost sequential run, together with the kernel's own trace per specialist (ruling D). Outside that case
the composition is a different program: the product with broadcast and arbitration. That is its point, and it
is stated as such.

## 5. The examples: today's director instance is a manifest

The generated director instance (`gen_hier.py`: `handles`, `result`, `end`, `finished`, `detour`, `escalate`,
`rename`) is a hand-compiled interface. It derives from the manifests:

| director fact | from the manifests |
|---|---|
| `handles(D, K)` | `K: in` in D's `shared` (alfworld: nav/goto, access/open, grasp/take, place/put, task/fetch, reached, accessible, taken, placed, refused) |
| `result(K)` | K ∈ some specialist's `status.success` (reached, accessible, taken, placed) |
| `finished(K)` | K ∈ the planner's `status.success` (task: done) |
| `end(K)` | K ∈ the planner's `status.failure` (task: stuck, wrong_dest, wrong_object) |
| `detour`/`escalate`/`rename` | D's own rules and facts (the tree): not derivable, and not meant to be |

So the alfworld manifests, read off §1.2 with today's behaviour kept, are:

| specialist | shared | status |
|---|---|---|
| task | fetch: in; reached, accessible, taken, placed, refused: in; goto, open, take, put: out; done, stuck, wrong_dest, wrong_object: out; inrecep, holds, absent, believed, lost: in | success [done], failure [stuck, wrong_dest, wrong_object] |
| nav | goto: in; reached: out; at, recat: world-private | success [reached] |
| access | open: in; accessible, elsewhere, refused: out; at, recat, openable, notopenable, closed: in; opened: out (single writer) | success [accessible], failure [refused, elsewhere] |
| grasp | take: in; taken, refused, elsewhere: out; holds, holding, handsfree, inrecep, objat: world-private (the hands) | success [taken], failure [refused, elsewhere] |
| place | put: in; placed, refused, elsewhere: out; the same world-private set as grasp | success [placed], failure [refused, elsewhere] |

minihack mh_hier:

| specialist | shared | status |
|---|---|---|
| task | reach: in (world); reached, refused: in; opened, cleared: in (warning: unread); goto: out; done, stuck: out | success [done], failure [stuck] |
| nav | goto: in; reached, closed, guarded: out; agent_at: world-private; step, door, monster, next, toward, stairs_down: in (world readings); motion: resource (with act) | success [reached], failure [closed, guarded] |
| act | open, fight: in; opened, cleared: out; refused: out (finding: no producing rule); agent_at, step, door, monster, next: in; said: in (world, consumed: its own copy); motion: resource | success [opened, cleared], failure [refused] |

What the check reports on today's sources, before anyone writes a manifest:
- **Errors**:
  - alfworld access's and minihack act's `refused`: declared and listed `out`, never produced. The host
    asserts it today, so it is a `world.out`, not the specialist's.
- **Two sets that are `world-private` today** (amendment 1a):
  - the hands in alfworld (grasp and place both write `holds`, `holding`, `handsfree`, `inrecep`, `objat`);
  - the position in both trees (`at`/`agent_at`: nav and the host both write it).

  Declared `world-private`, which is what today's per-session runtime does (each session its own copy, synced
  by its own host), neither is contention. They become I4 findings only if a composition declares them shared
  (`in`/`out`) across members. That choice (world-private vs a shared reading vs single writer vs resource) is
  a modelling decision no tool can default. The tables above declare them `world-private`.
- **Notes**:
  - minihack task's unread `opened`/`cleared`;
  - minihack's `goto`/`reached` call/return pair.

## 6. Toolchain

- **`metisc --interface COMPOSITION.yaml`** is IMPLEMENTED (specialist-tree step 1c, 99f9e77; amendment 4).
  - It reads `composition.yaml` and each member's `domain.yaml` as a strict YAML subset: `key: value` per line,
    flow lists and maps; block YAML is refused with its line.
  - It computes G(Π) per member (which file declares each pred), checks I1–I12, the cut report (the class of
    each shared pred, the private remainder, the call/return smell as a note), EI(S) and ei_key per member, and
    the package key.
  - The output is a listing on stdout ending `result N error(s), M warning(s), K note(s)`. The exit code is 1
    when N > 0.
  - Spec 08 rows (`iface-*` codes in the D2 registry, one fixture row each) follow in a two-repo step with
    metispy.
  - `ci/check.sh` gate 13 diffs the listings of `corpus/iface/*` against `corpus/goldens/iface/`: the alfworld
    and minihack tree installs, one broken composition per check, a clean one, and the reader's refusal.
- **`metisc --compose COMPOSITION.yaml`** (form P, deferred by ruling v3): writes the composed `.llp` and its
  port map. A composition that fails the check is not written. The check (`--interface`) serves both forms.
- **metispy at byte parity**, as for every compile surface. nina's composer (step 2) can call either, or
  implement §4 itself against these goldens.
- **Goldens**: the two compositions of §5 (cut reports, diagnostics, composed files), plus a sequential
  equivalence case (§4.6) per tree.

YAML is the manifests' existing format. metisc is stdlib-only, so the composition file would need either a
minimal YAML subset reader (the manifests here are flat maps of lists) or the `.llp`-side syntax of §7 Q1.

## 7. Open questions, for the ruling

1. **Manifest in YAML or in the language?** Directions could be declared in the domain file (`shared goto :
   in.`) so the kernel's own typecheck sees them. YAML keeps nina's composer unblocked now. Recommendation:
   YAML first, the language form only if a second consumer appears.
2. **Argument-level cuts.** G is over pred symbols. `refused` is one node here, but the sources give it four
   signatures: `refused(object)` in grasp, `refused(receptacle)` in access and place, and `refused(thing)` in
   task. I6 refuses them as one shared pred, so
   the composition must rename one, or type them as one sum type. That is the price of predicate-level
   sharing. Recommendation: refuse, and let the author rename (`refused_take`, `refused_put`).
3. **Stage order within a tick.** Only the order of signal visibility depends on it (A3 removes it from
   resources). Should D also run between specialists (a director after each stage), or once per tick as here?
   Once per tick is the BT tick; per stage is today's DirectorHost cadence. Recommendation: once per tick,
   with the sequential case's equivalence covering the per-stage cadence when only one specialist is active.
4. **Statuses for worlds without goals** (RDDL, stories: objection C). Without `status`, they are `running` or
   `idle` only, and a BT over them sees no success. Recommendation: allowed, stated.

## 8. Amendment 2: one certifiable package (brief v4 §9)

### 8.1 The package and its certificate

A composition Π is ONE catalog package. Its members are:
- the n specialist domain files;
- the director domain;
- the protocol module (§8.4);
- the composition manifest with each member's manifest (§2);
- the capacity instance.

Executing the members as separate contexts (form S, today's sessions) is an execution strategy, not a
semantic choice. The semantics is fixed at the package level by the tick protocol (§8.5).

**Its certificate** is the triple:

    cert(Π) = ( package_key(Π),  iface(Π),  [ program_key(G_d) for each member d, in manifest order ] )

- **`package_key(Π)`** is the lowercase hex SHA-256 of the canonical bytes `"metis-package 1\n"` followed by,
  one line per member and in manifest order (protocol, capacity, director, then `specialists`):
  - the member's role and name;
  - the canonical key of its source unit (spec 03: AST identity, includes resolved, so a formatting change
    leaves it unchanged);
  - then the composition manifest's own canonical form (sorted keys, the lists in their order).

  It is identity at the package level: two packages with the same key are the same composition.
- **`iface(Π)`** is the I-check verdict (I1–I9) with the cut report (§3). It is part of the certificate: an
  uncertified composition is one that fails a check, not one that merely failed to ground.
- **`program_key(G_d)`** is each member's own grounded certificate (spec 03), grounded through the capacity.
  Each member is grounded and keyed ALONE, which is possible because it depends only on the protocol module and
  the capacity (§8.4).

Nothing composite is grounded. The composite's measure is determined by the members' programs and the protocol
(§8.2), so the per-member certificates plus the protocol ARE the composite's certificate.

### 8.2 Why the composite measure factorizes (objection A3, for form S)

The tick protocol (§8.5) gives four properties:
- **(F1) Inputs are taken at the boundary.** Within tick t, a beating member d reads only its private state
  and the copies taken for it at boundary t.
- **(F2) Outputs are latched to the next boundary (Moore).** Nothing d emits at t is visible to any other
  member before boundary t+1.
- **(F3) The relay is deterministic.** The host's copy, relay and grant transfer at a boundary is a function
  of the members' latched outputs and the world's readings, with no draw.
- **(F4) The RNG streams are disjoint.** Each member samples from its own seeded stream (today: one RNG per
  session).

Under F1–F4, no member's choice within a tick can depend on another member's choice in the same tick. The
probability of a composite trace τ (the per-member step sequences, tick by tick) is therefore the product:

    P(τ) = Π_t  Π_{d beats at t}  P_d( steps of d at t  |  state_d(t) )

Here state_d(t) is d's private state plus its boundary-t copies, which are fixed by τ's prefix through F3.
Each factor is the member's own kernel measure, already certified by `program_key(G_d)`.

**Arbitration** is the director's CHOICE at its own beat, inside its own measure. The grant it emits reaches
the holder at the next boundary (F2), and the resource is a token in the director's program (I5).

This is the session-form answer to A3. One measure per member, composed by a product that the protocol
determines; not a joint measure over a shared multiset.

**What the product does NOT give** is the flat program's measure: interleavings within a tick are not
represented (F2 forbids them), as amendment 1's §4.6 already restricts. A chain A → B → C takes two
boundaries (objection B) and shows as such in the status journal.

### 8.3 Copies per port, not `!atom`

In linear-logic terms, `!p` (unrestricted) is one live shared truth: every rule may read it, none can consume
it, and every reader sees every change at once. In metis that is a `bwd` fact (the Horn world, guards only), or
a `$`-read of an atom nobody retracts. Used for a reading or a signal, it breaks three things:
- a trigger on it never latches and the domain never quiesces (A2);
- a slow member sees a moving target;
- contraction is implicit (A1).

**Rule.** World readings and signals are COPIES PER PORT; statics are `!`, meaning `bwd` facts, types, and the
capacity's tables.

- **A copy is linear.** It is an atom in the subscribing member's own state (form S: its session; form P: its
  stage), so the member's trigger consumes it, and that is the latch.
- **A copy is a snapshot.** The value is the one AT THE MEMBER'S OWN BEAT: the host refreshes it at the
  boundary where the member beats (§8.5), so a member that does not beat keeps its last snapshot.
- **A copy's multiplicity is declared.** One per subscribing port, so the multiplicity of a signal is its
  subscriber count, derived from the `in` directions (§2.1) and made explicit (contraction). A manifest may
  state `copies: k` on a port that legitimately takes k units per boundary; the default is 1.
- **`world-private` (amendment 1a) is exactly the per-port copy of a world reading.** amendment 1 left its
  refresh time open; §8.5 fixes it at the member's own beat.

New check **I9**:
- a pred declared `bwd` (static) is never a `world.out` port, and never refreshed by the host;
- a reading or signal port is never `bwd`;
- a `copies: k` declaration agrees with the subscriber count, unless stated as a k-unit port
  (`iface-copy-static`, `iface-copy-multiplicity`).

### 8.4 The protocol module: no cycle between specialists and the director

Specialists write reports and read grants and goals. The director reads reports and writes grants and goals.
Declared inside either side, that is a dependency cycle, and neither side could be keyed or certified alone. So
the reports and grants are declared in a THIRD module, a lifted domain file (spec 12) that every member
includes:

```
% protocol — the interface between the specialists and the director (spec 15 §8.4)
catalog protocol 1.
types (specialist resource kind).        % S, R and the goal/report kinds: completed by the composition
namespace proto produce (dyn).
pred active(specialist) : proto.         % report  (specialist: out, director: in)
pred done(specialist) : proto.           % report
pred stuck(specialist) : proto.          % report
pred status(specialist, tick__status) : proto.   % report, asserted by the host from the trace (amendment 1b)
pred report(specialist, kind) : proto.   % a result or refusal of kind K (today's seen/result kinds)
pred goal(specialist, kind) : proto.     % grant side (director: out, specialist: in): a goal of kind K
pred grant(resource, specialist) : proto.% grant side: the resource token's holder
pred cancel(specialist) : proto.         % grant side: a STOP, the goal withdrawn (amendment 7)
```

- **The composition manifest makes S and R concrete.** `specialists:` completes `specialist`, the director's
  `resources:` completes `resource`, and the kinds are the goal and report kinds (today's director instance's
  `kind` type, derived as in §5).
- **The task-level vocabulary that crosses members** (alfworld `goto`, `reached`, `open`, `accessible`, …)
  is declared in the protocol module too, with its argument types, and not by the specialists.
- **A specialist reads its goals as copies of `goal(self, K)` plus the payload atom.** That is today's
  director relay (`forward(D, K)` with the atom carried by the host), made a declaration.
- **Requests are idempotent by key (amendment 6).** A member that receives a request (a forwarded intent) for
  a thing it is already handling absorbs it, and still owes the requester's report (act, alert on a beast,
  absorbs `fight(P)` for that beast and answers `cleared(P)`); the director's forward to an already-active
  member pushes nothing on the path. No check.
- **A STOP is a CANCEL, not a REVOKE (amendment 7).**
  - A REVOKE (`tick__revoke(D, R)`, §8.5 rule 4 and §9.3) takes the BODY and keeps the goal: a preempted
    member keeps its goal, waits queued, and resumes on it when the resource comes back.
  - A CANCEL (`tick__cancel(D)`, nature `signal`, director `out`, member `in`) takes the GOAL. The agent
    relays it like any director `out` to a member `in`, and never writes one itself: a director `out` no rule
    produces is an I2 finding, and a member `in` with no producer an I3 one.
  - The stop itself is `tick__stop` (0-ary, nature `signal`), a ONE-TICK world signal. The agent asserts it
    for the stop's tick and retracts it at the next, and the composition lists it under `world.out`.
  - The director cancels exactly the members on its path, and pops each in the same rule (the generic base):

    ```
    stop_cancel [dyn] : $tick__stop * path(D) * tick__goal(D) -o tick__cancel(D) * offpath(D).
    ```

    The cancel goes only where a goal is, together with the goal's withdrawal. Consuming `path(D)` is the
    once-per-stop guard, so no start token is needed and nothing must be re-armed. The director is not
    reloaded on a stop: "0 reloads, same sessions" holds.
  - Every member carries a GENERATED PROTOCOL STUB, two rules per goal kind K and one absorb rule:

    ```
    begin_K     [dyn] : idle * $K(G) -o busy * tick__active(D).   % reads the goal, idle → busy, reports active
    cancel_K    [dyn] : busy * tick__cancel(D) * K(G) -o idle.    % the cancel: the goal dropped, idle given back
    cancel_none [dyn] : idle * tick__cancel(D) -o idle.           % the done-and-stop race
    ```

    - The member gives back `idle` and drops the goal itself: no host writes a member's internals. A revoke
      touches none of these rules, so a preempted member stays `busy` on its goal.
    - A member idle with a forwarded goal it has not begun begins and cancels in one beat (`begin_K`, then
      `cancel_K`), so nothing is withdrawn from outside.
    - `cancel_none` is for the ONE real race: the member's done and the stop land in one director beat, with
      `path_pop` and `stop_cancel` both enabled. It is not a licence for cancels to idle members in
      general; `stop_cancel` sends none.

**Dependencies:** specialist → protocol ← director, with capacity below all of them. This is a DAG, so each
member is keyed and grounded alone (§8.1).

**The tree director's base is generic (amendment 5).** `iface/director_tree_domain.llp` lives in metispy's
`metis/catalog/iface/`, beside the protocol module, and is included by plain path through `METIS_HOME` (spec
00 §4). It holds the resources' tokens, the requests and their ticket queue, preemption by priority, the
hysteresis ages and the path. A composition supplies only its instance: the resources and their counts, the
priorities, k and m, and its members (the `domain` and `resource` types). `iface/director_tree_wake.llp`
bridges a routing director's wake and sleep onto the tree; it declares nothing and adds rules to the
director's stage.

New check **I8**, over the static graph and the include graph:
- (a) the member include graph is a DAG, with protocol and capacity as its only shared nodes, apart from a
  SHARED LIFTED DOMAIN FILE (amendment 5): a base of rules several members instantiate, which is no member's
  top file and lies in no member's package directory. The listing notes it, and its key enters each
  instance's EI(S). A member including another member's program or package stays refused;
- (b) every pred that crosses members (the cut, §3) is declared by the protocol module or is a world port;
- (c) no specialist rule names the director's name or another specialist's name as a constant of type
  `specialist`. It may name only itself, through the `self` constant the composition binds
  (`iface-direct-name`, `iface-cut-undeclared`).

The consequence for §1.2's tables:
- the peer-to-peer pairs (`goto`/`reached` between task and nav; `open`/`accessible`; …) become report → goal
  routes through the protocol, which is what today's director already does;
- the direct `in`/`out` peer edges of §5 remain as the cut's description, but under I8 their declarations move
  to the protocol module.

### 8.5 The tick rules (form S: the host's; form P: the stage guards)

The base tick is only the boundary at which copies are taken and latched outputs released. Four rules:

1. **Change-or-clock.** The blackboard keeps a change counter c_p per port. Member d keeps the counter value it
   last saw, seen_d(p). d beats at boundary t iff some port p ∈ in(d) has c_p > seen_d(p) through a change
   not tagged with source d (rule 3), or d's clock period (domain.yaml `clock`) has elapsed since its last
   beat. Otherwise d does not beat. A non-beating member costs no draw and keeps its last snapshot (F1).
   **A CLOCK SOURCE must declare a clock period (amendment 5).** A member whose world changes without the
   ego (a drying plant, a scripted visitor, beasts moving unseen) sees no change on its ports, so under this
   rule it would never wake: its `domain.yaml` must declare `clock`. Rule 1 binds composition members only;
   a domain outside any composition is clocked every tick, as today. (Found by opus's dog/plant control test
   under the tick.)
2. **Moore latch.** d's reports, intents and grants produced at boundary t's beat are released at boundary
   t+1 (F2). Within a tick there is no feedback path, so no loop can close inside one. Across ticks a loop
   takes two boundaries per round and shows in the status journal.
3. **No beat on one's own echo.** Each change on the blackboard is tagged with its source member (or `world`
   for the host's sync of a world reading). A change whose source is d does not make d beat: c_p advances, but
   rule 1 skips it for d. Effects that go through the world are not echoes: nav's own move changes `at`
   through the world's sync, tagged `world`, and nav beats on it. That is the dialog's echo-loop lesson, as a
   protocol rule.
4. **Hysteresis is the director's.** These are director rules, not runtime policy:
   - a grant is not revoked within k ticks of being given;
   - a status must hold for m ticks before the tree acts on it.

   They are written as countdown tokens in the director domain (`held(R, S, k)` decremented on the director's
   own clock). k and m are the director's own constants, in its instance.

   **The one exception is preemption (amendment 5).**
   - It is allowed only by a declared instance fact `priority(P, Q)`: P may preempt Q, a strict order.
   - The preempted request is queued, never dropped.
   - The preemptor then holds the hysteresis itself: no preempt-back within k.

   **The ticket queue** (the generic base, a bakery):
   - each resource keeps `issue(R, t)`, the next ticket to hand out, and `serving(R, t)`, the ticket whose turn
     it is;
   - a request (`tick__want(S, R)`) takes the next ticket and waits as `queued(S, R, t)`;
   - the resource goes to the ticket being served: first asked, first served;
   - a preemption serves its preemptor out of turn and marks the preemptor's own ticket `skipped(R, t)`, so its
     turn is passed over when it comes up and nobody is served twice.

In form P (deferred), rule 1 is a guard on each stage's link: the stage runs its rules only when its dirty or
clock token is present. Rule 2 is the copies' release at the `direct` → S₁ link. Rule 3 is the source tag on
copies. Rule 4 is unchanged.

### 8.6 What changes in the manifest

- **The composition file** gains `protocol: protocol.llp`, and `response: ρ` (amendment 6, §2.3).
- **Each member's `domain.yaml` `clock`** (it exists) is rule 1's period.
- **A port may carry `copies: k`** (§8.3).

There are no renames. nina's fields and amendment 1's are unchanged.

## 9. Amendment 3a: the deployment view — bundle, wake set, actors, the replay oracle (brief v5 §10)

### 9.1 The bundle

A **bundle** B is a composition package Π (§8.1), selected for one robot or appliance and sealed, together
with a **runtime manifest** RM. For each member, RM gives:
- the runtime that executes it (the Go embedded runtime over `libmetis_rt`, the C++ `metis::Live`, the
  metispy REPL);
- its placement: in-process, or an actor of its own (§9.3);
- the binding of each of its ports to a **domain library** (the host code that computes: the semantic map,
  perception, a planner, a device driver), with that library's name, version and own key.

RM also carries the deployment policy of §9.2 (`evict_after`, `on_wake`).

    cert(B) = ( cert(Π), runtime_key(RM) )

- **`runtime_key`** is the SHA-256 of RM's canonical form: sorted keys, the member list in manifest order.
- **cert(Π)** (§8.1) already covers the semantics. RM covers what runs it. A library upgrade changes
  runtime_key, not cert(Π).

**OTA.**
- **A deployed bundle changes only by OTA**, either whole or per member.
- **A member m′ may replace m iff:**
  - both were certified against the SAME interface package keys (§10.3; the protocol module is one of them);
  - and the new composition passes I1–I12 again. The check is static and cheap, and it runs before the swap.
- **Every OTA produces a new bundle key.** A member swap keeps cert(Π)'s structure: one member key changes, and
  the package key is recomputed.

### 9.2 The wake set, and lazy loading (form S only)

A specialist's manifest `in` set (§2.1) IS its **wake set**.
- **The wake test.** The runtime evaluates it over the blackboard's per-port change counters (§8.5 rule 1:
  c_p > seen_S(p) through a change not tagged with source S), or over its declared clock. It does this WITHOUT
  loading the specialist.
- **"Beat on change" and "load on change" are the same rule.** The director never names a specialist's code,
  only protocol atoms (I8).
- **What a sleeping specialist receives on waking:**
  - a **reading** (only `$`-read): the copy taken at the waking boundary, the latest value; intermediate
    values are not replayed, since a copy is a snapshot (§8.3);
  - a **signal** (consumed): it is held in the specialist's mailbox while it sleeps and delivered at the
    waking boundary. It is linear, so it is never dropped. A `copies: k` port accumulates up to its declared
    multiplicity.

**Eviction.** A specialist is evicted when all of these hold:
- it has been idle (did not beat) for `evict_after` ticks (in RM; absent means never);
- it holds no lease (§9.3);
- no goal copy addressed to it is unconsumed.

Its private state is then checkpointed: the session's atoms, stage and RNG state as the K3 snapshot, which is
data. A re-wake restores the checkpoint (`on_wake: resume`, the default) or starts from the member's init
(`on_wake: fresh`).

**Form P cannot do this.** In one grounded program every member is present at once: hundreds of specialists
would be loaded together, and the model's surface would be the union. Lazy loading, eviction and per-member OTA
are form S properties, stated as such.

### 9.3 Actors, boundary stamps, `age`, leases

**An actor** is one session, plus its domain library, plus a mailbox. Its messages are exactly the protocol's:
- **in:** the boundary copies of its `in` ports, each carrying the **boundary stamp** b at which it was taken;
- **out:** its reports, intents and requests, each stamped with the latest boundary whose copies the actor had
  consumed when it produced them. "Which world it answers" is therefore explicit.

The in-process relay of form S today (nina's step 2) is the degenerate case: one process, one boundary, zero
latency, every stamp equal to the current boundary. Across processes, the same protocol runs with stamps.

**Desync is bounded, not prevented.** The protocol module (§8.4) gains:

```
types (… age).                              % 0..K, completed by the composition (K = the director's horizon)
pred age(specialist, age) : proto.          % host-asserted at each boundary: the current boundary minus the
                                            % stamp of S's latest report, capped at K (director: in)
pred lease(resource, specialist, age) : proto.  % a grant as a LEASE: the boundaries it has left (director-private)
pred revoke(resource, specialist) : proto.  % director: out, specialist: in — the lease is gone
```

- **Staleness is a fact.** The director's rules may ignore an intent from S while `age(S, k)` with k above its
  limit. That is the director's rule, with the limit as its constant.
- **A grant is a lease.**
  - The director's grant rule produces `grant(R, S)` (to S) and `lease(R, S, m)`, both director-private.
  - Its own countdown rules decrement the lease at each director beat, and renew it on a fresh report from S
    (one whose age is under the limit).
  - On reaching 0, the director's `expire` rule releases R back to the director's token and sends
    `revoke(R, S)`.
  - **The director releases on expiry, never because the actor fell silent.** A stalled actor cannot hold the
    body past m boundaries.
- **I5 with leases.** `held_by: [lease]`: the P-invariant over R + Σ lease(R, ·, ·) holds through grant,
  renew and expire.

### 9.4 The message order is the replay oracle

§8.2's F3 becomes:

- **(F3′) The relay is deterministic given the message order:** the order in which messages arrive at each
  mailbox, and the boundary at which each is taken.

With actors, latency is the environment's. Message timing is not part of the composite's measure.

- **The factorization holds per actor, given its input log:**

      P(τ | logs) = Π_d P_d(τ_d | log_d)

  where log_d is member d's stamped messages in the order they were taken.
- **What the journal records:** each member's seed, its checkpoint (if any), and its input log.
- **Replay of a bundle** is replay of each member's session from its init or checkpoint against its log. Each
  member's trace is byte-identical by construction, since the kernel is seeded. The composite trace is the
  members' traces merged by boundary stamp.
- **What is NOT reproduced:** the timing that produced the logs. Replay is of a given run, not of the network.

## 10. Amendment 3b: interface packages and a specialist's external interface (brief v6 §11)

### 10.1 Interface packages own the shared preds

A shared pred is declared ONCE, in an **interface package**:
- it is a lifted file with only declarations: `types (…)` abstract types (spec 12) and `pred`s over them;
- it has no rules, no facts and no stages;
- it has its own `catalog <name> <version>.` and its own spec-03 key.

There are two kinds:
- **the protocol module** (§8.4, with §9.3's additions): the generic one, with status, active, done, stuck,
  report, goal, grant, revoke, age and lease;
- **a family's crossing vocabulary**: `iface/<family>.llp`, for example `iface/alfworld.llp` with goto,
  reached, open, accessible, take, taken, put, placed, elsewhere; `iface/kitchen.llp`; `iface/nav.llp`.

A specialist INCLUDES the interface packages it speaks, and its manifest states its DIRECTION on each of their
preds (§2.1: in / out / resource / world-private). It no longer declares a shared pred itself. Forward
declarations stay for TYPES (spec 12); shared PREDS come from the include. This supersedes I8(b): "the cut is
declared by the protocol module" becomes "by an interface package", and the protocol module is one of them.

**Each interface pred has a NATURE.** Following the YAML-first ruling (§7 Q1), it is declared in the interface
package's own manifest. That is a sidecar named after the package, `<package>.yaml` beside `<package>.llp`
(for example `protocol_domain.yaml`), with one flow line `nature: {pred: signal | resource | report}`
(amendment 4). Without a sidecar, I11 is skipped with a note. The interface package's key covers its
declarations AND its natures (the sidecar's canonical line, keys sorted), so a nature change is visible to I12
and to OTA compatibility:

| nature | a specialist may declare | the director may declare |
|---|---|---|
| `signal` (world readings and peer-crossing vocabulary) | `in`, `out`, `world-private` | `in`, `out` |
| `resource` | `resource` only: never `out`, never `in` | holds it (I5): grants and leases |
| `report` (status, active, done, stuck, report) | `out` only: never `in` | `in` |

### 10.2 New checks

- **I10, ownership.** Every pred a member lists in `shared`, and every pred of the cut (§3), is declared by
  exactly one interface package the member includes (`iface-shared-local` when a member declares it itself;
  `iface-pred-owned-twice` when two interface packages declare the same name). Two specialists that each
  declare a shared pred are "two vocabularies by accident", and the check refuses them.
- **I11, natures.** Each member's direction on an interface pred is one its nature allows, by the table of
  §10.1 (`iface-nature`).
- **I12, keys.** In a bundle, every member's included interface packages have the bundle's keys for them: the
  same name means the same spec-03 key (`iface-key-mismatch`). This is the OTA compatibility of §9.1, as a
  check.

The §7 Q2 ruling applies at the interface package: a pred has one signature. alfworld's four `refused`
signatures become one pred per signature (`refused_take(object)`, `refused_put(receptacle)`, …) in
`iface/alfworld.llp`, or one pred over a sum type the package declares.

### 10.3 A specialist's external interface

    EI(S) = ( [ (interface package, its key) included by S ],
              S's directions on their preds,
              S's abstract types (made concrete by the bundle's capacity),
              S's status atoms,
              the resources S requests )

- **`ei_key(S)`** is the SHA-256 of EI(S)'s canonical form.
- **The bundle's I-check reads EI(S), not S's rules.** I1–I12 need only the external interfaces and the static
  graph.
- **OTA compatibility of m′ for m:** the same interface package keys (I12). The bundle's I-checks are then
  re-run with EI(m′) in m's place.

### 10.4 Testing a specialist alone: the case closes the interface, the stub is generic

There is no micro-director per package. It would duplicate director logic, be certified as part of the
specialist, and drift from the real director.

- **A specialist's case** is what the kernel already runs: an init, a script of deliveries, and the expected
  atoms (`#init`, `#cases`, traces). It closes the interface with facts. At each scripted boundary it feeds the
  `in` copies (and grants), and it reads the `out` reports and intents.
- **The INTERFACE STUB** is one generic driver, parameterized by the specialist's manifest and EI. It belongs
  to metispy and the catalog packages job, as a later step after specialist-tree step 2.
  - It knows what to feed: the `in` set.
  - It knows what to collect: the `out` set.
  - It knows how to score: the status atoms.
  - It knows what to grant: a `grant`/`lease` fact asserted when the script says so.
  - It binds the program's weight ports (amendment 7). A program with a weight port does not load unbound
    (the alfworld task's `weight look(O, R)`), so the case binds each one to a constant for the whole case,
    `ports: {look: 1.0}`. The value must be a number (finite, not negative: a weight). A name the program does
    not declare is refused by name, and a declared port left unbound refuses the case. A table or a fitted
    binding is a plugin's job, never a case's.

  One stub for all packages, and no package-specific harness code.
- **Certificates.** A specialist's certificate is its program_key plus its cases passing against the stub.
  **It never depends on which director it will meet**: the protocol module is a declaration package, with no
  rules. A composition's certificate (§8.1) adds the I-checks and the composite cases (the shared-pot
  kitchen). The interface packages have no rules, so they have no cases; their key, their contract text and
  their natures are their certificate.

### 10.5 For the two hierarchies, and nina's step 2

- **The protocol module file is the first interface package.**
- **alfworld hier.** `iface/alfworld.llp` takes the crossing preds of §1.2 (with `refused` split per §10.2).
  nav, access, grasp, place and task include it and the protocol module. Their manifests' directions are
  unchanged; their local `pred` declarations of those names go.
- **minihack mh_hier** follows the same pattern (`iface/minihack.llp`: goto, reached, closed, guarded, open,
  fight, opened, cleared, refused).
- **The world readings** that are `world-private` (amendment 1a) stay declared by the specialist. Each is a
  per-member copy, not a crossing pred, so I10 does not apply to them.

## Acceptance (for the design step)

The spec is reviewed, the field names are agreed with nina (no rename; the three additions of §2.3 told to
her), and the two decisions of §5 are handed to step 2: the hands, and the position. Implementation of §6 is a
separate step with its own ruling.
