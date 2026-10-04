# OCaml toolchain build — stdlib only, plain ocamlopt (no dune on
# noble; a certifier wants zero deps anyway). Module order = the
# dependency order of 02-ocaml-contracts.md.

SRC = ast lexer parser diag catalog horn compile ground ports factorize \
      sha256 nets refsample \
      bpn elim ir
FILES = $(foreach m,$(SRC),$(m).mli $(m).ml) main.ml

metisc: $(FILES)
	ocamlfind ocamlopt -package "" $(FILES) -o metisc 2>/dev/null \
	  || ocamlopt $(FILES) -o metisc

clean:
	rm -f *.cmi *.cmx *.cmo *.o metisc

.PHONY: clean
