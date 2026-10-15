// SPDX-License-Identifier: Apache-2.0
// The live golden replayer (runtime-binding K1 + K2): metis::Live on a
// ground wire against a trace metispy's live REPL wrote
// (metispy tools/gen_live_goldens.py), byte for byte.
//
//   live_run <ground.wire> <live golden>
//
// The golden:
//   L <name> <seed> <samples>        the case: the REPL's _sample() calls
//   G <stage name> …                 the stages' names (the sidecar's; the
//                                    wire carries indices only)
//   O <canon of wire event 0> …      the normative order (sidecar canon)
//   B <port> const <v>               a weight binding, constant
//   B <port> if <atom> <then> <else> …or by whether <atom> is present
//   T <line> ; <line> … | T -        the host's ticks in order: its
//                                    do-lines, or an empty beat; after the
//                                    last, the host's episode is over
//   A <k> <line> ; <line> …          a tick mid-activity, applied before
//                                    sample k (the watch ticks every beat)
//   F <k> <event>                    a forced row before sample k (Live::fire)
//   R <kind> <canon> <stage> | <name> | <a:n …>   one row each sample
//   E <stage>                        the stage at the end
// Prints LIVE PARITY ok/total; exits nonzero on any difference.
#include <cstdio>
#include <fstream>
#include <map>
#include <stdexcept>
#include <sstream>
#include <string>
#include <vector>

#include "metis/live.hpp"
#include "metis/loader.hpp"
#include "metis/registry.hpp"

namespace {

std::string row(const metis::Live& live, const metis::LiveEvent& ev) {
    std::string s = "R " + ev.kind + " " + std::to_string(ev.canon) + " " +
                    live.stage_name(live.stage()) + " | " + ev.name + " |";
    const auto counts = live.named_counts();
    if (counts.empty()) s += " -";
    for (const auto& [a, n] : counts) s += " " + a + ":" + std::to_string(n);
    return s;
}

std::vector<std::string> split_lines(const std::string& rest) {
    std::vector<std::string> out;
    if (rest == "-") return out;
    size_t start = 0;
    for (;;) {
        const size_t k = rest.find(" ; ", start);
        out.push_back(rest.substr(start, k - start));
        if (k == std::string::npos) break;
        start = k + 3;
    }
    return out;
}

}  // namespace

int main(int argc, char** argv) {
    if (argc != 3) {
        std::fprintf(stderr, "usage: live_run <ground.wire> <live golden>\n");
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
    unsigned long long seed = 0;
    int samples = 0;
    std::vector<int> canon;
    std::vector<std::string> stages;
    metis::Registry reg;
    bool bound = false;
    std::vector<std::vector<std::string>> ticks;
    std::map<int, std::vector<std::string>> at;
    std::map<int, std::string> force;
    std::vector<std::string> want;
    while (std::getline(in, line)) {
        if (line.empty() || line[0] == '#') continue;
        std::istringstream ls(line);
        std::string tag;
        ls >> tag;
        if (tag == "L") {
            ls >> name >> seed >> samples;
        } else if (tag == "G") {
            for (std::string g; ls >> g;) stages.push_back(g);
        } else if (tag == "O") {
            for (int c; ls >> c;) canon.push_back(c);
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
        } else if (tag == "T") {
            ticks.push_back(split_lines(line.size() > 2 ? line.substr(2) : "-"));
        } else if (tag == "A") {
            int k;
            ls >> k;
            std::string rest;
            std::getline(ls, rest);
            at[k] = split_lines(rest.empty() ? "-" : rest.substr(1));
        } else if (tag == "F") {
            int k;
            ls >> k >> force[k];
        } else if (tag == "R" || tag == "E") {
            want.push_back(line);
        }
    }

    if (!stages.empty()) {
        if (stages.size() != lp.program.stage_names.size()) {
            std::printf("FIRST FAIL: %zu stage names for %zu stages\n",
                        stages.size(), lp.program.stage_names.size());
            return 1;
        }
        lp.program.stage_names = stages;
    }
    const size_t n_events = lp.program.events.size();
    std::vector<std::string> got;
    try {
        metis::Live live(std::move(lp), canon);
        if (bound) live.bind(reg);
        live.seed(seed);
        size_t t = 0;
        for (int k = 0; k < samples; ++k) {
            metis::LiveEvent ev;
            auto a = at.find(k);
            if (a != at.end()) {
                ev = live.apply(a->second);
                got.push_back(row(live, ev));
            }
            auto f = force.find(k);
            if (f != force.end()) {
                int idx = -1;
                const auto& evs = live.program().program.events;
                for (size_t i = 0; i < evs.size(); ++i)
                    if (evs[i].name == f->second) idx = static_cast<int>(i);
                if (idx < 0 || !live.fire(idx, &ev))
                    throw std::runtime_error("cannot force " + f->second);
                got.push_back(row(live, ev));
            }
            if (live.step(&ev) == metis::StepResult::Fired) {
                got.push_back(row(live, ev));
                continue;
            }
            if (t == ticks.size()) {          // the host's episode is over
                live.latch_done();
                break;
            }
            ev = live.apply(ticks[t++]);
            got.push_back(row(live, ev));
        }
        got.push_back("E " + live.stage_name(live.stage()));
    } catch (const std::exception& e) {
        std::printf("FIRST FAIL: %s\n", e.what());
        return 1;
    }

    int ok = 0;
    const size_t total = std::max(want.size(), got.size());
    std::string first;
    for (size_t k = 0; k < total; ++k) {
        const std::string w = k < want.size() ? want[k] : "(none)";
        const std::string g = k < got.size() ? got[k] : "(none)";
        if (w == g) ++ok;
        else if (first.empty())
            first = "row " + std::to_string(k) + ": want '" + w + "', got '" + g + "'";
    }
    if (!first.empty()) std::printf("FIRST FAIL: %s\n", first.c_str());
    std::printf("LIVE PARITY %d/%zu (%s seed %llu, %zu events) %s\n", ok, total,
                name.c_str(), seed, n_events, argv[2]);
    return first.empty() && total > 0 ? 0 : 1;
}
