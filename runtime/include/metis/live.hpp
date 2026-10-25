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
//   snapshot() / restore()   K3: the live state as portable text — the
//              counts by atom name, the stage and the latched stage by
//              name, the rng state, the fired length — so it outlives a
//              reload of the same program (metispy's fork/back contract)
//   likelihood(from, steps, observed)   K4: P(observed | the program,
//              from a snapshot's state, over `steps`), priced as the
//              tier is (kernel/record.py surprise_record: the watch's
//              surprise test and the record's likelihood)
//
// Every fired or applied row comes back as a LiveEvent. Masks, `why`,
// the watch and the host are the harness's, not the runtime's.
#pragma once

#include <algorithm>
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
        : lp_(std::move(lp)), tiers_(build_tiers(lp_.program)) {
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
        std::map<Atom, int> counts;
        for (const auto& [a, n] : lp_.program.init)
            if (n > 0) counts[a] = n;
        set_counts_(std::move(counts));
        stage_ = lp_.program.init_stage;
        quiet_stage_ = -2;
        fired_ = 0;
    }

    // the firing tier, (wire index, weight) in the normative order. The
    // candidates are the tier index's (keyless + those keyed by a present
    // atom), sorted by canon index: an event left out has a consume atom at
    // count 0, so the full scan weighs it 0 and drops it too — the same
    // list, element for element (eval-perf step 2g)
    std::vector<std::pair<int, double>> enabled() const {
        std::vector<std::pair<int, double>> ws;
        if (stage_ == kDone) return ws;
        for (int tier = 0; tier < 2; ++tier) {
            const TierIndex& t = tiers_[stage_ * 2 + tier];
            std::vector<int> cand(t.keyless);
            for (const auto& [a, n] : counts_) {
                auto it = t.by_atom.find(a);
                if (it != t.by_atom.end())
                    cand.insert(cand.end(), it->second.begin(), it->second.end());
            }
            std::sort(cand.begin(), cand.end(),
                      [this](int x, int y) { return canon_[x] < canon_[y]; });
            for (int i : cand) {
                const Event& e = lp_.program.events[i];
                const double n = transition_count(e, dense_);
                const double w = n ? e.weight * n : 0.0;
                if (w > 0) ws.emplace_back(i, w);
            }
            if (!ws.empty() && policy_ && tier == 0) policy_(stage_, counts(), ws);
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
        std::map<Atom, int> counts;
        for (const auto& [a, n] : after)
            if (n > 0) counts[lp_.atoms.get(a)] = n;
        set_counts_(std::move(counts));
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

    // -- K3: snapshot / restore ------------------------------------------

    std::string snapshot() const {
        std::string s = "metis-live 1\nstage " + stage_ref(stage_) +
                        "\nquiet " + (quiet_stage_ == -2 ? "-" : stage_ref(quiet_stage_)) +
                        "\nrng " + std::to_string(rng_.state) +
                        "\nfired " + std::to_string(fired_) + "\n";
        for (const auto& [a, n] : named_counts())
            s += "count " + a + " " + std::to_string(n) + "\n";
        return s;
    }

    // all or nothing: a malformed snapshot or an unknown stage throws
    // std::invalid_argument and the state is unchanged
    void restore(const std::string& snap) {
        Parsed p = parse_snapshot(snap);
        std::map<Atom, int> counts;
        for (const auto& [a, n] : p.counts)
            if (n > 0) counts[lp_.atoms.get(a)] = n;
        set_counts_(std::move(counts));
        stage_ = p.stage;
        quiet_stage_ = p.quiet;
        rng_.state = p.rng;
        fired_ = p.fired;
    }

    // -- K4: projection from a given state ----------------------------------

    // the snapshot's state as the kernel's State (atoms interned)
    State state_of(const std::string& snap) {
        Parsed p = parse_snapshot(snap);
        std::map<Atom, int> counts;
        for (const auto& [a, n] : p.counts)
            if (n > 0) counts[lp_.atoms.get(a)] = n;
        return State{p.stage, Counts(counts.begin(), counts.end())};
    }

    ForwardProjection project(const State& from, int steps) const {
        return ForwardProjection(lp_.program, from, steps, policy_);
    }

    // P(every observed atom has exactly its count | from, steps): an atom
    // the program never names counts 0 unless the state carries it
    double likelihood(const std::string& from, int steps,
                      const std::map<std::string, int>& observed) {
        const State s0 = state_of(from);
        std::vector<std::pair<Atom, int>> want;
        for (const auto& [a, n] : observed) want.emplace_back(lp_.atoms.get(a), n);
        const ForwardProjection pr = project(s0, steps);
        double like = 0.0;
        for (const auto& [s, p] : pr.final()) {
            bool ok = true;
            for (const auto& [a, n] : want)
                if (count_of(s.kappa, a) != n) { ok = false; break; }
            if (ok) like += p;
        }
        return like;
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
    struct Parsed {
        int stage = 0, quiet = -2;
        uint64_t rng = 0;
        size_t fired = 0;
        std::map<std::string, int> counts;
    };

    // a stage by name when its name is unique and not empty (a wire
    // without the sidecar's names): "#<index>" otherwise
    std::string stage_ref(int s) const {
        if (s == kDone) return "(done)";
        const auto& names = lp_.program.stage_names;
        const std::string& n = names.at(s);
        if (!n.empty() && std::count(names.begin(), names.end(), n) == 1) return n;
        return "#" + std::to_string(s);
    }

    int stage_of(const std::string& ref) const {
        if (ref == "(done)") return kDone;
        const auto& names = lp_.program.stage_names;
        if (!ref.empty() && ref[0] == '#') {
            const int s = std::stoi(ref.substr(1));
            if (s >= 0 && s < static_cast<int>(names.size())) return s;
        }
        for (size_t i = 0; i < names.size(); ++i)
            if (!names[i].empty() && names[i] == ref) return static_cast<int>(i);
        throw std::invalid_argument("snapshot: no stage '" + ref + "' here");
    }

    Parsed parse_snapshot(const std::string& snap) const {
        Parsed p;
        std::istringstream in(snap);
        std::string line;
        if (!std::getline(in, line) || line != "metis-live 1")
            throw std::invalid_argument("snapshot: not a metis-live 1 snapshot");
        bool stage = false, quiet = false, rng = false, fired = false;
        while (std::getline(in, line)) {
            if (line.empty()) continue;
            std::istringstream ls(line);
            std::string tag, v;
            ls >> tag >> v;
            if (tag == "stage") { p.stage = stage_of(v); stage = true; }
            else if (tag == "quiet") { p.quiet = v == "-" ? -2 : stage_of(v); quiet = true; }
            else if (tag == "rng") { p.rng = std::stoull(v); rng = true; }
            else if (tag == "fired") { p.fired = std::stoull(v); fired = true; }
            else if (tag == "count") {
                int n;
                if (!(ls >> n) || n < 0)
                    throw std::invalid_argument("snapshot: bad count line '" + line + "'");
                p.counts[v] = n;
            } else {
                throw std::invalid_argument("snapshot: unknown record '" + tag + "'");
            }
        }
        if (!(stage && quiet && rng && fired))
            throw std::invalid_argument("snapshot: stage, quiet, rng and fired are required");
        return p;
    }

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
        for (const auto& [a, n] : e.consume) sync_dense_(a);
        for (const auto& [a, n] : e.produce) sync_dense_(a);
        if (e.post >= 0) stage_ = e.post;
        ++fired_;
    }

    // the dense mirror of counts_ (index = atom id; 0 = absent), kept in
    // step at every change: the indexed weights read it
    void sync_dense_(Atom a) {
        auto it = counts_.find(a);
        const int n = it == counts_.end() ? 0 : it->second;
        if (a >= dense_.size()) {
            if (n == 0) return;
            dense_.resize(static_cast<size_t>(a) + 1, 0);
        }
        dense_[a] = n;
    }
    void set_counts_(std::map<Atom, int> counts) {
        for (const auto& [a, n] : counts_)
            if (a < dense_.size()) dense_[a] = 0;
        counts_ = std::move(counts);
        for (const auto& [a, n] : counts_) sync_dense_(a);
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
    std::vector<TierIndex> tiers_;     // the rarest-atom index (kernel.hpp)
    std::map<Atom, int> counts_;
    std::vector<int> dense_;           // counts_ by atom id
    int stage_ = 0;
    int quiet_stage_ = -2;             // -2: never latched
    size_t fired_ = 0;
};

}  // namespace metis
