// SPDX-License-Identifier: Apache-2.0
// libmetis_rt — the one translation unit behind the C ABI (metis_rt.h):
// the header-only runtime, compiled once, with nothing thrown across.
#include "metis_rt.h"

#include <cstdio>
#include <cstring>
#include <exception>
#include <fstream>
#include <string>

#include "metis/golden.hpp"
#include "metis/ir.hpp"

namespace {

void set_text(char* dst, size_t cap, const std::string& s) {
    std::snprintf(dst, cap, "%s", s.c_str());
}

// the first record decides, as tools/metis_run does: `C ` is IR
bool is_ir_corpus(std::ifstream& in) {
    std::string line;
    while (std::getline(in, line)) {
        if (line.empty() || line[0] == '#') continue;
        return line.rfind("C ", 0) == 0;
    }
    return false;
}

}  // namespace

extern "C" {

int metis_rt_abi_version(void) { return METIS_RT_ABI_VERSION; }

metis_rt_status metis_rt_conformance(const char* path,
                                     metis_rt_parity* out) {
    if (out == nullptr) return METIS_RT_EARG;
    std::memset(out, 0, sizeof *out);
    if (path == nullptr) {
        set_text(out->first_fail, sizeof out->first_fail, "no path");
        return METIS_RT_EARG;
    }
    try {
        std::ifstream probe(path);
        if (!probe) {
            set_text(out->first_fail, sizeof out->first_fail,
                     std::string("cannot open ") + path);
            return METIS_RT_EIO;
        }
        const bool ir = is_ir_corpus(probe);
        const metis::GoldenResult r = ir ? metis::run_ir_goldens(path)
                                         : metis::run_goldens(path);
        out->ok = r.ok;
        out->total = r.total;
        out->cases = r.cases;
        out->ir = ir ? 1 : 0;
        set_text(out->first_fail, sizeof out->first_fail, r.first_fail);
        return r.total > 0 && r.ok == r.total ? METIS_RT_OK
                                              : METIS_RT_EPARITY;
    } catch (const std::exception& e) {
        set_text(out->first_fail, sizeof out->first_fail, e.what());
    } catch (...) {
        set_text(out->first_fail, sizeof out->first_fail,
                 "unknown exception");
    }
    return METIS_RT_EINTERNAL;
}

}  // extern "C"
