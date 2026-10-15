// SPDX-License-Identifier: Apache-2.0
// The projection golden replayer (runtime-binding K4): metis::Live's
// likelihood from a given state against metispy's surprise_record — the
// watch's surprise test and the record's likelihood
// (metispy tools/gen_live_goldens.py, proj_<n>).
//
//   project_run <ground.wire> <projection golden>
//
// The golden:
//   L <name> · G <stage name> … · B <port> const <v> | if <atom> <then> <else>
//   P <stage> | <counts> | <steps> | <observed, zeros kept> | <likelihood>
// A zero is structural (no path reaches the observation) and must be zero
// here; any other likelihood agrees to 1e-12 relative (the filter sums the
// same paths in another order). Also the identity: from the artifact's
// init, the from-state projection is the existing one exactly.
// Prints K4 LIKELIHOOD ok/total; exits nonzero on any difference.
#include <cmath>
#include <cstdio>
#include <fstream>
#include <map>
#include <memory>
#include <sstream>
#include <string>
#include <vector>

#include "metis/live.hpp"
#include "metis/loader.hpp"
#include "metis/registry.hpp"

namespace {

std::vector<std::string> fields(const std::string& line) {
    std::vector<std::string> out;
    size_t start = 0;
    for (;;) {
        const size_t k = line.find(" | ", start);
        out.push_back(line.substr(start, k - start));
        if (k == std::string::npos) break;
        start = k + 3;
    }
    return out;
}

std::map<std::string, int> counts_of(const std::string& text) {
    std::map<std::string, int> m;
    if (text == "-") return m;
    std::istringstream in(text);
    for (std::string t; in >> t;) {
        const size_t c = t.rfind(':');
        m[t.substr(0, c)] = std::stoi(t.substr(c + 1));
    }
    return m;
}

}  // namespace

int main(int argc, char** argv) {
    if (argc != 3) {
        std::fprintf(stderr, "usage: project_run <ground.wire> <projection golden>\n");
        return 2;
    }
    std::ifstream wire(argv[1]);
    metis::LoadedProgram lp = metis::load_program(wire);
    if (!lp.ok) {
        std::printf("FIRST FAIL: %s: %s\n", argv[1], lp.error.c_str());
        return 1;
    }
    std::ifstream in(argv[2]);
    if (!in) {
        std::printf("FIRST FAIL: cannot open %s\n", argv[2]);
        return 1;
    }
    std::string name = "?", line;
    metis::Registry reg;
    bool bound = false;
    struct Case {
        std::string stage;
        std::map<std::string, int> from, observed;
        int steps;
        double like;
    };
    std::vector<Case> cases;
    while (std::getline(in, line)) {
        if (line.empty() || line[0] == '#') continue;
        std::istringstream ls(line);
        std::string tag;
        ls >> tag;
        if (tag == "L") {
            ls >> name;
        } else if (tag == "G") {
            std::vector<std::string> stages;
            for (std::string g; ls >> g;) stages.push_back(g);
            if (stages.size() != lp.program.stage_names.size()) {
                std::printf("FIRST FAIL: %zu stage names for %zu stages\n",
                            stages.size(), lp.program.stage_names.size());
                return 1;
            }
            lp.program.stage_names = stages;
        } else if (tag == "B") {
            std::string port, how;
            ls >> port >> how;
            if (how == "const") {
                double v;
                ls >> v;
                reg.weight(port, v);
            } else if (how == "if") {
                std::string atom;
                double yes, no;
                ls >> atom >> yes >> no;
                reg.weight(port, [atom, yes, no](const std::vector<std::string>&,
                                                 const metis::CountsView& c) {
                    return c.has(atom) ? yes : no;
                });
            } else {
                std::printf("FIRST FAIL: binding '%s'\n", line.c_str());
                return 1;
            }
            bound = true;
        } else if (tag == "P") {
            const auto f = fields(line.substr(2));
            if (f.size() != 5) {
                std::printf("FIRST FAIL: case '%s'\n", line.c_str());
                return 1;
            }
            cases.push_back({f[0], counts_of(f[1]), counts_of(f[3]), std::stoi(f[2]),
                             std::stod(f[4])});
        }
    }

    int ok = 0;
    double worst = 0.0;
    std::string first;
    bool identity = false;
    try {
        metis::Live live(std::move(lp));
        if (bound) live.bind(reg);
        for (size_t k = 0; k < cases.size(); ++k) {
            const Case& c = cases[k];
            std::string snap = "metis-live 1\nstage " + c.stage + "\nquiet -\nrng 0\nfired 0\n";
            for (const auto& [a, n] : c.from) snap += "count " + a + " " + std::to_string(n) + "\n";
            const double got = live.likelihood(snap, c.steps, c.observed);
            const bool zero = c.like == 0.0 || got == 0.0;
            const double d = std::fabs(got - c.like) / std::max(1.0, std::fabs(c.like));
            const bool same = zero ? got == c.like : d <= 1e-12;
            if (!zero) worst = std::max(worst, d);
            if (same) ++ok;
            else if (first.empty()) {
                char buf[96];
                std::snprintf(buf, sizeof buf, ": want %.17g, got %.17g", c.like, got);
                first = "case " + std::to_string(k) + buf;
            }
        }
        // the identity: from the init, the from-state projection is the
        // existing projection, slice for slice
        const metis::Program& prog = live.program().program;
        const metis::ForwardProjection a(prog, 3);
        const metis::ForwardProjection b(prog, metis::State{prog.init_stage, prog.init}, 3);
        identity = a.final() == b.final();
        // (unpriced on both sides here: the priced one is the cases')
    } catch (const std::exception& e) {
        std::printf("FIRST FAIL: %s\n", e.what());
        return 1;
    }
    if (!first.empty()) std::printf("FIRST FAIL: %s\n", first.c_str());
    if (!identity) std::printf("FIRST FAIL: the from-init projection is not the projection\n");
    std::printf("K4 LIKELIHOOD %d/%zu (%s; max relative difference %.3g; identity %s) %s\n",
                ok, cases.size(), name.c_str(), worst, identity ? "ok" : "BROKEN", argv[2]);
    return first.empty() && identity && !cases.empty() ? 0 : 1;
}
