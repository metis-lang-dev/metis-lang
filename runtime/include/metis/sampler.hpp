// SPDX-License-Identifier: Apache-2.0
// The trajectory sampler — port of kernel/sampler.py with the same
// policy-hook semantics as the filter, so exact and sampled draws come
// from ONE measure (self-consistency checked by the parity runner; no
// cross-language RNG parity is claimed — seeds are engine-local).
#pragma once

#include <random>

#include "metis/kernel.hpp"

namespace metis {

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
