// SPDX-License-Identifier: Apache-2.0
// The sampler rung, C++ (docs/rewrite/06-sampler-wire.md): consume
// the CANONICAL PROGRAM BYTES (stage-38 wire — no grounder, per the
// §8.5 doctrine), run splitmix64 seeded traces with the normative
// selection arithmetic, and verify every R/F golden line. This is
// the evaluator ladder's bottom rung as deployed code: full
// language (multiplicities, quiescence — no class-F restriction),
// deterministic cost, cross-implementation verified.
//
// Horizon note: traces run at the CASE horizon (B line) — the
// (done) stage transition can happen on a step after the last
// recorded event, so the trace length alone under-runs the final
// state. One run per seed verifies both its R and F lines.
//
//   ./sample_run cpp/parity/sample_goldens.txt

#include <cstdint>
#include <cstdio>
#include <fstream>
#include <map>
#include <sstream>
#include <string>
#include <vector>

namespace {

struct Mset { std::vector<std::pair<std::string, long>> items; };

struct Event {
    bool is_link = false;
    std::string stage;           // clause: its stage; link: pre
    std::string post;            // links only
    Mset consume, produce, persist;
    double weight = 1.0;
};

Mset parse_mset(const std::string& s) {
    // items separate on TOP-LEVEL commas only: atoms like
    // anger(helena,hermia) carry commas inside parentheses
    Mset m;
    if (s == "-") return m;
    int depth = 0;
    size_t start = 0;
    auto push = [&](size_t end) {
        std::string item = s.substr(start, end - start);
        size_t c = item.rfind(':');
        m.items.push_back({item.substr(0, c),
                           std::stol(item.substr(c + 1))});
    };
    for (size_t i = 0; i < s.size(); ++i) {
        if (s[i] == '(') ++depth;
        else if (s[i] == ')') --depth;
        else if (s[i] == ',' && depth == 0) {
            push(i);
            start = i + 1;
        }
    }
    push(s.size());
    return m;
}

// splitmix64 (normative constants, 06-sampler-wire §3)
struct SplitMix64 {
    uint64_t s;
    explicit SplitMix64(uint64_t seed) : s(seed) {}
    uint64_t next() {
        s += 0x9E3779B97F4A7C15ULL;
        uint64_t z = s;
        z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
        z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
        return z ^ (z >> 31);
    }
    double unit() {
        return (next() >> 11) * (1.0 / 9007199254740992.0);
    }
};

long falling(long c, int n) {
    long w = 1;
    for (int i = 0; i < n; ++i) {
        w *= c - i;
        if (w <= 0) return 0;
    }
    return w;
}

struct Program {
    std::vector<Event> events;   // canonical order = file order
    std::string init_stage;
    std::map<std::string, long> init;
};

long tcount(const Event& e, const std::map<std::string, long>& m) {
    long w = 1;
    for (const auto& an : e.consume.items) {
        auto it = m.find(an.first);
        w *= falling(it == m.end() ? 0 : it->second,
                     (int)an.second);
        if (w == 0) return 0;
    }
    for (const auto& an : e.persist.items) {
        auto it = m.find(an.first);
        long c = it == m.end() ? 0 : it->second;
        for (long k = 0; k < an.second; ++k) w *= c;
        if (w == 0) return 0;
    }
    return w;
}

struct Trace { std::vector<int> idx; std::string fline; };

Trace run(const Program& p, int steps, int seed) {
    SplitMix64 rng((uint64_t)seed);
    std::map<std::string, long> counts = p.init;
    std::string stage = p.init_stage;
    Trace t;
    for (int s = 0; s < steps; ++s) {
        if (stage == "(done)") break;
        std::vector<std::pair<int, double>> ws;
        for (int pass = 0; pass < 2 && ws.empty(); ++pass) {
            bool link = pass == 1;
            for (size_t i = 0; i < p.events.size(); ++i) {
                const Event& e = p.events[i];
                if (e.is_link != link || e.stage != stage) continue;
                long n = tcount(e, counts);
                if (n <= 0) continue;
                double w = e.weight * (double)n;
                if (w > 0) ws.push_back({(int)i, w});
            }
        }
        if (ws.empty()) { stage = "(done)"; continue; }
        double total = 0;
        for (const auto& iw : ws) total += iw.second;
        double threshold = rng.unit() * total;
        int chosen = ws.back().first;
        double acc = 0;
        for (const auto& iw : ws) {
            acc += iw.second;
            if (threshold < acc) { chosen = iw.first; break; }
        }
        t.idx.push_back(chosen);
        const Event& e = p.events[chosen];
        for (const auto& an : e.consume.items) {
            long c = (counts.count(an.first) ? counts[an.first]
                                             : 0) - an.second;
            if (c > 0) counts[an.first] = c;
            else counts.erase(an.first);
        }
        for (const auto& an : e.produce.items)
            counts[an.first] += an.second;
        if (e.is_link) stage = e.post;
    }
    // F payload: sorted atom:count (std::map iterates bytewise-
    // sorted; atoms are ASCII, matching the python/ocaml sort)
    std::string f = stage;
    for (const auto& an : counts)
        if (an.second > 0)
            f += " " + an.first + ":" + std::to_string(an.second);
    t.fline = f;
    return t;
}

}  // namespace

