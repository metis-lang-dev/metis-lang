# Rulescript v2 — language specification (rewrite exercise, phase 1)

Normative spec of the `.llp` surface, extracted from
`metis/lang/parser.py` + `ast.py` + `compiler.py`. Python remains the
reference implementation until the OCaml toolchain reaches golden
parity; where this document and Python disagree, Python wins and the
document gets fixed. Syntax is FROZEN (concurrent-LL level; no new
sugar in scope).

## 1. Lexical

Tokens, longest-match, in priority order:

    doc      %%<to end of line>          (kept; leading/trailing ws
                                          stripped after '%%')
    comment  %<not %><to end of line>    (dropped; also bare '%$')
    directive #<to end of line>          (dropped, like comment; a
                                          LINE whose first non-blank
                                          char is '#' is additionally
                                          an interpreter case line,
                                          §8 — never compiler input)
    string   "..."                       (no escapes, no newline)
    arrow    -o                          (must NOT be followed by
                                          [A-Za-z0-9_-])
    horn     :-
    ne       <>
    weight   @w
    range    ..
    num      \d+\.\d+ | \.\d+ | \d+
    ident    [A-Za-z][A-Za-z0-9_-]*      (hyphens legal inside)
    punct    one of  { } ( ) . , * : [ ] ~ $
    ws       [ \t\n]+                    (dropped)

Any other character is a lex error with its byte offset.

Case rule: an ident with uppercase first letter is a VARIABLE in term
position; lowercase-first (or num) is a constant.

Doc lines attach to the NEXT rule or link; they are part of the AST
(the unit a human approves) and are MANDATORY on every rule and link
(compile-time finding if missing). Multiple doc lines join with "\n".

## 2. Grammar (EBNF; `.` terminates every declaration)

    catalog     ::= [docs] "catalog" ident num "."  decl*
    decl        ::= include | extends | provenance | layers | stages
                  | typedecl | namespace | pred | bwd | port
                  | stagedef | link | hornfact | hornrule
    include     ::= "include" string "."
    extends     ::= "extends" ident "."
    provenance  ::= "provenance" ident string string "."
    layers      ::= "layers" "(" ident* ")" "."
    stages      ::= "stages" "(" ident* ")" "."      (only when
                     followed by "(" — else "stage"~ident collision)
    typedecl    ::= "type" ident "{" typeconst* "}" "."
    typeconst   ::= (ident|num) [".." (ident|num)]   (range sugar:
                     shared alpha prefix, inclusive int suffixes,
                     lo <= hi; EXPANDED IN THE AST — round-trip and
                     hashing see plain constants)
    namespace   ::= "namespace" ident "produce" "(" ident* ")"
                     ["consume" "(" ident* ")"] "."
    pred        ::= "pred" ident [sigargs] ":" ident "."
    bwd         ::= "bwd" ident [sigargs] "."
    sigargs     ::= "(" ident ("," ident)* ")"
    port        ::= ("weight"|"guard"|"input"|"output") ident
                     [sigargs] [readsblock] "."
                     (readsblock legal on "weight" only)
    readsblock  ::= "reads" "{" [readpat ([","] readpat)*] "}"
    readpat     ::= atom ["if" atom ("*" atom)*]
    stagedef    ::= "stage" ident "{" rule* "}"
    rule        ::= [docs] ident "[" ident "]" ":" body "-o"
                     (althead | head ["@w" weightexpr]) "."
    althead     ::= "(" head "@w" weightexpr
                     ("|" head "@w" weightexpr)+ ")"
                     (the additive-plus sugar: EXPANDED IN THE PARSER
                     to one clause per branch, named <name>-1 ..
                     <name>-k, sharing the body — one CHOICE site;
                     weights mandatory per branch; <name>-<k> names
                     are reserved, duplicates rejected per stage)
    body        ::= bodyelem ("*" bodyelem)*
    bodyelem    ::= distinct | atom
    distinct    ::= VARIDENT "<>" ident      (lookahead: ident with
                     uppercase first + next token <>)
    head        ::= "(" ")" | atom ("*" atom)*
                     ("()" is the LL unit, an alias of the atom
                     "one"; pretty() prints a sole-unit head as "()")
    atom        ::= ["$"] ident ["(" term ("," term)* ")"]
    term        ::= ident | num
    weightexpr  ::= num                       (static prior)
                  | ["~"] ident ["(" term ("," term)* ")"]  (port ref;
                     ~ = complement)
    link        ::= [docs] "qui" ident "[" ident "]" ":"
                     ident ["*" atom ("*" atom)*] "-o"
                     ident ["*" atom ("*" atom)*] "."
    hornfact    ::= atom "."
    hornrule    ::= atom ":-" atom ("," atom)* "."

Any bare atom at top level is a Horn fact or (with `:-`) a Horn rule.

## 3. AST identity & round-trip

The AST is lossless: `parse(pretty(ast)) == ast` for every AST the
parser produces. `pretty` is the canonical printer (one decl per
line; stages indent rules by two spaces; docs re-emitted as `%% `
lines). Range sugar and comments are NOT represented (ranges expand,
comments drop).

## 4. Includes (RDDL-style lifting)

`include "path".` splices the included file's DECLS in place,
recursively, relative to the includer's directory; cycles are errors.
The includer keeps its own name/version/provenance. `layers` and
`stages` are ADOPTED from an included file iff the includer omits
them (domain file included by a generated instance file).
`compile_catalog` on an AST that still contains includes is an error
— resolution is a separate pass.

## 5. Compilation to the kernel catalog (static semantics)

