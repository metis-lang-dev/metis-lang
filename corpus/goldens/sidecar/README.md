# Sidecar goldens (linker s-5908724a, ruling 6)

The target for metisc's sidecar emitter (step 5c). Made by metispy's `metis.kernel.artifact.build` (metispy
cb3b742) for every member of the four corpus images (`corpus/iface`: kitchen_pot, road, alfworld hier,
minihack hier; metis-lang fdc0a07). The emitter must write each member's `sidecar.json` **byte-equal**.

- `sidecars.sha256`: `sha256  bytes  image/member` for all 16 members. This is the gate's comparison.
- `<image>/<member>.sidecar.json`: the seven members under 110 KB, in full (kitchen_pot ×3, road ×3,
  minihack task) to diff against. The other nine (up to 6.8 MB, alfworld's director) are regenerated with
  `regen.py`, not committed.
- `tools.json`: the REPL API's tool declarations. It is one constant (identical in all 16 bundles), which the link
  writes once at the image root.
- The ground.wire of each member is already byte-equal to the image's (16/16), and the sidecar's `key` equals
  the image's `wire_key`.

Rulings for the emitter (architect, 2026-10-28):
- (a) `cards[].error` is a diagnostic code as diag.ml names it, never exception text. There is none in this corpus.
- (b) The atom text in `script` is the wire's canonical atom form. OCaml is authoritative, and metispy's
  artifact.py adapts if it differs, after which these goldens are regenerated.
- `cards[].slots` and `events[].line` come from the parsed AST on both sides, not a regex over raw text.
- The format stays `json.dumps(indent=1, ensure_ascii=False) + "\n"`.

The gate also covers the catalog's 42 bundles (metis-catalog `domains/*/build/*.metis/sidecar.json`), which
hold the cases this corpus lacks: kitchen's sibling card, and plant's extension (visitor.llp).
