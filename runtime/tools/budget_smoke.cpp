// SPDX-License-Identifier: Apache-2.0
// max_states budget smoke (the wayplan-oom-hardening kernel API,
// merged from chariot_ws): self-checking, mirrors fw_smoke.
//
// Program: a coin bank — n independent coins, flipped in ANY order
// (slice sizes for n=6: 1, 12, 60, 160, 240, 192, 64). Checks:
//   1. default (0): exact measure, overflowed() false, full support;
//   2. budget crossing mid-horizon: overflowed() true and final()
//      is the LAST COMPLETE slice (mass 1) — a
//      truncated horizon, never a partial slice;
//   3. generous budget: identical to default (opt-in is inert
//      until crossed).

#include <cstdio>
#include <cmath>
#include "metis/kernel.hpp"

using namespace metis;

static Program coin_bank(Interner& in, int n) {
    Program p;
    p.stage_names = {"flip"};
    for (int i = 0; i < n; ++i) {
        for (int face = 0; face < 2; ++face) {
            Event e;
            e.stage = 0;
            e.post = -1;
            e.weight = 1.0;
            e.consume = {{in.get("t" + std::to_string(i)), 1}};
            e.produce = {{in.get(std::string(face ? "h" : "l")
                                 + std::to_string(i)), 1}};
            p.events.push_back(e);
        }
    }
    p.init_stage = 0;
    p.init = {{in.get("t0"), 1}};
    for (int i = 1; i < n; ++i)
        p.init.push_back({in.get("t" + std::to_string(i)), 1});
    return p;
}

static double mass(const Dist& d) {
    double z = 0;
    for (const auto& [s, pr] : d) z += pr;
    return z;
}

int main() {
    int fails = 0;
    auto check = [&](bool ok, const char* what) {
        if (!ok) { std::printf("FAIL: %s\n", what); ++fails; }
    };

    {
        Interner in;
        Program p = coin_bank(in, 6);
        ForwardProjection pr(p, 6);
        check(!pr.overflowed(), "default: overflowed() must be false");
        check(pr.final().size() == 64, "default: 2^6 final support");
        check(std::abs(mass(pr.final()) - 1.0) < 1e-12,
              "default: mass 1");
    }
    {
        Interner in;
        Program p = coin_bank(in, 6);
        // slices grow 1,12,60,... — budget 20 admits slice 1 only
        ForwardProjection pr(p, 6, nullptr, nullptr, 20);
        check(pr.overflowed(), "budget 20: overflowed() must be true");
        check(pr.final().size() == 12,
              "budget 20: final is the LAST COMPLETE slice (12)");
        check(std::abs(mass(pr.final()) - 1.0) < 1e-12,
              "budget 20: complete slice has mass 1");
    }
    {
        Interner in;
        Program p = coin_bank(in, 6);
        ForwardProjection pr(p, 6, nullptr, nullptr, 300);
        check(!pr.overflowed(), "budget 300: inert until crossed");
        check(pr.final().size() == 64, "budget 300: full support");
    }

    if (fails) return 1;
    std::printf("BUDGET SMOKE OK\n");
    return 0;
}
