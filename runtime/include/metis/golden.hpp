// SPDX-License-Identifier: Apache-2.0
// Golden-file runner as a library — the parity engine the CLI wraps
// and an embedding runtime can call live (a conformance oracle).
#pragma once

#include <cmath>
#include <fstream>
#include <map>
#include <sstream>
#include <string>

#include "metis/kernel.hpp"
#include "metis/registry.hpp"

namespace metis {

// TEST bindings for the port-weighted corpus (sysadmin n=2). In
// production, bindings are DOMAIN code registered by the linking node
// (docs/integration-design.md); the parity runner carries these only
// so port-weighted goldens exercise the registry path end to end.
inline Registry test_registry() {
    Registry reg;
    reg.weight("cpt", [](const std::vector<std::string>& args,
                         const CountsView& v) {
        const std::string& c = args[0];
        if (v.has("rb(" + c + ")")) return 1.0;
        static const std::unordered_map<std::string,
            std::vector<std::string>> adj{{"a", {"b"}}, {"b", {"a"}}};
        const auto& ins = adj.at(c);
        int r = 0;
        for (const auto& y : ins)
            if (v.has("prev(" + y + ")")) ++r;
        return 0.45 + 0.5 * (1 + r) / (1.0 + ins.size());
    });
    reg.weight("rp", [](const std::vector<std::string>& args,
                        const CountsView& v) {
        return v.has("rb(" + args[0] + ")") ? 1.0 : 0.04;
    });
    return reg;
}

struct GoldenResult {
    int ok = 0, total = 0, cases = 0;
    std::string first_fail;
};

inline GoldenResult run_goldens(const std::string& path) {
    GoldenResult res;
    std::ifstream in(path);
    if (!in) {
        res.first_fail = "cannot open " + path;
        return res;
    }
    Interner atoms;
    Program prog;
    std::vector<WeightRef> refs;
    Registry reg = test_registry();
    int steps = 0;
    ForwardProjection* pr = nullptr;

    auto ensure = [&]() {
        if (pr) return;
        bool ported = false;
        for (const auto& r : refs)
            if (!r.factor.empty()) ported = true;
        Policy pol = ported ? make_weight_policy(refs, reg, atoms)
                            : Policy{};
        pr = new ForwardProjection(prog, steps, pol);
    };
    auto check = [&](bool good, const std::string& what) {
        ++res.total;
        if (good) ++res.ok;
        else if (res.first_fail.empty())
            res.first_fail = "case " + std::to_string(res.cases) +
                             ": " + what;
    };

    std::string line;
    while (std::getline(in, line)) {
        if (line.empty() || line[0] == '#') continue;
        std::istringstream ls(line);
        std::string tag;
        ls >> tag;
        if (tag == "N") {
            delete pr;
            pr = nullptr;
            prog = Program{};
            refs.clear();
            int n;
            ls >> n >> prog.init_stage;
            prog.stage_names.assign(n, "");
        } else if (tag == "E") {
            Event e;
            WeightRef ref;
            ls >> e.stage >> e.post >> e.weight >> e.name;
            std::string tok;
            int sec = 0;                    // 1=c 2=o 3=p 4=w
            while (ls >> tok) {
                if (tok == ";") { sec = 0; continue; }
                if (sec == 0) {
                    sec = tok == "c" ? 1 : tok == "o" ? 2
                        : tok == "p" ? 3 : 4;
                    if (sec == 4) {
                        int compl_;
                        ls >> ref.factor >> compl_;
                        ref.complement = compl_ != 0;
                    }
                    continue;
                }
                if (sec == 4) {
                    ref.args.push_back(tok);
                    continue;
                }
                int n;
                std::string a = tok;
                ls >> n;
                auto& dst = sec == 1 ? e.consume
                          : sec == 2 ? e.produce : e.persist;
                dst.emplace_back(atoms.get(a), n);
            }
            prog.events.push_back(std::move(e));
            refs.push_back(std::move(ref));
        } else if (tag == "I") {
            std::string a;
            int n;
            std::map<Atom, int> init;
            while (ls >> a >> n) init[atoms.get(a)] = n;
            prog.init.assign(init.begin(), init.end());
        } else if (tag == "S") {
            ls >> steps;
        } else if (tag == "Q") {
            ensure();
            std::string a;
            ls >> a;
            std::vector<double> want,
                got = pr->final_distribution(atoms.get(a));
            double v;
            while (ls >> v) want.push_back(v);
            bool good = got.size() == want.size();
            for (size_t i = 0; good && i < want.size(); ++i)
                good = std::fabs(got[i] - want[i]) <= 1e-9;
            check(good, "Q " + a);
        } else if (tag == "D") {
            ensure();
            double v;
            ls >> v;
            check(std::fabs(pr->p_done() - v) <= 1e-9, "D");
        } else if (tag == "R") {
            ensure();
            size_t v;
            ls >> v;
            check(pr->n_reachable() == v, "R");
        } else if (tag == ".") {
            ++res.cases;
            delete pr;
            pr = nullptr;
        }
    }
    delete pr;
    return res;
}

}  // namespace metis