Order of processing is significant and specified.

1. Decl sweep 1 (in decl order): collect types (ordered! constant
   order is the grounding domain order), namespaces, pred→namespace,
   pred signatures, bwd signatures, ports. Weight ports with `reads`
   enter the reads table — PRESENCE of `reads` is the factorability
   contract; absent = opaque binding.
2. Read-scope validation, per weight port with reads: formals must
   be uppercase vars; no `$` in scope atoms; arity match against
   declared sigs; scope atom's pred must be a declared resource pred
   (base's preds count under extends); every guard pred must be bwd;
   every scope-atom var must be bound by a formal or enumerated by a
   guard var.
3. Decl sweep 2 (in decl order):
   - Fact: pred must be bwd; becomes a Horn entry. Its vars (the
     SORTED set of var names in the atom) are UNIVERSALLY
     QUANTIFIED over the type each position declares — `plus(n0,N,N).`
     is Π N:nat, the Ceptre/Twelf reading of a bodiless clause — and
     typed like rule vars (one var at two differently-typed
     positions = finding). A query that leaves such a var unbound
     (Horn `solutions`, e.g. a reads-scope guard) is an error, not a
     silent non-ground answer: guard it with a predicate that
     enumerates it.
   - HornRule: vars = SORTED set of var names in head+body.
   - Stage: per rule, in order:
     * doc mandatory;
     * VAR TYPE INFERENCE: walk `[body atoms (Atom only, guards
       included)] ++ head` in order, and within an atom the terms in
       order; a var's type is the declared arg type at every position
       it occupies; conflict or untypable var = finding. THE
       RESULTING INSERTION ORDER OF THE VAR TABLE IS SEMANTIC — it
       is the grounding enumeration order and the `[X=c,Y=d]` tag
       order (01-ir-spec §2).
     * body classification: Distinct → distinct pairs; atom whose
       pred is bwd (own or inherited) → GUARD (Horn premise, never a
       resource); `$`-atom → persist; else consume.
     * head: produce, EXCEPT atoms named `one` (the LL unit — drops).
     * weight: absent → prior 1.0; `@w num` → prior num; `@w
       [~]f(args)` → prior 1.0 plus a WeightRef {factor, args (term
       names), complement} keyed by RULE name; findings if factor
       undeclared, an arg var is not a rule var, or (when f has
       reads) arg count ≠ declared formal count.
   - Link (`qui`): same inference over pre_atoms++post_atoms; same
     body classification on pre_atoms; bwd atom in POST is a
     finding; post_atoms are produce.
4. Horn entries carry layer = first declared layer (fallback
   "horn" when no layers).
5. If any findings: fail with ALL findings (accumulate, don't stop).
6. When not a pack (`extends` absent): run the kernel typecheck
   (§6); failure is a catalog error.

Packs (`extends`): base supplies sigs and bwd for inference;
layers/stages inherited when omitted; typecheck DEFERRED to
admission. (Out of the rewrite slice; contract only.)

## 6. Kernel typecheck (containment)

Per catalog: every pred's namespace declared; no pred both resource
and bwd; every namespace right references a declared layer. Per
entry: comment nonempty; layer declared; schema stage / link
endpoints declared; every var's type declared; consume/produce
rights: entry's layer ∈ namespace's consume/produce set (READS are
always allowed — observation cannot violate containment); bwd preds
never resources; Horn world closed (head and body preds all bwd);
guards only on bwd preds; guard vars declared on the schema.

## 7. Numeric & misc invariants

- Weights parse by strtod (`float()`); printed back by `%g` in
  pretty and `%.17g` on the IR wire (bit-preserving round-trip).
- Catalog version is an int; provenance = (source, ref, date)
  strings, default ("hand", "catalog <name>", "unknown").
- Namespace `consume` omitted = same as produce.
- The `stages(...)` header is the PROGRAM stage order (semantic:
  initial stage is its first element unless overridden at ground
  time; the IR schedule follows it).

## 8. Interpreter directives (compiler-invisible)

A `.llp` may embed its own case as `#`-directive lines — the Ceptre
lineage's in-file `#trace`, restored as a comment class. This is NOT
new syntax under the freeze: the compiler lexes `#...` exactly like a
`%` comment, so the AST, the compiled catalog and the canonical
program_key are byte-identical with or without them.

A directive is a line whose first non-blank character is `#`; its
body is ONE case-manifest line, same vocabulary, same driver code
(`init <atom> <count>`, `steps <n>`, `seeds <n>`, `unknown <atom>`,
`query <atom>`, `lik <atom>=<v> ...`, `interactive <stage>`). At most
one `init` line per atom. `interactive <stage>` (the additive &,
Ceptre's `#interactive`) makes `--run` resolve that stage's CHOICE
externally: enabled events and their normalized weights are listed on
stderr, the selection is read from stdin, and EOF or unparseable
input falls back to the reference sampler draw (piped runs always
complete); the stdout wire (`T`/`F`/`Q`) is unchanged, and the
symbolic drivers ignore the directive. A trailing `#...` after code on the same line is lexed away
but is NOT a directive.

`metisc --run <file.llp>` builds the embedded case (`case` name =
the file's basename; `llp` = the file itself) and replays it on the
reference sampler: `I` init lines, then per seed a `T` line of fired
canonical event names (`-` if none) and the `F` final line
(06-sampler-wire), then `Q <atom> <hit>/<seeds>` presence counts.
Directives are a dev/discovery channel: certified expectations stay
in manifests, and pretty() does not reproduce directives (a
parse→pretty rewrite drops them).
