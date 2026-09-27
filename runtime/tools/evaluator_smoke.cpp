// Self-checking smoke for the C++ Evaluator (evaluator.hpp — the
// fw.Evaluator parity surface). Python is semantic truth
// (gen_fw_artifact.py): the rover artifacts v1/v2 with expectations.
//
// Proves, in one binary:
//   - product artifact load with B port manifest; FAIL-FAST on an
//     unbound port (and the failure leaves nothing serving);
//   - the decision cycle: blackboard inputs required, candidates as
//     init edits, weight ports resolved through the registry WITH an
//     overlay chain, lexicographic plan, output port writes back;
//   - HOT-SWAP: overwriting the artifact with v2 (one added rule,
//     recompiled by metisc) and reload() flips the decision — same
//     binary, same bindings;
//   - degrade-to-last-good: a corrupt artifact is rejected and v2
//     keeps serving.
//
// usage: evaluator_smoke <fw_rover_v1.txt> <fw_rover_v2.txt>
//                        <fw_rover_expect.txt> <serve-path>
#include <cmath>
#include <cstdio>
#include <fstream>
#include <map>
#include <sstream>
#include <string>
#include <vector>

#include "metis/evaluator.hpp"

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

struct Expect {
    std::string action;
    bool doomed = false;
    int dof = 0;
    std::vector<double> scores;
    std::map<std::string, double> p_goal;
};

static std::map<int, Expect> load_expect(const std::string& path) {
    std::map<int, Expect> out;
    std::ifstream in(path);
    std::string line;
    while (std::getline(in, line)) {
        std::istringstream ls(line);
        std::string tag;
        ls >> tag;
        if (tag == "X") {
            int v, doomed, dof, n;
            ls >> v;
            Expect& e = out[v];
            ls >> e.action >> doomed >> dof >> n;
            e.doomed = doomed != 0;
            e.dof = dof;
            e.scores.resize(n);
            for (double& s : e.scores) ls >> s;
        } else if (tag == "P") {
            int v;
            std::string a;
            double p;
            ls >> v >> a >> p;
            out[v].p_goal[a] = p;
        }
    }
    return out;
}

static void copy_file(const std::string& from,
                      const std::string& to) {
    std::ifstream in(from, std::ios::binary);
    std::ofstream out(to, std::ios::binary | std::ios::trunc);
    out << in.rdbuf();
}

int main(int argc, char** argv) {
    using namespace metis;
    if (argc < 5) {
        std::fprintf(stderr,
                     "usage: evaluator_smoke <v1> <v2> <expect> "
                     "<serve-path>\n");
        return 2;
    }
    const std::string v1 = argv[1], v2 = argv[2], expf = argv[3],
                      serve = argv[4];
    auto expect = load_expect(expf);

    // the app's bindings — MUST mirror gen_fw_artifact.registry()
    auto make_registry = [](bool with_stay) {
        Registry reg;
        reg.weight("move", 1.0);
        reg.overlay("move",
                    [](const std::vector<std::string>& args,
                       const CountsView&) -> std::optional<double> {
                        if (args[0] == "c2") return 3.0;
                        return std::nullopt;
                    });
        if (with_stay) reg.weight("stay", 1.0);
        reg.input("scene", [](const Blackboard& bb) {
            return bb.has("scene");
        });
        reg.output("decision",
                   [](const Decision& d, Blackboard& bb) {
                       bb.set("decision", d.action);
                   });
        return reg;
    };

    const std::map<std::string, std::map<std::string, int>> CANDS = {
        {"near", {{"at(c1)", 1}, {"tick", 1}}},
        {"far", {{"at(c0)", 1}, {"tick", 1}}}};

    // The seam: candidates as init edits; score = 1 - P(at(c2)),
    // the query atom resolved through the SERVING artifact's
    // interner (bound after construction via the pointer).
    Evaluator* serving_ev = nullptr;
    DomainSeam seam = [&CANDS, &serving_ev](const Blackboard&) {
        CatalogDomain dom;
        for (const auto& [a, init] : CANDS)
            dom.candidates.push_back(a);   // sorted: map order
        dom.init_for = [&CANDS](const std::string& a) {
            return CANDS.at(a);
        };
        dom.score = [&serving_ev](ForwardProjection& pr) {
            auto& ids = serving_ev->artifact().atoms.ids;
            auto it = ids.find("at(c2)");
            std::vector<double> d =
                it == ids.end()
                    ? std::vector<double>{1.0}
                    : pr.final_distribution(it->second);
            double p1 = d.size() > 1 ? d[1] : 0.0;
            return std::vector<double>{1.0 - p1};
        };
        dom.doomed = "near";
        return dom;
    };

    // FAIL-FAST: registry missing `stay` -> reload refuses, nothing
    // serves, error names the port.
    copy_file(v1, serve);
    {
        Evaluator ev(serve, make_registry(false), seam);
        CHECK(!ev.reload());
        CHECK(!ev.serving());
        CHECK(ev.error().find("stay") != std::string::npos);
    }

    // The full cycle against v1, then hot-swap to v2.
    Evaluator ev2(serve, make_registry(true), seam);
    serving_ev = &ev2;
    CHECK(ev2.reload());
    CHECK(ev2.serving());

    Blackboard::Ptr bb = Blackboard::create();
    // missing input fails fast
    bool threw = false;
    try {
        ev2.tick(*bb);
    } catch (const std::exception&) {
        threw = true;
    }
    CHECK(threw);

    bb->set("scene", "smoke");
    for (int version : {1, 2}) {
        if (version == 2) {
            copy_file(v2, serve);          // metisc recompile lands
            CHECK(ev2.reload());           // hot-swap picks it up
        }
        const Expect& e = expect.at(version);
        Decision d = ev2.tick(*bb);
        CHECK(d.action == e.action);
        CHECK(d.doomed == e.doomed);
        CHECK(d.dof == e.dof);
        CHECK(d.scores.size() == e.scores.size());
        for (size_t i = 0;
             i < d.scores.size() && i < e.scores.size(); ++i)
            CHECK(near9(d.scores[i], e.scores[i]));
        const std::string* out =
            bb->get<std::string>("decision");
        CHECK(out != nullptr && *out == e.action);
    }

    // degrade to last good: corrupt artifact rejected, v2 serving
    {
        std::ofstream bad(serve, std::ios::trunc);
        bad << "E garbage before any N record\n";
    }
    CHECK(!ev2.reload());
    CHECK(ev2.serving());
    Decision d = ev2.tick(*bb);
    CHECK(d.action == expect.at(2).action);

    std::printf("evaluator smoke: %s (%d failures)\n",
                fails == 0 ? "OK" : "FAILING", fails);
    return fails == 0 ? 0 : 1;
}
