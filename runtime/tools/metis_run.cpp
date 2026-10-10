// SPDX-License-Identifier: Apache-2.0
// Self-checking golden CLI — thin wrapper over metis/golden.hpp and
// metis/ir.hpp (the same engines an embedding runtime serves in
// production). A corpus whose first record is `C ` is an IR corpus
// (factor-graph artifact + shipped schedules); anything else is the
// ground-program filter corpus.
#include <cstdio>
#include <fstream>
#include <string>

#include "metis/golden.hpp"
#include "metis/ir.hpp"

static bool is_ir(const char* path) {
    std::ifstream in(path);
    std::string line;
    while (std::getline(in, line)) {
        if (line.empty() || line[0] == '#') continue;
        return line.rfind("C ", 0) == 0;
    }
    return false;
}

int main(int argc, char** argv) {
    if (argc < 2) {
        std::fprintf(stderr, "usage: metis_run <corpus-file>...\n");
        return 2;
    }
    bool all_ok = true;
    for (int i = 1; i < argc; ++i) {
        bool ir = is_ir(argv[i]);
        auto r = ir ? metis::run_ir_goldens(argv[i])
                    : metis::run_goldens(argv[i]);
        if (!r.first_fail.empty())
            std::printf("FIRST FAIL: %s\n", r.first_fail.c_str());
        std::printf("%sPARITY %d/%d (%d cases) %s\n",
                    ir ? "IR " : "", r.ok, r.total, r.cases, argv[i]);
        all_ok = all_ok && r.ok == r.total && r.total > 0;
    }
    return all_ok ? 0 : 1;
}
