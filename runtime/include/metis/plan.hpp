// The generic decision loop — port of kernel/decision.py::plan.
// Candidates -> do (intervention) -> project (a ForwardProjection or
// anything score can read) -> lexicographic round9-quantized scores,
// earliest-candidate tie-break, doomed fallback. Same semantics as
// the python loop the road corpus gate pinned at 1e-9.
#pragma once

#include <cmath>
#include <functional>
#include <map>
#include <string>
#include <vector>

namespace metis {

inline double round9(double x) {
    // python round(x, 9): ties-to-even on the 9th decimal
    return std::nearbyint(x * 1e9) / 1e9;
}

template <typename A, typename P>
struct PlanResult {
    A action{};
    bool doomed = false;
    int dof = 0;
    std::map<A, std::vector<double>> scores;
    std::map<A, P> projections;
};

template <typename A, typename P>
PlanResult<A, P> plan(
    const std::vector<A>& candidates,
    const std::function<P(const A&)>& project,
    const std::function<std::vector<double>(const P&)>& score,
    const A& doomed_action = A{}) {
    PlanResult<A, P> res;
    if (candidates.empty()) {
        res.action = doomed_action;
        res.doomed = true;
        return res;
    }
    res.dof = static_cast<int>(candidates.size());
    bool first = true;
    for (const A& a : candidates) {
        P pr = project(a);
        std::vector<double> s = score(pr);
        for (double& v : s) v = round9(v);
        if (first || s < res.scores[res.action]) {
            res.action = a;
            first = false;
        }
        res.scores.emplace(a, std::move(s));
        res.projections.emplace(a, std::move(pr));
    }
    return res;
}

}  // namespace metis
