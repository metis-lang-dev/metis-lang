// The metis measure core in C++ — port of metis/kernel/{clause,weight,
// program,filter}.py. Python is semantic truth (the v1 doctrine): this
// header exists to be BIT-CLOSE to the oracle, proven by the golden
// corpus (cpp/parity), never the other way around.
//
// Scope (stage 8 v1): ground programs (grounding stays python-side —
// the pack/instance pipeline serializes ground programs), exact
// reachable-support filtering with the three-tier CHOICE, clause
// priors, policy hook for weight-port bindings (the C++ registry).
#pragma once

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <functional>
#include <map>
#include <string>
#include <unordered_map>
#include <vector>

namespace metis {

using Atom = uint32_t;

struct Interner {
    std::unordered_map<std::string, Atom> ids;
    std::vector<std::string> names;
    Atom get(const std::string& s) {
        auto it = ids.find(s);
        if (it != ids.end()) return it->second;
        Atom a = static_cast<Atom>(names.size());
        ids.emplace(s, a);
        names.push_back(s);
        return a;
    }
};

// sorted (atom,count) pairs — the canonical multiset (python's
// frozenset-of-items, ordered for hashing)
using Counts = std::vector<std::pair<Atom, int>>;

inline int count_of(const Counts& c, Atom a) {
    for (const auto& [x, n] : c)
        if (x == a) return n;
    return 0;
}

struct Event {                       // clause or link, one table
    std::string name;
    int stage = 0;                   // owning stage index
    int post = -1;                   // link: destination stage; -1 = clause
    std::vector<std::pair<Atom, int>> consume, produce, persist;
    double weight = 1.0;
};

struct Program {
    std::vector<std::string> stage_names;
    std::vector<Event> events;       // clauses in stage order, then links
    int init_stage = 0;
    Counts init;
};

// -- CHOICE weights (weight.py verbatim) ---------------------------------

inline double falling_factorial(int c, int n) {
    double w = 1;
    for (int i = 0; i < n; ++i) {
        w *= c - i;
        if (w <= 0) return 0;
    }
    return w;
}

inline double transition_count(const Event& e, const Counts& counts) {
    double w = 1;
    for (const auto& [a, n] : e.consume) {
        w *= falling_factorial(count_of(counts, a), n);
        if (w == 0) return 0;
    }
    for (const auto& [a, n] : e.persist) {
        w *= std::pow(static_cast<double>(count_of(counts, a)), n);
        if (w == 0) return 0;
    }
    return w;
}

// -- states --------------------------------------------------------------

constexpr int kDone = -1;

struct State {
    int stage;
    Counts kappa;
    bool operator==(const State& o) const {
        return stage == o.stage && kappa == o.kappa;
    }
};

struct StateHash {
    size_t operator()(const State& s) const {
        size_t h = std::hash<int>()(s.stage);
        for (const auto& [a, n] : s.kappa)
            h = h * 1000003u ^ (static_cast<size_t>(a) * 31u + n);
        return h;
    }
};

using Dist = std::unordered_map<State, double, StateHash>;

// policy hook: reweight tier-0 candidates in place (drop = weight 0) —
// the filter.py contract; the C++ REGISTRY binds weight ports here.
using Policy = std::function<void(
    int stage, const Counts&, std::vector<std::pair<int, double>>&)>;

// per-slice observer (the BT.cpp logger seam): called after every
// step with (t, slice distribution) — feed it your tracer, a
// file, or nothing. Purely observational; the measure is untouched.
using Observer = std::function<void(int, const Dist&)>;

// -- the exact filter (filter.py verbatim, simple-scan tiers) ------------

class ForwardProjection {
  public:
    // max_states: OPT-IN resource guard (0 = unlimited, the default —
    // the exact measure, parity-policed). A step that would grow the
    // slice past the budget aborts the projection: overflowed() turns
    // true, stepping stops, and final() is the LAST COMPLETE slice —
    // a truncated horizon, NOT the measure. Callers that set a budget
    // MUST check overflowed() before trusting final(). Peak memory is
    // bounded by two slices of max_states states.
    ForwardProjection(const Program& p, int steps,
                      Policy policy = nullptr,
                      Observer observe = nullptr,
                      size_t max_states = 0)
        : prog_(p), policy_(std::move(policy)) {
        // rarest-atom tier index (filter.py / lolli lineage): per
        // (stage, kind), events keyed by their least-common consume
        // atom so a state only inspects possibly-enabled candidates
        // — pure pruning of zero-weight candidates (an event whose
        // consume atoms are absent weighs 0 in the scan too).
        int nstages = static_cast<int>(p.stage_names.size());
        tiers_.assign(static_cast<size_t>(nstages) * 2, Tier{});
        for (int kind = 0; kind < 2; ++kind) {
            std::unordered_map<Atom, int> freq;
            for (const auto& e : p.events)
                if ((e.post >= 0) == (kind == 1))
                    for (const auto& [a, n] : e.consume) freq[a] += 1;
            for (size_t i = 0; i < p.events.size(); ++i) {
                const Event& e = p.events[i];
                if ((e.post >= 0) != (kind == 1)) continue;
                Tier& t = tiers_[e.stage * 2 + kind];
                if (e.consume.empty()) {
                    t.keyless.push_back(static_cast<int>(i));
                    continue;
                }
                Atom key = e.consume.front().first;
                for (const auto& [a, n] : e.consume)
                    if (freq[a] < freq[key]) key = a;
                t.by_atom[key].push_back(static_cast<int>(i));
            }
        }
        Dist dist;
        dist.emplace(State{p.init_stage, p.init}, 1.0);
        for (int t = 0; t < steps; ++t) {
            bool ovf = false;
            Dist next = step_(dist, max_states, &ovf);
            if (ovf) {
                overflowed_ = true;
                break;  // keep the last complete slice as final_
            }
            dist = std::move(next);
            if (observe) observe(t + 1, dist);
        }
        final_ = std::move(dist);
    }