int main(int argc, char** argv) {
    if (argc != 2) {
        std::fprintf(stderr, "usage: sample_run <goldens>\n");
        return 2;
    }
    std::ifstream in(argv[1]);
    if (!in) { std::fprintf(stderr, "cannot open input\n"); return 2; }
    std::string line, cur_stage;
    Program prog;
    int case_steps = 0;
    std::map<int, std::string> flines;   // seed -> computed F payload
    int ok = 0, total = 0, cases = 0;
    std::string first_fail;
    auto fail = [&](const std::string& msg) {
        if (first_fail.empty()) first_fail = msg;
    };
    while (std::getline(in, line)) {
        if (line.empty() || line[0] == '#') continue;
        std::stringstream ss(line);
        std::string tag;
        ss >> tag;
        if (tag == "B") {
            prog = Program(); cur_stage.clear(); flines.clear();
            std::string name; ss >> name >> case_steps;
            ++cases;
        } else if (tag == "metis-canonical") {
            // canonical block header
        } else if (tag == "stage") {
            ss >> cur_stage;
        } else if (tag == "c" || tag == "l") {
            Event e;
            e.is_link = (tag == "l");
            std::string semi, wtag, cons, prod, pers;
            if (e.is_link) {
                std::string pre, post;
                ss >> pre >> post >> semi;
                e.stage = pre; e.post = post;
            } else {
                e.stage = cur_stage;
            }
            ss >> cons >> semi >> prod >> semi >> pers >> semi
               >> wtag >> e.weight;
            e.consume = parse_mset(cons);
            e.produce = parse_mset(prod);
            e.persist = parse_mset(pers);
            prog.events.push_back(e);
        } else if (tag == "init-stage") {
            ss >> prog.init_stage;
        } else if (tag == "i") {
            std::string item;
            ss >> item;
            size_t c = item.rfind(':');
            prog.init[item.substr(0, c)] =
                std::stol(item.substr(c + 1));
        } else if (tag == "E") {
            size_t n; ss >> n;
            ++total;
            if (n == prog.events.size()) ++ok;
            else fail("event count mismatch");
        } else if (tag == "R") {
            int seed, k; ss >> seed >> k;
            std::vector<int> want(k);
            for (int i = 0; i < k; ++i) ss >> want[i];
            Trace t = run(prog, case_steps, seed);
            ++total;
            if (t.idx == want) ++ok;
            else fail("R mismatch seed " + std::to_string(seed));
            flines[seed] = t.fline;
        } else if (tag == "F") {
            int seed; ss >> seed;
            std::string rest;
            std::getline(ss, rest);
            if (!rest.empty() && rest[0] == ' ') rest.erase(0, 1);
            ++total;
            if (flines.count(seed) && flines[seed] == rest) ++ok;
            else fail("F mismatch seed " + std::to_string(seed)
                      + " got [" + (flines.count(seed)
                                    ? flines[seed] : "<none>")
                      + "] want [" + rest + "]");
        }
        // "." ends a case; nothing to do
    }
    if (!first_fail.empty())
        std::printf("FIRST FAIL: %s\n", first_fail.c_str());
    std::printf("SAMPLE PARITY %d/%d (%d cases)\n", ok, total,
                cases);
    return ok == total && total > 0 ? 0 : 1;
}
