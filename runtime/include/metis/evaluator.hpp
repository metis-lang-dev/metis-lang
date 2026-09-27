// The C++ Evaluator — fw.Evaluator parity, the framework's product
// loop (TODO.md "C++ runtime / framework", item 1):
//
//     Evaluator ev(artifact_path, registry, seam);
//     ev.reload();                 // load / hot-swap (RCU on mtime)
//     Decision d = ev.tick(bb);    // inputs -> plan -> outputs
//
// The artifact is the ground wire kernel/wire.py emits (loader.hpp),
// carrying the B port manifest; loading FAIL-FASTS unless every
// declared port has a registry binding, and any load failure leaves
// the previous artifact serving (the mis-deployed-pack doctrine:
// degrade to the last good catalog, never to no-action).
//
// The DOMAIN SEAM is the catalog_domain contract: candidates are
// labels whose do() edits the initial multiset; project = the metis
// ForwardProjection over the served program with weight ports
// resolved through the registry (overlays included); score =
// lexicographic vector, minimized by plan.hpp with the doomed
// fallback. Inputs/outputs cross the BLACKBOARD through the
// registry's input/output bindings — the measure reads state through
// counts, bindings read the world through the blackboard.
#pragma once

#include <functional>
#include <map>
#include <memory>
#include <string>
#include <sys/stat.h>
#include <vector>

#include <fstream>

#include "metis/blackboard.hpp"
#include "metis/ir.hpp"
#include "metis/kernel.hpp"
#include "metis/loader.hpp"
#include "metis/plan.hpp"
#include "metis/registry.hpp"

namespace metis {

// what the domain seam supplies per tick (catalog_domain parity)
struct CatalogDomain {
    std::vector<std::string> candidates;
    // do(a): the full initial multiset for candidate a (atom -> n)
    std::function<std::map<std::string, int>(const std::string&)>
        init_for;
    // score(projection): lexicographic vector, LOWER is better
    std::function<std::vector<double>(ForwardProjection&)> score;
    std::string doomed;
    int steps = 0;                   // 0 = the artifact's S record
};

using DomainSeam = std::function<CatalogDomain(const Blackboard&)>;

class Evaluator {
  public:
    Evaluator(std::string artifact_path, Registry registry,
              DomainSeam seam)
        : path_(std::move(artifact_path)), reg_(std::move(registry)),
          seam_(std::move(seam)) {}

    // Load (first call) or hot-swap (mtime changed). Returns true
    // when a NEW artifact is serving. On any failure — unreadable,
    // malformed, unbound port — keeps the previous artifact and
    // records error().
    bool reload() {
        struct stat st;
        if (::stat(path_.c_str(), &st) != 0) {
            error_ = "cannot stat " + path_;
            return false;
        }
        int64_t mt = static_cast<int64_t>(st.st_mtim.tv_sec) *
                         1000000000 +
                     st.st_mtim.tv_nsec;
        if (lp_ && mt == mtime_) return false;   // unchanged
        std::ifstream in(path_);
        if (!in) {
            error_ = "cannot open " + path_;
            return false;
        }
        auto fresh = std::make_shared<LoadedProgram>(load_program(in));
        if (!fresh->ok) {
            error_ = "artifact REJECTED: " + fresh->error;
            return false;
        }
        std::string missing = validate(*fresh);
        if (!missing.empty()) {
            error_ = "unbound ports: " + missing;
            return false;
        }
        lp_ = fresh;                 // RCU swap
        mtime_ = mt;
        error_.clear();
        return true;
    }

    bool serving() const { return lp_ != nullptr; }
    const std::string& error() const { return error_; }
    const LoadedProgram& artifact() const { return *lp_; }

