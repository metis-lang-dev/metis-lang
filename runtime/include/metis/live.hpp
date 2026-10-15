// SPDX-License-Identifier: Apache-2.0
// metis::Live — the live state of one served program (runtime-binding
// K1 + K2; metis-agent docs/RUNTIME-BINDING.md §3): the loaded artifact,
// the counts, the stage, the normative rng and what has fired. The
// reference is metispy's live REPL (metis/lang/repl.py), which samples by
// spec 06's sampler:
//
//   enabled()  the firing tier: the current stage's clauses with
//              choice weight > 0, port-priced (the policy), else its
//              links — in the NORMATIVE order (refsample.canonical_events:
//              the artifact sidecar's `canon`), not the wire's
//              (repl.py _candidates)
//   step()     one normative selection over enabled() and its firing
//              (repl.py _sample/_fire); Quiet when nothing is enabled —
//              the host decides (a tick's do-lines, or latch_done)
//   fire(i)    fire wire event i if it is enabled (a forced row)
//   apply()    one exogenous row from do-lines "+atom [n]" / "-atom [n]",
//              in order, a retract clamped at what is present; a latched
//              stage revives (repl.py _tick, fw/plugin.py exo_event)
//
// Every fired or applied row comes back as a LiveEvent. Masks, `why`,
// the watch and the host are the harness's, not the runtime's.
#pragma once

#include <cstdint>
#include <map>
#include <sstream>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

#include "metis/kernel.hpp"
#include "metis/loader.hpp"
#include "metis/registry.hpp"
#include "metis/sampler.hpp"

namespace metis {

struct LiveEvent {
    int index = -1;              // wire index; -1 = an exogenous row
    int canon = -1;              // normative index; -1 = exogenous
    std::string kind;            // "clause" | "link" | "exo"
    int stage = 0;               // the stage it fired in
    int post = -1;               // a link's destination
    std::string name;            // the event's; exo: "do +a -b 2" | "tick"
    std::vector<std::pair<std::string, int>> consume, produce, persist;
    std::vector<std::string> ops;  // exo: the applied do-lines, normalized
    double p = 0.0;              // its probability in the tier it fired
                                 // from (sampled/forced); 0 for exo
};

enum class StepResult { Fired, Quiet, Done };

class Live {
  public:
    // canon[i] = wire event i's normative index (sidecar events[i].canon);
    // empty = the wire's order is the normative one
    explicit Live(LoadedProgram lp, std::vector<int> canon = {})
        : lp_(std::move(lp)) {
        const size_t n = lp_.program.events.size();
        if (canon.empty())
            for (size_t i = 0; i < n; ++i) canon.push_back(static_cast<int>(i));
        if (canon.size() != n)
            throw std::invalid_argument("canon: " + std::to_string(canon.size()) +
                                        " entries for " + std::to_string(n) +
                                        " events");
        canon_ = canon;
        order_.assign(n, -1);
        for (size_t i = 0; i < n; ++i) {
            const int c = canon_[i];
            if (c < 0 || c >= static_cast<int>(n) || order_[c] != -1)
                throw std::invalid_argument("canon is not a permutation");
            order_[c] = static_cast<int>(i);
        }
        reset();
    }
    Live(const Live&) = delete;              // the policy holds &lp_.atoms
    Live& operator=(const Live&) = delete;

    // the weight ports, bound (fail-fast on an unbound factor, as
    // make_weight_policy); an empty registry leaves the tier unpriced
    void bind(const Registry& reg) {
        policy_ = make_weight_policy(lp_.refs, reg, lp_.atoms);
    }

    void seed(uint64_t s) { rng_ = SplitMix64(s); }

    // back to the artifact's init (the rng is left as it is)
    void reset() {
        counts_.clear();
        for (const auto& [a, n] : lp_.program.init)
            if (n > 0) counts_[a] = n;
        stage_ = lp_.program.init_stage;
        quiet_stage_ = -2;
        fired_ = 0;
    }

    // the firing tier, (wire index, weight) in the normative order
    std::vector<std::pair<int, double>> enabled() const {
        std::vector<std::pair<int, double>> ws;
        if (stage_ == kDone) return ws;
        const Counts c = counts();
        for (int tier = 0; tier < 2; ++tier) {
            for (int i : order_) {
                const Event& e = lp_.program.events[i];
                if ((e.post >= 0) != (tier == 1) || e.stage != stage_) continue;
                const double n = transition_count(e, c);
                const double w = n ? e.weight * n : 0.0;
                if (w > 0) ws.emplace_back(i, w);
            }
            if (!ws.empty() && policy_ && tier == 0) policy_(stage_, c, ws);
            if (!ws.empty()) return ws;
        }
        return ws;
    }

    StepResult step(LiveEvent* out = nullptr) {
        if (stage_ == kDone) return StepResult::Done;
        const auto ws = enabled();
        if (ws.empty()) return StepResult::Quiet;
        const size_t k = normative_pick(ws, rng_);
        fire_from(ws, k, out);
        return StepResult::Fired;
    }

    // fire wire event i when it is in the tier; false (nothing changes)
    // when it is not enabled now
    bool fire(int i, LiveEvent* out = nullptr) {
        const auto ws = enabled();
        for (size_t k = 0; k < ws.size(); ++k)
            if (ws[k].first == i) {
                fire_from(ws, k, out);
                return true;
            }
        return false;
    }

