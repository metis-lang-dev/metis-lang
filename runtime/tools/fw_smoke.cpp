// SPDX-License-Identifier: Apache-2.0
// Framework smoke — the BT.cpp-parity features, self-checking:
// loader round-trip against analytic values, blackboard scoping and
// remapping, the projection observer, registry substitution.
#include <cmath>
#include <cstdio>

#include "metis/blackboard.hpp"
#include "metis/loader.hpp"
#include "metis/registry.hpp"

static int fails = 0;
#define CHECK(cond)                                                   \
    do {                                                              \
        if (!(cond)) {                                                \
            std::printf("FAIL %s:%d %s\n", __FILE__, __LINE__,        \
                        #cond);                                       \
            ++fails;                                                  \
        }                                                             \
    } while (0)

static bool near(double a, double b) { return std::fabs(a - b) < 1e-9; }

int main() {
    using namespace metis;
    // two-arm coin with a port on arm a: P(x) = f/(f+2)
    const char* WIRE =
        "N 1 0\n"
        "E 0 -1 1 a ; c t 1 ; o x 1 ; w f 0\n"
        "E 0 -1 2 b ; c t 1 ; o y 1\n"
        "I t 1\n"
        "S 1\n";
    LoadedProgram lp = load_program(std::string(WIRE));
    CHECK(lp.ok);
    CHECK(lp.program.events.size() == 2 && lp.steps == 1);

    // blackboard: scoping + remap (child isolated, alias declared)
    auto root = Blackboard::create();
    root->set("speed_limit", 27.8);
    auto sub = root->child({{"vmax", "speed_limit"}});
    sub->set("local", int64_t(7));
    CHECK(near(sub->get_or<double>("vmax", 0.0), 27.8));
    CHECK(!root->has("local"));                 // isolation
    sub->set("vmax", 13.9);                     // writes through alias
    CHECK(near(root->get_or<double>("speed_limit", 0.0), 13.9));

    // bindings read the world through the captured blackboard
    Registry reg;
    reg.weight("f", [sub](const std::vector<std::string>&,
                          const CountsView&) {
        return sub->get_or<double>("vmax", 0.0) > 13.0 ? 1.0 : 0.25;
    });
    Policy pol = make_weight_policy(lp.refs, reg, lp.atoms);
    int slices = 0;
    Observer obs = [&](int, const Dist&) { ++slices; };
    ForwardProjection pr(lp.program, lp.steps, pol, obs);
    CHECK(slices == 1);
    Atom x = lp.atoms.get("x");
    CHECK(near(pr.final_distribution(x)[1], 1.0 / 3.0));

    // substitution rules: a test stub overrides the binding
    Registry subs;
    subs.weight("f", 2.0);
    reg.override_with(subs);
    Policy pol2 = make_weight_policy(lp.refs, reg, lp.atoms);
    ForwardProjection pr2(lp.program, lp.steps, pol2);
    CHECK(near(pr2.final_distribution(x)[1], 0.5));

    std::printf("FW SMOKE %s\n", fails == 0 ? "OK" : "FAILED");
    return fails == 0 ? 0 : 1;
}