    // The decision cycle: require + decode inputs, run the plan loop
    // over the seam's candidates (each an init edit projected through
    // the served program under the registry-resolved policy), write
    // the outputs. Throws std::runtime_error when nothing serves or
    // a required input is missing (fail fast, exactly fw.Evaluator).
    Decision tick(Blackboard& bb) {
        if (!lp_) throw std::runtime_error(
            "no artifact serving" +
            (error_.empty() ? "" : " (" + error_ + ")"));
        std::shared_ptr<LoadedProgram> lp = lp_;   // pin for the tick
        for (const auto& p : lp->ports_in) {
            const InputBinding* b = reg_.find_input(p);
            if (!b || !(*b)(bb))
                throw std::runtime_error("blackboard missing input: " +
                                         p);
        }
        CatalogDomain dom = seam_(bb);
        int steps = dom.steps > 0 ? dom.steps : lp->steps;
        Policy pol;
        bool ported = false;
        for (const auto& r : lp->refs)
            if (!r.factor.empty()) ported = true;
        if (ported) pol = make_weight_policy(lp->refs, reg_, lp->atoms);

        using Proj = std::shared_ptr<ForwardProjection>;
        auto project = [&](const std::string& a) -> Proj {
            Program prog = lp->program;          // shape shared, init per candidate
            std::map<Atom, int> init;
            for (const auto& [atom, n] : dom.init_for(a))
                init[lp->atoms.get(atom)] = n;
            prog.init.assign(init.begin(), init.end());
            return std::make_shared<ForwardProjection>(prog, steps,
                                                       pol);
        };
        auto score = [&](const Proj& pr) {
            return dom.score(*pr);
        };
        PlanResult<std::string, Proj> res = plan<std::string, Proj>(
            dom.candidates, project, score, dom.doomed);

        Decision d;
        d.action = res.action;
        d.doomed = res.doomed;
        d.dof = res.dof;
        auto it = res.scores.find(res.action);
        if (it != res.scores.end()) d.scores = it->second;
        for (const auto& p : lp->ports_out) {
            const OutputBinding* b = reg_.find_output(p);
            if (b) (*b)(d, bb);
        }
        return d;
    }

  private:
    std::string validate(const LoadedProgram& lp) const {
        std::string missing;
        auto note = [&missing](const std::string& kind,
                               const std::string& name) {
            if (!missing.empty()) missing += ", ";
            missing += kind + ":" + name;
        };
        for (const auto& p : lp.ports_weight)
            if (!reg_.has_weight(p)) note("weight", p);
        for (const auto& p : lp.ports_guard)
            if (!reg_.has_guard(p)) note("guard", p);
        for (const auto& p : lp.ports_in)
            if (!reg_.has_input(p)) note("input", p);
        for (const auto& p : lp.ports_out)
            if (!reg_.has_output(p)) note("output", p);
        return missing;
    }

    std::string path_;
    Registry reg_;
    DomainSeam seam_;
    std::shared_ptr<LoadedProgram> lp_;
    int64_t mtime_ = -1;
    std::string error_;
};

// ------------------------------------------------------------------
// The IR-mode Evaluator (decision-over-IR): serves an IR product
// artifact (ir.hpp IrArtifact/IrEval) instead of a ground wire. The
// decision cycle is the SAME plan loop, but a candidate is an
// EVIDENCE ASSIGNMENT over the declared U slots (do() as a clamp on
// one compiled structure — python truth: decision.clamp_domain).
// Hot-swap, fail-fast validation and degrade-to-last-good mirror
// Evaluator above.

struct IrDomain {
    std::vector<std::string> candidates;
    // do(a): the evidence assignment (atom -> 0/1) for candidate a
    std::function<std::map<std::string, int>(const std::string&)>
        evidence_for;
    // score over the shared structure at that evidence
    std::function<std::vector<double>(
        const IrEval&, const std::map<std::string, int>&)> score;
    std::string doomed;
};

using IrDomainSeam = std::function<IrDomain(const Blackboard&)>;

class IrEvaluator {
  public:
    IrEvaluator(std::string artifact_path, Registry registry,
                IrDomainSeam seam)
        : path_(std::move(artifact_path)), reg_(std::move(registry)),
          seam_(std::move(seam)) {}

