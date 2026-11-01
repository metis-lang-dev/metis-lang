# PROPOSAL 18 — derivation: extending a domain by inclusion, extension, parametrization and override

**Status: DRAFT 2026-11-01 (the architect, at the user's request: "do refactoring spec … give me your take on domain extending by inclusion, lifting override, reparametrization, maybe more"). The worked example is the road family: the platform-neutral road semantics kept in the catalog, consumed by the road world (cars, SUMO/CARLA) and by the wheelchair, the loop refining the family on traces (spec 17 am.7, trace-replay s-c111ff41) with both consumers' goldens as the gate. Nothing here changes a running runtime; §3 and §4 are language changes for BOTH toolchains (metis-lang authoritative, metispy at byte parity) and are the subject road-family's step 1 once ruled.**

## 0. In one table

| mechanism | exists today | what it derives | certifiable by the image | preferred for |
|---|---|---|---|---|
| **reparametrization on ports** | yes (`weight`/`guard`/`input`/`output` ports, `@w` weights, the plan's port values) | the same rules, other prices | yes: port values are in the image's plan | every platform difference that is a number: margins, speeds, RSS parameters, responses, policy weights |
| **abstract type binding** (spec 12) | yes (`types (…)` completed by the instance) | the same rules over another vocabulary | yes | mover classes, zone kinds, role sets |
| **inclusion** (`include "unit".`) | yes (spec 00 §4; standard units, root/home resolution; L20) | the union of a unit's declarations and rules | yes: the include place and key are in the lock | taking a family's units whole |
| **extension** (`extends base.`, a pack) | yes (spec 00 §5.6/§5.7: the base supplies signatures, bwd, layers, stages, types; the pack adds rules) | more rules over the base's vocabulary | yes (the pack compiles against its base) | a consumer's OWN rules beside a family's: the chair's members over the road vocabulary |
| **gating by tokens** | yes (an idiom: a rule's premise consumes/reads a token the consumer issues or withholds; the generated cancel rules do this) | a base rule switched off or on per consumer | yes, nothing new | disabling a family rule without touching it |
| **hiding at inclusion** (`include "unit" hiding (r1 r2).`) | NO: new, §3 | the union minus named rules | yes: the hidden set is in the lock | rules that must not even ground on a platform (cost, spec 14) |
| **override of an open rule** (`open` on the base rule, `override` on the derived) | NO: new, §4; today a duplicate rule name in a stage is the error `duplicate rule name` (parser), not a warning | a base rule replaced by name | yes: the override is in the lock; the base's interface theory is rechecked on the derived composition | the few rules a family marks as extension points |
| silent redefinition | an error today, stays an error | — | — | never |

The ranking is the recommendation: a derived domain changes prices first, vocabulary second, adds its own rules by extension third, switches a family rule off by a token fourth, hides it fifth, and overrides it last and only where the family allowed it.

## 1. Motivation: one family, two platforms

The road domains (metis-worlds `road/domains`: responder, planner, the tree director, the role capacity) are written over ROLES (lead, follower, leadleft, a1..a3, vru1, nextzone, the zone's priority), geometry in the host, prices in the ports (the framework's six rules). The wheelchair's domains (metis-wheelchair `world/`) are too: nav is the people member, wc the chair's own, over the same role vocabulary from `libs/semantic-world`, and the chair's composition already takes the road's domains from metis-worlds at a pin. The user's issue (2026-11-01): the road domain can learn, on SUMO and CARLA's Town nets, semaphores, junction priority, zipper merges, and there is no way to carry that to the chair. The answer is not to copy knowledge but to SHARE THE PACKAGE: a platform-neutral family in the catalog, each platform deriving from it, the loop refining the family on traces, and a family change accepted only when every consumer's goldens still replay. Derivation is what makes "each platform deriving from it" precise.

## 2. The mechanisms that exist, stated as derivation

**2.1 Ports.** A family rule reads its prices through ports: `weight`, `guard`, `input`, `output` (spec 00 §3), the fold's bounds, the responses, the margins. A consumer binds other values in its plan; the rule text is untouched; the image holds the values. This is the chair's `1 m` against the car's `2.6 m`, the chair's `0.5 m/s2` against the car's, the responder's response in ticks. RULE: a number that differs by platform is a port value, never a rule. A family unit lists its ports and their meaning in its README; a consumer that leaves one unbound is the link error L-port (spec 17 L-rules).

**2.2 Abstract types.** The family declares `types (mover zonekind signal)`; the road instance completes `type mover {car truck bus}`, the chair's `type mover {walker bicycle chair}`. A rule over `mover` is the same rule. Grounding cost follows the consumer's type product (spec 14), so a consumer completes only what it binds.

**2.3 Inclusion.** `include "road/sem/signals.llp".` splices the unit; resolution root → home (spec 00 §4); the lock records the place and key (L20). A consumer includes the family's units it uses and no others. Inclusion is additive: a unit's rules enter the consumer's stages under the unit's names.

**2.4 Extension (packs).** `extends road_sem.` makes the consumer's file a pack over the family as its base: signatures, bwd, layers, stages and types come from the base; the pack adds rules. The chair's nav and wc members are packs over the family's vocabulary. A pack cannot redeclare a base name (`decl-duplicate`); it can declare new ones.

**2.5 Gating by tokens.** A family rule whose premise reads `$allow(change)` fires only where the consumer's instance asserts `allow(change)`; the chair never does, so the car's lane change is dead on the chair without an edit. The generated protocol stub's cancel rules are this idiom. Gating keeps the rule in the image (it grounds; it never fires); that is the cost of gating, and the reason §3 exists.

## 3. New: hiding at inclusion

`include "unit" hiding (name …).` splices the unit minus the named rules; a name that is not a rule of the unit is the error `hiding-unknown`. The hidden set is recorded in the lock beside the include (L20 gains it) and in `metisc --interface`'s print. Semantics: identical to a copy of the unit with those rules deleted, so the family's interface theory (spec 15) is rechecked on the derived composition by the link step as it is for any unit; a hidden rule that another rule of the unit depends on through a token is a finding of that check, not of hiding. Use: a rule that must not even ground on a platform (the car's lane change on the chair: its premise over `next` and the adjacent lanes multiplies the chair's grounding for nothing).

## 4. New: open rules and override

**Today** a second rule of the same name in a stage is a parse error, including one that comes through an include. Redefinition is not a derivation mechanism and must not become one silently.

**The proposal.** A family marks its extension points: `open` before a rule (`open yield_at_zone [dyn] : … -o … .`). A derived unit replaces an open rule with `override` before a rule of the same name in the same stage (`override yield_at_zone [dyn] : … -o … .`). Rules:
- `override` of a rule that is not `open` is the error `override-final` naming the base rule and its unit; `override` of a name that no included or base unit defines is `override-unknown`; a plain redefinition stays `duplicate rule name`.
- The overriding rule may change premise, head, weight and ports, not the rule's name or stage; its docs line should say what it replaces and why.
- The lock records `(unit, rule) overridden by (unit, rule)`; `metisc --interface` prints it; the image hash covers it. The base's interface theory is rechecked on the derived composition (spec 15's cut and the L-rules), as for hiding.
- The family's goldens do not bind the overriding consumer for that rule: the consumer's own cases do. The family's case harness still runs on the family's own composition unchanged.
- A family rule not marked `open` is final: the responder's proper response, the restrictor's bounds, the protocol stub's rules, the director's. A family author marks `open` deliberately and rarely: a progress-stage choice (which lane, which pace), a narration, a default.

**Why not override everywhere.** Certification: a consumer that may replace any rule carries the family's name and none of its guarantees. The `open` mark is the family's statement of what it guarantees and what it leaves to the platform; the image shows every override, so a reviewer sees in one listing what a platform changed.

## 5. What else, and what not

- **Priorities and clocks** are the composition's (composition.yaml, tick types): a consumer orders its members and clocks itself; nothing to derive.
- **Instances (`#init`)** are per world: geometry, zones, the first scene. The host projects; the family never holds geometry.
- **Versioning.** A consumer pins the family's version (the chair pins metis-worlds today; it will pin the catalog's road family). The loop's refinement of the family (spec 17 am.7) produces a candidate version; it becomes the family's version when the family's goldens and EVERY consumer's goldens replay on their images (the two-consumer ecology, trace-replay s-c111ff41 step 3's gate); a consumer bumps its pin when it chooses. A learned rule enters the family under the loop's provenance; it is `open` only if the family's author marks it so.
- **Weights and policy tuning** are port values (`@w`, weight ports): per consumer, per instance; tuning the family on cars does not retune the chair.
- **Not a mechanism: copying rules into a consumer.** Copies-not-deps is the rule for UI code, never for domains: a copied rule leaves the family's goldens and gains none of the consumer's; it is the way knowledge stops moving.
- **Not a mechanism: the REPL's interactive redefinition.** The REPL may replace a rule in a session for exploration (the `#` directives); it is a session act, not a derivation, and leaves no trace in an image.

## 6. The road family: the refactoring plan (the subject road-family, after trace-replay step 2)

1. **Carve the family** `metis-catalog/domains/road/` (public, the user: the road domain stays in the catalog): units `capacity.llp` (roles), `signals.llp` (semaphore states as roles: `signal(zone, state)`, the stop/go/clear decisions), `junction.llp` (priority at a zone, the zipper, the walker's priority), `responder.llp` (the proper response: final), `progress.llp` (the keep-table's progress stage with `open` choices), the protocol units it needs, ports listed with meaning, abstract types `mover zonekind signal`, the family's own cases and goldens (the exerciser's scenes moved from the road world's), README. The road WORLD stays in metis-worlds: the SUMO host, the exerciser, the car-specific members (lane change, ego dynamics) as packs over the family, the Town-net scenarios.
2. **The projection:** semantic-world's situation layer emits `signal` and junction-priority roles for both adapters (it already reads a SUMO net's tls programs and link rows); the chair's mixed adapter emits the crossing's pedestrian signal as the same `signal` role.
3. **The chair derives:** its composition includes the family's units at the catalog pin, `hiding` the car-only rules, with the chair's port values, `type mover {walker bicycle chair}`, its nav and wc members as packs; zero rule copies. Its goldens S1–S8 replay unchanged on the image (the acceptance of the refactor).
4. **The loop on the family:** trace-replay's `--replay` on SUMO Town-net traces refines `metis-catalog/domains/road`; the gate runs the family's goldens, the road world's and the chair's (their pins moved to the candidate in a throwaway image), all on images, no simulator.
5. **The language steps** (§3 hiding, §4 open/override) in both toolchains with goldens, spec 00/08 amendments, before step 3 needs them; if the chair can derive with ports, types, packs and gating alone, §3 and §4 wait, and the plan says so in its report.

## 7. Open questions for the user

- Should `open` be the default for rules the LOOP learned (they are the family's least certain rules), or never without the author's mark? My take: never without the mark; the loop's rules are judged by goldens, not by openness.
- Hiding by stage (`hiding stage change`) as well as by rule name? My take: by rule name only; a stage is a unit's structure.
