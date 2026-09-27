// Self-checking smoke for the PRODUCT IR runtime (ir.hpp IrArtifact/
// IrEval — TODO "C++ runtime / framework" item 2). Python
// FactoredProgram is semantic truth (gen_ir_artifact.py).
//
// Proves the load-once, evidence-per-tick story: ONE artifact
// (declared U slots, shipped O/Y schedules, F mapping, no
// expectations) served across every scene assignment —
//   - marginal(q | slot evidence) along the shipped O order;
//   - likelihood(observation | evidence) along Y with F clamps (the
//     runtime surprise op: 0 = unmodeled);
//   - the slot-candidate decision (per-candidate evidence = the
//     intervention mechanism, decision-over-IR's substrate);
//   - CPT rows resolved through the app Registry at build time
//     (rebuild() available when the bound world changes).
//
// With a serve-path argument it also drives the IrEvaluator (the
// IR-mode framework loop, evaluator.hpp): B-manifest validation,
// blackboard input/output ports, the plan cycle over candidates-as-
// evidence — the decision must match the python clamp_domain truth.
//
// usage: ir_eval_smoke <ir_rover_artifact.txt> <ir_rover_expect.txt>
//                      [<serve-path>]
#include <cmath>
#include <cstdio>
#include <fstream>
#include <map>
#include <sstream>
#include <string>

#include "metis/evaluator.hpp"
#include "metis/ir.hpp"

static int fails = 0;
#define CHECK(cond)                                                   \
    do {                                                              \
        if (!(cond)) {                                                \
            std::printf("FAIL %s:%d %s\n", __FILE__, __LINE__,        \
                        #cond);                                       \
            ++fails;                                                  \
        }                                                             \
    } while (0)

static bool near9(double a, double b) {
    return std::fabs(a - b) <= 1e-9;
}

int main(int argc, char** argv) {
    using namespace metis;
    if (argc < 3) {
        std::fprintf(stderr,
                     "usage: ir_eval_smoke <artifact> <expect>\n");
        return 2;
    }
    std::ifstream in(argv[1]);
    IrArtifact art = load_ir_artifact(in);
    CHECK(art.ok);
    CHECK(art.unknowns.size() == 2);
    CHECK(art.queries.count("reach(c2)") == 1);
    CHECK(art.finals.count("reach(c2)") == 1);

    // the app bindings — MUST mirror gen_ir_artifact.REGISTRY
    Registry reg;
    reg.weight("move", [](const std::vector<std::string>& args,
                          const CountsView&) {
        return args[0] == "c2" ? 3.0 : 1.0;
    });
    reg.weight("stay", 1.0);
    IrEval ev(art, reg);

    const std::string q = "reach(c2)";
    std::map<std::pair<int, int>, double> marg;   // for the decision
    std::ifstream exp(argv[2]);
    std::string line;
    while (std::getline(exp, line)) {
        std::istringstream ls(line);
        std::string tag;
        ls >> tag;
        if (tag == "EM") {
            int a0, a1;
            double want;
            ls >> a0 >> a1 >> want;
            std::map<std::string, int> ev_map = {{"at(c0)", a0},
                                                 {"at(c1)", a1}};
            double got = ev.marginal(q, ev_map);
            marg[{a0, a1}] = got;
            CHECK(near9(got, want));
        } else if (tag == "EL") {
            int a0, a1, obs;
            double want;
            ls >> a0 >> a1 >> obs >> want;
            std::map<std::string, int> ev_map = {{"at(c0)", a0},
                                                 {"at(c1)", a1}};
            double got = ev.likelihood({{q, obs}}, ev_map);
            CHECK(near9(got, want));
        } else if (tag == "EX") {
            std::string want;
            ls >> want;
            // candidates as slot assignments — per-candidate
            // evidence IS the intervention (argmax P(reach c2))
            double p_near = marg.count({0, 1}) ? marg[{0, 1}] : -1;
            double p_far = marg.count({1, 0}) ? marg[{1, 0}] : -1;
            std::string got = p_near >= p_far ? "near" : "far";
            CHECK(got == want);
        }
    }
    // default evidence (no assignment) must equal the (1,1) world —
    // the U defaults clamp every slot, mirroring _calibration
    CHECK(near9(ev.marginal(q), marg[{1, 1}]));
    // the surprise verdict: an impossible observation has mass 0
    CHECK(ev.likelihood({{q, 1}}, {{"at(c0)", 0}, {"at(c1)", 0}}) ==
          0.0);

    // ---- the IR-mode framework loop (IrEvaluator) ----------------
    if (argc >= 4) {
        const std::string serve = argv[3];
        {
            std::ifstream src(argv[1], std::ios::binary);
            std::ofstream dst(serve,
                              std::ios::binary | std::ios::trunc);
            dst << src.rdbuf();
        }
        Registry frame = reg;        // weights as above
        frame.input("scene", [](const Blackboard& bb) {
            return bb.has("scene");
        });
        frame.output("decision",
                     [](const Decision& d, Blackboard& bb) {
                         bb.set("decision", d.action);
                     });
        const std::map<std::string, std::map<std::string, int>>
            CANDS = {{"near", {{"at(c0)", 0}, {"at(c1)", 1}}},
                     {"far", {{"at(c0)", 1}, {"at(c1)", 0}}}};
        IrDomainSeam seam = [&CANDS, &q](const Blackboard&) {
            IrDomain dom;
            for (const auto& [a, e] : CANDS)
                dom.candidates.push_back(a);
            dom.evidence_for = [&CANDS](const std::string& a) {
                return CANDS.at(a);
            };
            dom.score = [&q](const IrEval& ir,
                             const std::map<std::string, int>& evi) {
                return std::vector<double>{1.0 - ir.marginal(q, evi)};
            };
            dom.doomed = "near";
            return dom;
        };
        // fail-fast: input port unbound -> nothing serves
        {
            Registry noin = reg;
            noin.output("decision",
                        [](const Decision&, Blackboard&) {});
            IrEvaluator bad(serve, noin, seam);
            CHECK(!bad.reload());
            CHECK(bad.error().find("scene") != std::string::npos);
        }
        IrEvaluator irev(serve, frame, seam);
        CHECK(irev.reload());
        Blackboard::Ptr bb = Blackboard::create();
        bb->set("scene", "smoke");
        Decision d = irev.tick(*bb);
        // the expectations file's EX line is the python
        // clamp_domain decision — compare via the recorded marginals
        std::string want =
            marg[{0, 1}] >= marg[{1, 0}] ? "near" : "far";
        CHECK(d.action == want);
        const std::string* out = bb->get<std::string>("decision");
        CHECK(out != nullptr && *out == want);
        CHECK(near9(d.scores.at(0), 1.0 - marg[{0, 1}]) ||
              near9(d.scores.at(0), 1.0 - marg[{1, 0}]));
    }

    std::printf("ir eval smoke: %s (%d failures)\n",
                fails == 0 ? "OK" : "FAILING", fails);
    return fails == 0 ? 0 : 1;
}