    bool reload() {
        struct stat st;
        if (::stat(path_.c_str(), &st) != 0) {
            error_ = "cannot stat " + path_;
            return false;
        }
        int64_t mt = static_cast<int64_t>(st.st_mtim.tv_sec) *
                         1000000000 +
                     st.st_mtim.tv_nsec;
        if (eval_ && mt == mtime_) return false;
        std::ifstream in(path_);
        if (!in) {
            error_ = "cannot open " + path_;
            return false;
        }
        auto fresh =
            std::make_shared<IrArtifact>(load_ir_artifact(in));
        if (!fresh->ok) {
            error_ = "artifact REJECTED: " + fresh->error;
            return false;
        }
        std::string missing = validate(*fresh);
        if (!missing.empty()) {
            error_ = "unbound ports: " + missing;
            return false;
        }
        std::shared_ptr<IrEval> ev;
        try {
            ev = std::make_shared<IrEval>(*fresh, reg_);
        } catch (const std::exception& e) {
            error_ = std::string("artifact REJECTED: ") + e.what();
            return false;
        }
        art_ = fresh;                // RCU swap, artifact THEN eval
        eval_ = ev;
        mtime_ = mt;
        error_.clear();
        return true;
    }

    // Rebuild site CPTs when the world the bindings read changed.
    void rebuild() {
        if (eval_) eval_->rebuild(reg_);
    }

    bool serving() const { return eval_ != nullptr; }
    const std::string& error() const { return error_; }
    const IrArtifact& artifact() const { return *art_; }
    const IrEval& eval() const { return *eval_; }

    Decision tick(Blackboard& bb) {
        if (!eval_) throw std::runtime_error(
            "no artifact serving" +
            (error_.empty() ? "" : " (" + error_ + ")"));
        std::shared_ptr<IrEval> ev = eval_;   // pin for the tick
        std::shared_ptr<IrArtifact> art = art_;
        for (const auto& p : art->ports_in) {
            const InputBinding* b = reg_.find_input(p);
            if (!b || !(*b)(bb))
                throw std::runtime_error("blackboard missing input: " +
                                         p);
        }
        IrDomain dom = seam_(bb);
        using Evi = std::map<std::string, int>;
        auto project = [&](const std::string& a) -> Evi {
            return dom.evidence_for(a);
        };
        auto score = [&](const Evi& evi) {
            return dom.score(*ev, evi);
        };
        PlanResult<std::string, Evi> res = plan<std::string, Evi>(
            dom.candidates, project, score, dom.doomed);
        Decision d;
        d.action = res.action;
        d.doomed = res.doomed;
        d.dof = res.dof;
        auto it = res.scores.find(res.action);
        if (it != res.scores.end()) d.scores = it->second;
        for (const auto& p : art->ports_out) {
            const OutputBinding* b = reg_.find_output(p);
            if (b) (*b)(d, bb);
        }
        return d;
    }

  private:
    std::string validate(const IrArtifact& art) const {
        std::string missing;
        auto note = [&missing](const std::string& kind,
                               const std::string& name) {
            if (!missing.empty()) missing += ", ";
            missing += kind + ":" + name;
        };
        for (const auto& p : art.ports_weight)
            if (!reg_.has_weight(p)) note("weight", p);
        for (const auto& p : art.ports_guard)
            if (!reg_.has_guard(p)) note("guard", p);
        for (const auto& p : art.ports_in)
            if (!reg_.has_input(p)) note("input", p);
        for (const auto& p : art.ports_out)
            if (!reg_.has_output(p)) note("output", p);
        return missing;
    }

    std::string path_;
    Registry reg_;
    IrDomainSeam seam_;
    std::shared_ptr<IrArtifact> art_;
    std::shared_ptr<IrEval> eval_;
    int64_t mtime_ = -1;
    std::string error_;
};

}  // namespace metis
