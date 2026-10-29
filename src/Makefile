# OCaml toolchain build — stdlib only, plain ocamlopt (no dune on
# noble; a certifier wants zero deps anyway). Module order = the
# dependency order of 02-ocaml-contracts.md.

SRC = ast lexer parser diag catalog horn compile ground ports wire factorize \
      sha256 nets refsample \
      bpn elim ir iface image tools_json sidecar link rat evaluate
FILES = std_dir.ml $(foreach m,$(SRC),$(m).mli $(m).ml) main.ml

metisc: $(FILES)
	ocamlfind ocamlopt -package "" $(FILES) -o metisc 2>/dev/null \
	  || ocamlopt $(FILES) -o metisc

# the standard units' directory compiled in (spec/17 amendment 5): this
# checkout's iface/, for a metisc copied away from it; rewritten only
# when it changes
STD = $(abspath ../iface)
std_dir.ml: FORCE
	@echo 'let dir = "$(STD)"' | cmp -s - $@ || echo 'let dir = "$(STD)"' > $@

FORCE:

clean:
	rm -f *.cmi *.cmx *.cmo *.o metisc std_dir.ml

.PHONY: clean FORCE