    // one exogenous row from do-lines; throws std::invalid_argument on a
    // malformed line (nothing applied then)
    LiveEvent apply(const std::vector<std::string>& lines) {
        std::map<std::string, int> before = named_counts(), after = before;
        LiveEvent ev;
        ev.kind = "exo";
        for (const auto& line : lines) {
            char sign;
            std::string atom;
            int n;
            parse_do_line(line, sign, atom, n);
            const int have = after.count(atom) ? after[atom] : 0;
            after[atom] = sign == '+' ? have + n : std::max(0, have - n);
            ev.ops.push_back(std::string(1, sign) + atom +
                             (n != 1 ? " " + std::to_string(n) : ""));
        }
        for (const auto& [a, n] : after) {   // after holds every atom of before
            const int d = n - (before.count(a) ? before[a] : 0);
            if (d < 0) ev.consume.emplace_back(a, -d);
            else if (d > 0) ev.produce.emplace_back(a, d);
        }
        ev.name = ev.ops.empty() ? "tick" : "do";
        for (const auto& op : ev.ops) ev.name += " " + op;
        if (stage_ == kDone)                 // a tick revives (G6)
            stage_ = quiet_stage_ != -2 ? quiet_stage_ : lp_.program.init_stage;
        counts_.clear();
        for (const auto& [a, n] : after)
            if (n > 0) counts_[lp_.atoms.get(a)] = n;
        ev.stage = stage_;
        ++fired_;
        return ev;
    }

    // nothing can fire and the host's episode is over: remember the
    // stage (a later apply revives it), then latch (repl.py _latch_done)
    void latch_done() {
        if (stage_ != kDone) quiet_stage_ = stage_;
        stage_ = kDone;
    }

    int stage() const { return stage_; }
    const std::string& stage_name(int s) const {
        static const std::string done = "(done)";
        return s == kDone ? done : lp_.program.stage_names.at(s);
    }
    size_t fired() const { return fired_; }
    const LoadedProgram& program() const { return lp_; }
    int canon(int i) const { return canon_.at(i); }

    // the counts, (atom id, n) sorted by id — the kernel's form
    Counts counts() const { return Counts(counts_.begin(), counts_.end()); }
    // the counts by atom name, bytewise sorted (python's sorted(items))
    std::map<std::string, int> named_counts() const {
        std::map<std::string, int> m;
        for (const auto& [a, n] : counts_) m[lp_.atoms.names[a]] = n;
        return m;
    }

    static void parse_do_line(const std::string& line, char& sign,
                              std::string& atom, int& n) {
        std::string s = trim(line);
        if (s.rfind("do ", 0) == 0) s = trim(s.substr(3));
        if (s.empty() || (s[0] != '+' && s[0] != '-'))
            throw std::invalid_argument("do-line '" + line +
                                        "': want +atom [n] or -atom [n]");
        sign = s[0];
        std::istringstream ls(s.substr(1));
        std::vector<std::string> parts;
        for (std::string t; ls >> t;) parts.push_back(t);
        if (parts.empty() || parts.size() > 2)
            throw std::invalid_argument("do-line '" + line + "': want +atom [n]");
        atom = parts[0];
        n = 1;
        if (parts.size() == 2) {
            size_t used = 0;
            try {
                n = std::stoi(parts[1], &used);
            } catch (const std::exception&) {
                used = 0;
            }
            if (used != parts[1].size())
                throw std::invalid_argument("do-line '" + line +
                                            "': count must be an integer");
            if (n < 0)
                throw std::invalid_argument("do-line '" + line +
                                            "': negative count");
        }
    }

  private:
    static std::string trim(const std::string& s) {
        const char* ws = " \t\r\n";
        const size_t b = s.find_first_not_of(ws);
        if (b == std::string::npos) return "";
        return s.substr(b, s.find_last_not_of(ws) - b + 1);
    }

    void fire_from(const std::vector<std::pair<int, double>>& ws, size_t k,
                   LiveEvent* out) {
        const int i = ws[k].first;
        double total = 0.0;
        for (const auto& iw : ws) total += iw.second;
        const Event& e = lp_.program.events[i];
        if (out) {
            out->index = i;
            out->canon = canon_[i];
            out->kind = e.post >= 0 ? "link" : "clause";
            out->stage = stage_;
            out->post = e.post;
            out->name = e.name;
            out->consume = named(e.consume);
            out->produce = named(e.produce);
            out->persist = named(e.persist);
            out->ops.clear();
            out->p = total > 0 ? ws[k].second / total : 0.0;
        }
        for (const auto& [a, n] : e.consume) counts_[a] -= n;
        for (const auto& [a, n] : e.produce) counts_[a] += n;
        for (auto it = counts_.begin(); it != counts_.end();)
            it = it->second > 0 ? std::next(it) : counts_.erase(it);
        if (e.post >= 0) stage_ = e.post;
        ++fired_;
    }

    std::vector<std::pair<std::string, int>> named(
        const std::vector<std::pair<Atom, int>>& v) const {
        std::vector<std::pair<std::string, int>> out;
        for (const auto& [a, n] : v) out.emplace_back(lp_.atoms.names[a], n);
        return out;
    }

    LoadedProgram lp_;
    std::vector<int> canon_, order_;   // wire→canon, canon→wire
    Policy policy_;
    SplitMix64 rng_{0};
    std::map<Atom, int> counts_;
    int stage_ = 0;
    int quiet_stage_ = -2;             // -2: never latched
    size_t fired_ = 0;
};

}  // namespace metis
