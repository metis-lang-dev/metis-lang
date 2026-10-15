// SPDX-License-Identifier: Apache-2.0
// The sampler rung, C++ (docs/rewrite/06-sampler-wire.md): the canonical
// program bytes, splitmix64 seeded traces with the normative selection,
// every R/F golden line verified — the engine is the library's
// (metis/sample_golden.hpp), as the C ABI's conformance runs it.
//
//   ./sample_run corpus/goldens/sample_goldens.txt

#include <cstdio>
#include <fstream>

#include "metis/sample_golden.hpp"

int main(int argc, char** argv) {
    if (argc != 2) {
        std::fprintf(stderr, "usage: sample_run <goldens>\n");
        return 2;
    }
    if (!std::ifstream(argv[1])) {
        std::fprintf(stderr, "cannot open input\n");
        return 2;
    }
    const metis::GoldenResult r = metis::run_sample_goldens(argv[1]);
    if (!r.first_fail.empty())
        std::printf("FIRST FAIL: %s\n", r.first_fail.c_str());
    std::printf("SAMPLE PARITY %d/%d (%d cases)\n", r.ok, r.total, r.cases);
    return r.ok == r.total && r.total > 0 ? 0 : 1;
}
