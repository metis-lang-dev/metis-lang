// SPDX-License-Identifier: Apache-2.0
// The artifact loader — the product API for consuming a compiled
// ground program (the same wire gen_goldens.py emits: N/E/I/S
// records). BT.cpp's XML-loading analog: python compiles and
// certifies, C++ loads and runs. golden.hpp keeps its own frozen
// copy of this parsing (it is the conformance harness and must not
// share fate with product code); the fw smoke gate pins this one
// against analytic values.
#pragma once

#include <istream>
#include <map>
#include <sstream>
#include <string>
#include <vector>

#include "metis/kernel.hpp"
#include "metis/registry.hpp"

namespace metis {

struct LoadedProgram {
    Program program;
    std::vector<WeightRef> refs;     // parallel to program.events
    int steps = 0;                   // horizon carried by the artifact
    Interner atoms;
    // the B port manifest — what the artifact requires the consuming
    // registry to bind (fw.Evaluator._validate parity); empty on
    // conformance goldens, populated on product artifacts
    // (kernel/wire.py emit_artifact)
    std::vector<std::string> ports_in, ports_out, ports_guard,
        ports_weight;
    bool ok = false;
    std::string error;
};

// Reads one program (N header through the records that follow it);
// stops before any non-program record. Returns ok=false with a
// message on malformed input — loading is admission's last gate.
inline LoadedProgram load_program(std::istream& in) {
    LoadedProgram lp;
    bool seen_n = false;
    std::string line;
    while (in.peek() != EOF) {
        std::streampos pos = in.tellg();
        if (!std::getline(in, line)) break;
        if (line.empty() || line[0] == '#') continue;
        std::istringstream ls(line);
        std::string tag;
        ls >> tag;
        if (tag == "N") {
            if (seen_n) {                    // next program starts
                in.seekg(pos);
                break;
            }
            seen_n = true;
            int n;
            ls >> n >> lp.program.init_stage;
            lp.program.stage_names.assign(n, "");
        } else if (tag == "E") {
            Event e;
            WeightRef ref;
            ls >> e.stage >> e.post >> e.weight >> e.name;
            std::string tok;
            int sec = 0;                     // 1=c 2=o 3=p 4=w
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
                dst.emplace_back(lp.atoms.get(a), n);
            }
            lp.program.events.push_back(std::move(e));
            lp.refs.push_back(std::move(ref));
        } else if (tag == "I") {
            std::string a;
            int n;
            std::map<Atom, int> init;
            while (ls >> a >> n) init[lp.atoms.get(a)] = n;
            lp.program.init.assign(init.begin(), init.end());
        } else if (tag == "S") {
            ls >> lp.steps;
        } else if (tag == "B") {             // port-manifest record
            std::string kind, name;
            ls >> kind >> name;
            if (kind == "in") lp.ports_in.push_back(name);
            else if (kind == "out") lp.ports_out.push_back(name);
            else if (kind == "guard") lp.ports_guard.push_back(name);
            else if (kind == "weight") lp.ports_weight.push_back(name);
            else {
                lp.error = "unknown port kind '" + kind + "'";
                return lp;
            }
        } else {                             // expectation/other record
            in.seekg(pos);
            break;
        }
    }
    if (!seen_n) {
        lp.error = "no program record (N) found";
        return lp;
    }
    lp.ok = true;
    return lp;
}

inline LoadedProgram load_program(const std::string& text) {
    std::istringstream in(text);
    return load_program(in);
}

}  // namespace metis