    const Dist& final() const { return final_; }

    bool overflowed() const { return overflowed_; }

    std::vector<double> final_distribution(Atom a) const {
        std::map<int, double> by_count;
        for (const auto& [s, p] : final_)
            by_count[count_of(s.kappa, a)] += p;
        int card = std::max(2, by_count.rbegin()->first + 1);
        std::vector<double> out(card, 0.0);
        for (const auto& [c, p] : by_count) out[c] = p;
        return out;
    }

    double p_done() const {
        double p = 0;
        for (const auto& [s, q] : final_)
            if (s.stage == kDone) p += q;
        return p;
    }

    size_t n_reachable() const { return final_.size(); }

  private:
    std::vector<std::pair<int, double>> choice_(
        int stage, const Counts& counts) const {
        if (stage == kDone) return {{-1, 1.0}};
        for (int tier = 0; tier < 2; ++tier) {
            std::vector<std::pair<int, double>> ws;
            const Tier& t = tiers_[stage * 2 + tier];
            auto consider = [&](int i) {
                const Event& e = prog_.events[i];
                double w = e.weight * transition_count(e, counts);
                if (w > 0) ws.emplace_back(i, w);
            };
            for (int i : t.keyless) consider(i);
            for (const auto& [a, n] : counts) {
                if (n <= 0) continue;
                auto it = t.by_atom.find(a);
                if (it == t.by_atom.end()) continue;
                for (int i : it->second) consider(i);
            }
            if (!ws.empty() && policy_ && tier == 0)
                policy_(stage, counts, ws);
            double tot = 0;
            for (const auto& [i, w] : ws) tot += w;
            if (tot > 0) {
                std::vector<std::pair<int, double>> out;
                for (const auto& [i, w] : ws)
                    if (w > 0) out.emplace_back(i, w / tot);
                return out;
            }
        }
        return {{-1, 1.0}};
    }

    State apply_(int stage, const Counts& counts, int e) const {
        if (e < 0) return State{kDone, counts};
        const Event& ev = prog_.events[e];
        std::map<Atom, int> knew(counts.begin(), counts.end());
        for (const auto& [a, n] : ev.consume) knew[a] -= n;
        for (const auto& [a, n] : ev.produce) knew[a] += n;
        Counts out;
        for (const auto& [a, n] : knew)
            if (n > 0) out.emplace_back(a, n);
        return State{ev.post >= 0 ? ev.post : stage, std::move(out)};
    }

    // bails MID-step once the budget is crossed — the whole point is
    // never to materialize the oversized slice
    Dist step_(const Dist& dist, size_t max_states,
               bool* overflow) const {
        Dist out;
        for (const auto& [s, p] : dist) {
            for (const auto& [e, pe] : choice_(s.stage, s.kappa)) {
                State nxt = apply_(s.stage, s.kappa, e);
                out[std::move(nxt)] += p * pe;
                if (max_states && out.size() > max_states) {
                    *overflow = true;
                    return out;
                }
            }
        }
        return out;
    }

    Program prog_;
    Policy policy_;
    bool overflowed_ = false;
    struct Tier {
        std::unordered_map<Atom, std::vector<int>> by_atom;
        std::vector<int> keyless;
    };
    std::vector<Tier> tiers_;
    Dist final_;
};

}  // namespace metis
