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
| **I3** every `in` has a producer | `world-private` preds are exempt (their producer is the host's sync). For each (S, p: in), some peer has p: `out`, or p ∈ `world.out`, or D produces p (`iface-in-unproduced`). | alfworld `fetch`: task's `in`, produced by the world (the person's goal, `world.out`); minihack `reach` alike |
| **I4** one writer of a state pred | `world-private` preds are exempt: one copy per member, one writer per copy (the host's sync). A shared pred consumed by more than one member (specialist, D, or the world as writer) is a contention point. It must be a `resource` (I5) or a broadcast signal, one copy per consumer (§4.3) (`iface-multi-writer`). An `out` consumed by its producer must be conserved per rule (`c` and `o` in the same rule). | alfworld `holds`/`holding`/`handsfree` (grasp writes, place writes) and `inrecep`/`objat` (grasp consumes, place produces): two writers of the body's state, the hands. Either a `hands` resource with grants, or world-owned readings (`world.out`) with grasp/place's writes turned into requests. alfworld `at` / minihack `agent_at`: nav consumes and re-produces (`cor`), and the host also asserts it. One writer must be chosen: the world (nav's `go`/`move` become requests for `motion`) or nav (the host stops asserting it). Under `world-private` (today's per-session reading, amendment 1a) neither set is contention; the finding fires only for a composition that SHARES these preds |
| **I5** every resource owned once | For each resource p with `count` n and `held_by` H: every rule of the composition that mentions p or an atom of H has Δ(p) + Σ_{h∈H} Δ(h) = 0 (a P-invariant of the net), and the direct domain's init holds exactly n of p and none of H. Only D's rules consume p (`iface-resource-*`). | `motion`, count 1: `grant: want_move(D) * motion -o moving(D)`, `release: moved(D) * moving(D) -o motion`; nav and act both list `motion: resource` (the beast case) |
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

## 6. Toolchain (on approval; nothing here is built)

- **`metisc --interface COMPOSITION.yaml`**: G(Π), checks I1–I7, and the cut report, as text and as spec 08
  JSON. The new `iface-*` codes are added to the D2 registry, with one fixture row each.
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

## Acceptance (for the design step)

The spec is reviewed, the field names are agreed with nina (no rename; the three additions of §2.3 told to
her), and the two decisions of §5 are handed to step 2: the hands, and the position. Implementation of §6 is a
separate step with its own ruling.
