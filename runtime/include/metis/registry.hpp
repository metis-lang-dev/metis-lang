// SPDX-License-Identifier: Apache-2.0
// The C++ weight-port registry — the BT.cpp seam, native side.
//
// A catalog names its factors (`@w cpt(C)`); a DOMAIN registers the
// implementations here (in its node's init, exactly like BT.cpp's
// registerNodeType). make_weight_policy() resolves each port-weighted
// ground event against the registry and returns the filter/sampler
// Policy — fail-fast on unbound factors, complement = 1-f, mirroring
// metis/lang/compiler.py::weight_policy.
//
// Bindings read the CURRENT counts through CountsView (atom strings
// resolved through the interner once, then integer lookups).
#pragma once

#include <functional>
#include <memory>
#include <optional>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <vector>

#include "metis/blackboard.hpp"
#include "metis/kernel.hpp"

namespace metis {

struct CountsView {
    const Counts& counts;
    Interner& atoms;
    int count(const std::string& atom) const {
        auto it = atoms.ids.find(atom);
        if (it == atoms.ids.end()) return 0;
        return count_of(counts, it->second);
    }
    bool has(const std::string& atom) const { return count(atom) > 0; }
};

// (resolved ground args, live counts) -> factor value
using Binding = std::function<double(const std::vector<std::string>&,
                                     const CountsView&)>;

// experience over the base (fw.Registry parity): consulted
// newest-first; nullopt = miss, fall through to the next overlay and
// finally the (total) base binding
using Overlay = std::function<std::optional<double>(
    const std::vector<std::string>&, const CountsView&)>;

// what an output port sees — the decision cycle's result surface
struct Decision {
    std::string action;
    bool doomed = false;
    int dof = 0;
    std::vector<double> scores;      // the chosen action's vector
};

using InputBinding = std::function<bool(const Blackboard&)>;
using OutputBinding = std::function<void(const Decision&,
                                         Blackboard&)>;
using GuardBinding = std::function<bool(
    const std::vector<std::string>&, const CountsView&)>;

struct WeightRef {                  // per ground event, args RESOLVED
    std::string factor;             // empty = no port on this event
    std::vector<std::string> args;
    bool complement = false;
};

class Registry {
  public:
    Registry& weight(const std::string& name, Binding b) {
        weights_[name] = std::move(b);
        return *this;
    }
    Registry& weight(const std::string& name, double constant) {
        weights_[name] = [constant](const auto&, const auto&) {
            return constant;
        };
        return *this;
    }
    // experience over the base — newest overlay consulted first,
    // nullopt falls through (fw.Registry.overlay parity; fitted rows
    // and online posteriors land here, never editing the base)
    Registry& overlay(const std::string& name, Overlay ov) {
        overlays_[name].push_back(std::move(ov));
        return *this;
    }
    Registry& pop_overlay(const std::string& name) {
        auto it = overlays_.find(name);
        if (it != overlays_.end() && !it->second.empty())
            it->second.pop_back();
        return *this;
    }
    Registry& input(const std::string& name, InputBinding b) {
        inputs_[name] = std::move(b);
        return *this;
    }
    Registry& output(const std::string& name, OutputBinding b) {
        outputs_[name] = std::move(b);
        return *this;
    }
    Registry& guard(const std::string& name, GuardBinding b) {
        guards_[name] = std::move(b);
        return *this;
    }

    const Binding* find(const std::string& name) const {
        auto it = weights_.find(name);
        return it == weights_.end() ? nullptr : &it->second;
    }
    bool has_weight(const std::string& n) const {
        return weights_.count(n) != 0;
    }
    bool has_input(const std::string& n) const {
        return inputs_.count(n) != 0;
    }
    bool has_output(const std::string& n) const {
        return outputs_.count(n) != 0;
    }
    bool has_guard(const std::string& n) const {
        return guards_.count(n) != 0;
    }
    const InputBinding* find_input(const std::string& n) const {
        auto it = inputs_.find(n);
        return it == inputs_.end() ? nullptr : &it->second;
    }
    const OutputBinding* find_output(const std::string& n) const {
        auto it = outputs_.find(n);
        return it == outputs_.end() ? nullptr : &it->second;
    }
    const GuardBinding* find_guard(const std::string& n) const {
        auto it = guards_.find(n);
        return it == guards_.end() ? nullptr : &it->second;
    }

    // the resolved factor (overlay chain newest-first, base as the
    // total fallback) — a VALUE closure safe to outlive the call
    Binding resolved(const std::string& name) const {
        auto it = weights_.find(name);
        if (it == weights_.end())
            throw std::runtime_error("unbound weight port '" + name +
                                     "'");
        Binding base = it->second;
        auto ov = overlays_.find(name);
        if (ov == overlays_.end() || ov->second.empty()) return base;
        std::vector<Overlay> chain = ov->second;
        return [chain, base](const std::vector<std::string>& args,
                             const CountsView& view) {
            for (auto o = chain.rbegin(); o != chain.rend(); ++o) {
                std::optional<double> v = (*o)(args, view);
                if (v) return *v;
            }
            return base(args, view);
        };
    }

    // BT.cpp's substitution rules: overlay every binding from `subs`
    // (tests inject stubs; learned overlays land the same way —
    // experience over base, never editing the base registration).
    Registry& override_with(const Registry& subs) {
        for (const auto& [name, b] : subs.weights_)
            weights_[name] = b;
        for (const auto& [name, b] : subs.inputs_)
            inputs_[name] = b;
        for (const auto& [name, b] : subs.outputs_)
            outputs_[name] = b;
        for (const auto& [name, b] : subs.guards_)
            guards_[name] = b;
        return *this;
    }

  private:
    std::unordered_map<std::string, Binding> weights_;
    std::unordered_map<std::string, std::vector<Overlay>> overlays_;
    std::unordered_map<std::string, InputBinding> inputs_;
    std::unordered_map<std::string, OutputBinding> outputs_;
    std::unordered_map<std::string, GuardBinding> guards_;
};

// refs[i] pairs with program.events[i] (empty factor = static weight).
inline Policy make_weight_policy(const std::vector<WeightRef>& refs,
                                 const Registry& reg,
                                 Interner& atoms) {
    struct Hook {
        Binding fn;                  // resolved: overlays + base
        std::vector<std::string> args;
        bool complement;
    };
    auto hooks = std::make_shared<
        std::unordered_map<int, Hook>>();
    for (size_t i = 0; i < refs.size(); ++i) {
        if (refs[i].factor.empty()) continue;
        (*hooks)[static_cast<int>(i)] =
            Hook{reg.resolved(refs[i].factor), refs[i].args,
                 refs[i].complement};
    }
    return [hooks, &atoms](int, const Counts& counts,
                           std::vector<std::pair<int, double>>& ws) {
        CountsView view{counts, atoms};
        std::vector<std::pair<int, double>> out;
        out.reserve(ws.size());
        for (auto& [i, w] : ws) {
            auto it = hooks->find(i);
            if (it == hooks->end()) {
                out.emplace_back(i, w);
                continue;
            }
            double f = it->second.fn(it->second.args, view);
            if (it->second.complement) f = 1.0 - f;
            if (f > 0) out.emplace_back(i, w * f);
        }
        ws = std::move(out);
    };
}

}  // namespace metis
