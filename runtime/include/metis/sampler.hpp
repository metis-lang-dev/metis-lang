// SPDX-License-Identifier: Apache-2.0
// The samplers.
//
// The NORMATIVE one (spec 06, docs/rewrite/06-sampler-wire.md; OCaml
// `metisc --sample` is authoritative, metispy refsample.py and the live
// REPL sample by it): SplitMix64 with the normative constants and the
// normative selection — threshold = unit() * total (a left-to-right
// sum), the first candidate with threshold < its running sum, else the
// last. Byte-identical traces across OCaml, Python and C++
// (tools/sample_run: SAMPLE PARITY; metis::Live, live.hpp).
//
// run_once below is the older engine-local trajectory sampler — a port
// of kernel/sampler.py with the filter's policy hook, so exact and
// sampled draws come from ONE measure; no cross-language RNG parity is
// claimed for it (mt19937, seeds engine-local).
#pragma once

#include <cstdint>
#include <random>
#include <utility>
#include <vector>

#include "metis/kernel.hpp"

namespace metis {

// splitmix64, normative constants (06-sampler-wire §3)
struct SplitMix64 {
    uint64_t state;
    explicit SplitMix64(uint64_t seed = 0) : state(seed) {}
    uint64_t next() {
        state += 0x9E3779B97F4A7C15ULL;
        uint64_t z = state;
        z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
        z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
        return z ^ (z >> 31);
    }
    double unit() {
        return static_cast<double>(next() >> 11) *
               (1.0 / 9007199254740992.0);
    }
};

// The normative selection (06-sampler-wire §4) over a non-empty tier
// of (key, weight > 0) in its normative order: one unit() drawn.
// Returns the position in `ws`.
template <class Key>
size_t normative_pick(const std::vector<std::pair<Key, double>>& ws,
                      SplitMix64& rng) {
    double total = 0.0;
    for (const auto& kw : ws) total += kw.second;
    const double threshold = rng.unit() * total;
    double acc = 0.0;
    for (size_t k = 0; k < ws.size(); ++k) {
        acc += ws[k].second;
        if (threshold < acc) return k;
    }
    return ws.size() - 1;
}

inline State run_once(const Program& p, int steps, std::mt19937& rng,
                      const Policy& policy = nullptr) {
    int stage = p.init_stage;
    Counts counts = p.init;
    std::uniform_real_distribution<double> uni(0.0, 1.0);
    for (int t = 0; t < steps; ++t) {
        if (stage == kDone) break;
        int chosen = -2;
        for (int tier = 0; tier < 2 && chosen == -2; ++tier) {
            std::vector<std::pair<int, double>> ws;
            for (size_t i = 0; i < p.events.size(); ++i) {
                const Event& e = p.events[i];
                bool is_link = e.post >= 0;
                if ((tier == 1) != is_link || e.stage != stage)
                    continue;
                double w = e.weight * transition_count(e, counts);
                if (w > 0) ws.emplace_back(static_cast<int>(i), w);
            }
            if (!ws.empty() && policy && tier == 0)
                policy(stage, counts, ws);
            double tot = 0;
            for (auto& [i, w] : ws) tot += w;
            if (tot > 0) {
                double x = uni(rng) * tot;
                for (auto& [i, w] : ws) {
                    x -= w;
                    if (x <= 0) { chosen = i; break; }
                }
                if (chosen == -2) chosen = ws.back().first;
            }
        }
        if (chosen == -2) { stage = kDone; continue; }
        const Event& ev = p.events[chosen];
        std::map<Atom, int> knew(counts.begin(), counts.end());
        for (auto& [a, n] : ev.consume) knew[a] -= n;
        for (auto& [a, n] : ev.produce) knew[a] += n;
        counts.clear();
        for (auto& [a, n] : knew)
            if (n > 0) counts.emplace_back(a, n);
        if (ev.post >= 0) stage = ev.post;
    }
    return State{stage, counts};
}

}  // namespace metis
