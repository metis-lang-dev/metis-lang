# metis-lang — the LLP language: compiler (src/, OCaml) + runtime
# (runtime/, header-only C++17) + the parity corpus that binds them.

all: metisc

metisc:
	$(MAKE) -C src metisc

check: metisc
	sh ci/check.sh

formal:
	cd formal && lake build

paper:
	cd paper && tectonic metis.tex

clean:
	$(MAKE) -C src clean

.PHONY: all metisc check formal paper clean
