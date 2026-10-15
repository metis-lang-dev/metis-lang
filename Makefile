# metis-lang — the LLP language: compiler (src/, OCaml) + runtime
# (runtime/, header-only C++17) + the parity corpus that binds them.

all: metisc

metisc:
	$(MAKE) -C src metisc

check: metisc
	sh ci/check.sh

# the C++ runtime: libmetis_rt (the C ABI), the six tools, ctest
runtime:
	cmake -S runtime -B runtime/build
	cmake --build runtime/build -j4
	ctest --test-dir runtime/build --output-on-failure

formal:
	cd formal && lake build

paper:
	cd paper && tectonic metis.tex

clean:
	$(MAKE) -C src clean

.PHONY: all metisc check runtime formal paper clean
