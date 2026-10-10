// SPDX-License-Identifier: Apache-2.0
// The IR interpreter — the item-3 decision (docs/ir-plan.md): C++
// consumes the COMPILED artifact (factor-graph structure + AOT
// elimination schedules, serialized by metis/kernel/ir.py) and
// evaluates it with table ops alone. No grounding, no typechecking,
// no min-fill lives here: admission and analysis happened at compile
// time on the authoring side; this file is the small deterministic
// runtime the vehicle actually runs. CPT rows are filled by calling
// the REGISTRY bindings on synthesized snapshots — bindings stay
// runtime C++ because they read the live world.
#pragma once

#include <cmath>
#include <fstream>
#include <map>
#include <sstream>
#include <string>
#include <vector>

#include "metis/golden.hpp"
#include "metis/registry.hpp"

namespace metis {

// Dense table over named variables; row-major, last var fastest —
// the numpy layout, though only scalars ever cross the language line.
struct Table {
    std::vector<std::string> vars;
    std::vector<int> dims;
    std::vector<double> data;

    size_t size() const {
        size_t n = 1;
        for (int d : dims) n *= d;
        return n;
    }
    int pos(const std::string& v) const {
        for (size_t i = 0; i < vars.size(); ++i)
            if (vars[i] == v) return static_cast<int>(i);
        return -1;
    }
};

inline Table multiply(const Table& A, const Table& B) {
    Table out;
    out.vars = A.vars;
    out.dims = A.dims;
    for (size_t i = 0; i < B.vars.size(); ++i)
        if (A.pos(B.vars[i]) < 0) {
            out.vars.push_back(B.vars[i]);
            out.dims.push_back(B.dims[i]);
        }
    size_t n = out.size();
    out.data.assign(n, 0.0);
    // per-out-var strides into A and B (0 when absent)
    auto strides = [&](const Table& t) {
        std::vector<size_t> s(out.vars.size(), 0);
        std::vector<size_t> own(t.vars.size(), 1);
        for (int i = static_cast<int>(t.vars.size()) - 2; i >= 0; --i)
            own[i] = own[i + 1] * t.dims[i + 1];
        for (size_t k = 0; k < out.vars.size(); ++k) {
            int p = t.pos(out.vars[k]);
            if (p >= 0) s[k] = own[p];
        }
        return s;
    };
    std::vector<size_t> sa = strides(A), sb = strides(B);
    std::vector<int> idx(out.vars.size(), 0);
    for (size_t f = 0; f < n; ++f) {
        size_t ia = 0, ib = 0;
        for (size_t k = 0; k < idx.size(); ++k) {
            ia += sa[k] * idx[k];
            ib += sb[k] * idx[k];
        }
        out.data[f] = A.data[ia] * B.data[ib];
        for (int k = static_cast<int>(idx.size()) - 1; k >= 0; --k) {
            if (++idx[k] < out.dims[k]) break;
            idx[k] = 0;
        }
    }
    return out;
}

inline Table sum_out(const Table& t, const std::string& v) {
    int p = t.pos(v);
    if (p < 0) return t;
    Table out;
    for (size_t i = 0; i < t.vars.size(); ++i)
        if (static_cast<int>(i) != p) {
            out.vars.push_back(t.vars[i]);
            out.dims.push_back(t.dims[i]);
        }
    out.data.assign(out.size(), 0.0);
    std::vector<int> idx(t.vars.size(), 0);
    for (size_t f = 0; f < t.data.size(); ++f) {
        size_t of = 0;
        for (size_t k = 0, ok = 0; k < idx.size(); ++k) {
            if (static_cast<int>(k) == p) continue;
            of = of * t.dims[k] + idx[k];
            (void)ok;
        }
        out.data[of] += t.data[f];
        for (int k = static_cast<int>(idx.size()) - 1; k >= 0; --k) {
            if (++idx[k] < t.dims[k]) break;
            idx[k] = 0;
        }
    }
    return out;
}

// Eliminate EVERYTHING along the shipped schedule; the product of
// the remaining scalars is the total mass — with evidence clamps
// added, that is the likelihood, and 0 is the UNMODELED verdict
// (the runtime surprise op: no parameter can create missing
// support, so Z == 0 is a structural signal, not a small number).
inline double ir_mass(std::vector<Table> fs,
                      const std::vector<std::string>& order) {
    for (const auto& v : order) {
        std::vector<Table> rest;
        Table prod;
        bool got = false;
        for (auto& f : fs) {
            if (f.pos(v) >= 0) {
                prod = got ? multiply(prod, f) : f;
                got = true;
            } else {
                rest.push_back(std::move(f));
            }
        }
        if (got) rest.push_back(sum_out(prod, v));
        fs = std::move(rest);
    }
    double z = 1.0;
    for (const auto& f : fs) {
        double s = 0.0;
        for (double x : f.data) s += x;
        z *= s;
    }
    return z;
}

// Eliminate along the SHIPPED schedule, then read P(q = 1).
inline double ir_query(std::vector<Table> fs,
                       const std::vector<std::string>& order,
                       const std::string& q) {
    for (const auto& v : order) {
        std::vector<Table> rest;
        Table prod;
        bool got = false;
        for (auto& f : fs) {
            if (f.pos(v) >= 0) {
                prod = got ? multiply(prod, f) : f;
                got = true;
            } else {
                rest.push_back(std::move(f));
            }
        }
        if (got) rest.push_back(sum_out(prod, v));
        fs = std::move(rest);
    }
    Table p = fs.at(0);
    for (size_t i = 1; i < fs.size(); ++i) p = multiply(p, fs[i]);
    double z = 0, on = 0;
    int qp = p.pos(q);
    size_t stride = 1;
    for (size_t k = qp + 1; k < p.dims.size(); ++k)
        stride *= p.dims[k];
    for (size_t f = 0; f < p.data.size(); ++f) {
        z += p.data[f];
        if ((f / stride) % p.dims[qp] == 1) on += p.data[f];
    }
    return on / z;
}

// The IR corpus registry: the port-weighted test bindings plus the
// fixtures' factors. cpt covers both the a/b pair and the generated
// c<i> ring (n = 6 in the corpus — see gen_ir_goldens.py).
inline Registry ir_test_registry() {
    Registry reg = test_registry();
    reg.weight("cpt", [](const std::vector<std::string>& args,
                         const CountsView& v) {
        const std::string& c = args[0];
        if (v.has("rb(" + c + ")")) return 1.0;
        std::vector<std::string> ins;
        if (c == "a") ins = {"b"};
        else if (c == "b") ins = {"a"};
        else {
            int i = std::stoi(c.substr(1)), n = 6;
            ins = {"c" + std::to_string((i + n - 1) % n),
                   "c" + std::to_string((i + 1) % n)};
        }
        int r = 0;
        for (const auto& y : ins)
            if (v.has("prev(" + y + ")")) ++r;
        return 0.45 + 0.5 * (1 + r) / (1.0 + ins.size());
    });
    reg.weight("pa", 0.6);
    reg.weight("pb", [](const std::vector<std::string>&,
                        const CountsView& v) {
        return v.has("a") ? 0.9 : 0.2;
    });
    reg.weight("w1", 0.5);
    reg.weight("w2", 0.3);
    reg.weight("ph", 0.7);       // the packmark base coin
    reg.weight("die", 0.1);      // nav4: uniform death
    // "go" is used by BOTH nav4 (uniform survival) and xtraffic1
    // (base policy) — corpus registries merge here, so dispatch on
    // the cell-name shape (nav "cXY" vs xtraffic "xi_yj"); real
    // deployments carry per-artifact registries, no collision
    // road-close (semantic handles, close_scene): brk/cls are scene
    // constants; rss reads {gclose, on(ego,L), on(alfa,L)} — active
    // value computed once by the python compiler for this scene
    reg.weight("brk", 0.20000000000000001);
    reg.weight("cls", 0.20000000000000001);
    reg.weight("rss", [](const std::vector<std::string>&,
                         const CountsView& v) {
        if (!v.has("gclose")) return 0.0;
        for (const char* ln : {"l1", "l2", "l3"})
            if (v.has(std::string("on(ego,") + ln + ")") &&
                v.has(std::string("on(alfa,") + ln + ")"))
                return 0.85671641791044773;
        return 0.0;
    });
    // xtraffic instance 1 (3x3 grid, cells "xi_yj", goal x3_y3;
    // ocells x1_y2 -> x3_y2 west-to-east, arrival rate 0.3)
    reg.weight("obs", [](const std::vector<std::string>& args,
                         const CountsView& v) {
        const std::string& c = args[0];
        if (c == "x3_y2") return 0.3;               // east edge
        std::string east = (c == "x1_y2") ? "x2_y2" : "x3_y2";
        return v.has("po(" + east + ")") ? 1.0 : 0.0;
    });
    reg.weight("fgo", [](const std::vector<std::string>& args,
                         const CountsView& v) {
        return v.has("o(" + args[0] + ")") ? 0.0 : 1.0;
    });
    reg.weight("fstayw", [](const std::vector<std::string>& args,
                            const CountsView& v) {
        return v.has("o(" + args[0] + ")") ? 0.0 : 1.0;
    });
    // base policy: uniform over goal-ward neighbors (empty policy
    // table), zero under a cmd token / an obstacle / at the goal
    auto xt_dist = [](const std::string& c) {
        return std::abs(c[1] - '3') + std::abs(c[4] - '3');
    };
    auto xt_wards = [xt_dist](const std::string& c) {
        int i = c[1] - '0', j = c[4] - '0', d0 = xt_dist(c), n = 0;
        const int di[] = {1, -1, 0, 0}, dj[] = {0, 0, 1, -1};
        for (int k = 0; k < 4; ++k) {
            int i2 = i + di[k], j2 = j + dj[k];
            if (i2 < 1 || i2 > 3 || j2 < 1 || j2 > 3) continue;
            std::string c2 = "x" + std::to_string(i2) + "_y"
                + std::to_string(j2);
            if (xt_dist(c2) < d0) ++n;
        }
        return n;
    };
    auto xt_cmd = [](const CountsView& v) {
        for (const char* d : {"cmdnorth", "cmdsouth", "cmdeast",
                              "cmdwest"})
            if (v.has(d)) return true;
        return false;
    };
    reg.weight("go", [xt_dist, xt_wards, xt_cmd](
                   const std::vector<std::string>& args,
                   const CountsView& v) {
        const std::string &c = args[0], &c2 = args[1];
        if (c[0] == 'c') return 0.9;         // nav4: uniform survival
        if (xt_cmd(v) || v.has("o(" + c + ")") || c == "x3_y3")
            return 0.0;
        int n = xt_wards(c);
        if (n == 0 || xt_dist(c2) >= xt_dist(c)) return 0.0;
        return 1.0 / n;
    });
    reg.weight("stayw", [xt_wards, xt_cmd](
                   const std::vector<std::string>& args,
                   const CountsView& v) {
        const std::string& c = args[0];
        if (xt_cmd(v) || v.has("o(" + c + ")") || c == "x3_y3")
            return 0.0;
        return xt_wards(c) == 0 ? 1.0 : 0.0;
    });
    // gol4: 2x2 all-adjacent Game of Life (cells g00..g11, every
    // other cell a neighbor), uniform noise 0.1
    reg.weight("life", [](const std::vector<std::string>& args,
                          const CountsView& v) {
        const std::string& c = args[0];
        bool cond;
        if (v.has("force(" + c + ")")) cond = true;
        else {
            int live = 0;
            for (const char* u : {"g00", "g01", "g10", "g11"})
                if (u != c && v.has(std::string("pa(") + u + ")"))
                    ++live;
            bool was_on = v.has("pa(" + c + ")");
            cond = was_on ? (live >= 2 && live <= 3) : (live == 3);
        }
        return cond ? 0.9 : 0.1;
    });
    return reg;
}

inline GoldenResult run_ir_goldens(const std::string& path) {
    GoldenResult res;
    std::ifstream in(path);
    if (!in) {
        res.first_fail = "cannot open " + path;
        return res;
    }
    Registry reg = ir_test_registry();
    Interner atoms;

    std::map<std::string, int> cards;
    std::vector<Table> tables;
    std::vector<std::string> order;
    int pending_cands = 0;
    Table site;                        // being filled by K lines
    std::vector<std::vector<double>> site_rows;
    struct Cand {
        double w;
        std::vector<int> depbits;      // parent indices that must be 1
        const Binding* fn = nullptr;
        std::vector<std::string> args;
        std::vector<std::string> base;
        std::vector<std::pair<std::string, int>> vats;  // atom, p-idx
        bool compl_ = false;
    };
    std::vector<Cand> cands;

    auto check = [&](bool good, const std::string& what) {
        ++res.total;
        if (good) ++res.ok;
        else if (res.first_fail.empty())
            res.first_fail = "ircase " + std::to_string(res.cases) +
                             ": " + what;
    };
    auto finish_site = [&]() {
        if (pending_cands != 0 || cands.empty()) return;
        int np = static_cast<int>(site.vars.size()) - 1;
        int card = site.dims.back();
        site.data.assign(site.size(), 0.0);
        std::vector<int> bits(np, 0);
        size_t rows = 1;
        for (int k = 0; k < np; ++k) rows *= 2;
        for (size_t row = 0; row < rows; ++row) {
            std::vector<double> w(card, 0.0);
            double tot = 0;
            for (int j = 0; j < card; ++j) {
                const Cand& c = cands[j];
                bool en = true;
                for (int d : c.depbits) en = en && bits[d] == 1;
                if (!en) continue;
                double wt = c.w;
                if (c.fn) {
                    Counts counts;
                    std::map<Atom, int> m;
                    for (const auto& a : c.base) m[atoms.get(a)] = 1;
                    for (const auto& [a, p] : c.vats)
                        if (bits[p] == 1) m[atoms.get(a)] = 1;
                    counts.assign(m.begin(), m.end());
                    CountsView view{counts, atoms};
                    double f = (*c.fn)(c.args, view);
                    if (c.compl_) f = 1.0 - f;
                    wt *= f;
                }
                if (wt > 0) w[j] = wt;
                tot += w[j];
            }
            size_t base_idx = row * card;
            if (tot > 0)
                for (int j = 0; j < card; ++j)
                    site.data[base_idx + j] = w[j] / tot;
            for (int k = np - 1; k >= 0; --k) {
                if (++bits[k] < 2) break;
                bits[k] = 0;
            }
        }
        tables.push_back(site);
        cands.clear();
    };

    std::string line;
    while (std::getline(in, line)) {
        if (line.empty() || line[0] == '#') continue;
        std::istringstream ls(line);
        std::string tag;
        ls >> tag;
        if (tag == "C") {
            cards.clear();
            tables.clear();
            order.clear();
            cands.clear();
            pending_cands = 0;
        } else if (tag == "V") {
            std::string v;
            int c;
            ls >> v >> c;
            cards[v] = c;
        } else if (tag == "S") {
            std::string x;
            int np;
            ls >> x >> np;
            site = Table{};
            for (int i = 0; i < np; ++i) {
                std::string p;
                ls >> p;
                site.vars.push_back(p);
                site.dims.push_back(2);
            }
            ls >> pending_cands;
            site.vars.push_back(x);
            site.dims.push_back(pending_cands);
            cands.clear();
        } else if (tag == "K") {
            Cand c;
            int nd, hook;
            ls >> c.w >> nd;
            for (int i = 0; i < nd; ++i) {
                std::string d;
                ls >> d;
                c.depbits.push_back(site.pos(d));
            }
            ls >> hook;
            if (hook) {
                std::string factor;
                int compl_, na, nb, nv;
                ls >> factor >> compl_ >> na;
                c.compl_ = compl_ != 0;
                for (int i = 0; i < na; ++i) {
                    std::string a;
                    ls >> a;
                    c.args.push_back(a);
                }
                ls >> nb;
                for (int i = 0; i < nb; ++i) {
                    std::string a;
                    ls >> a;
                    c.base.push_back(a);
                }
                ls >> nv;
                for (int i = 0; i < nv; ++i) {
                    std::string a, pv;
                    ls >> a >> pv;
                    c.vats.emplace_back(a, site.pos(pv));
                }
                c.fn = reg.find(factor);
                if (!c.fn) {
                    check(false, "unbound factor " + factor);
                    c.fn = nullptr;
                }
            }
            cands.push_back(std::move(c));
            if (--pending_cands == 0) finish_site();
        } else if (tag == "W") {
            std::string x, nv, ov;
            int card;
            ls >> x >> card >> nv >> ov;
            Table t;
            t.vars = {x};
            t.dims = {card};
            bool has_old = ov != "-";
            if (has_old) {
                t.vars.push_back(ov);
                t.dims.push_back(2);
            }
            t.vars.push_back(nv);
            t.dims.push_back(2);
            t.data.assign(t.size(), 0.0);
            for (int j = 0; j < card; ++j) {
                std::string val;
                ls >> val;
                if (!has_old) {
                    t.data[j * 2 + (val == "1" ? 1 : 0)] = 1.0;
                } else if (val == "-") {
                    t.data[(j * 2 + 0) * 2 + 0] = 1.0;
                    t.data[(j * 2 + 1) * 2 + 1] = 1.0;
                } else {
                    int v = val == "1" ? 1 : 0;
                    t.data[(j * 2 + 0) * 2 + v] = 1.0;
                    t.data[(j * 2 + 1) * 2 + v] = 1.0;
                }
            }
            tables.push_back(std::move(t));
        } else if (tag == "G") {
            std::string x, ov;
            int card, n;
            ls >> x >> card >> ov >> n;
            Table t;
            t.vars = {x, ov};
            t.dims = {card, 2};
            t.data.assign(t.size(), 1.0);
            for (int i = 0; i < n; ++i) {
                int j;
                ls >> j;
                t.data[j * 2 + 1] = 0.0;
            }
            tables.push_back(std::move(t));
        } else if (tag == "P") {
            std::string v;
            int val;
            ls >> v >> val;
            Table t;
            t.vars = {v};
            t.dims = {2};
            t.data = {val ? 0.0 : 1.0, val ? 1.0 : 0.0};
            tables.push_back(std::move(t));
        } else if (tag == "O" || tag == "Y") {
            std::string q;
            int n;
            if (tag == "O") ls >> q;
            ls >> n;
            order.clear();
            for (int i = 0; i < n; ++i) {
                std::string v;
                ls >> v;
                order.push_back(v);
            }
        } else if (tag == "Z") {
            int n;
            ls >> n;
            std::vector<Table> fs = tables;
            for (int i = 0; i < n; ++i) {
                std::string v;
                int val;
                ls >> v >> val;
                Table t;
                t.vars = {v};
                t.dims = {2};
                t.data = {val ? 0.0 : 1.0, val ? 1.0 : 0.0};
                fs.push_back(std::move(t));
            }
            double want;
            ls >> want;
            double got = ir_mass(std::move(fs), order);
            check(std::fabs(got - want) <= 1e-9, "Z");
        } else if (tag == "M") {
            std::string atom, q;
            double want;
            ls >> atom >> q >> want;
            double got = ir_query(tables, order, q);
            check(std::fabs(got - want) <= 1e-9, "M " + atom);
        } else if (tag == ".") {
            ++res.cases;
        }
    }
    return res;
}

// ------------------------------------------------------------------
// The PRODUCT IR runtime (TODO "C++ runtime / framework" item 2):
// load ONE compiled artifact (kernel/ir.py ir_artifact_lines — no
// expectations, certification happened on the authoring side), then
// serve every tick: evidence = an assignment over the declared U
// slots, marginals along the shipped O schedules, observation
// likelihood (the surprise op) along Y against the F mapping.
// Schedules stay exact under arbitrary slot clamps — every unknown
// is a singleton scope in the elimination graph already, so a point
// factor adds no edge (the authoring side proves this; here we just
// append point tables, exactly the Z path generalized).
//
// The record parsing mirrors run_ir_goldens above deliberately —
// that loop is the conformance referee and must not share fate with
// product code.

struct IrCand {
    double w = 1.0;
    std::vector<int> depbits;        // parent positions that must be 1
    bool hook = false;
    std::string factor;
    bool complement = false;
    std::vector<std::string> args, base;
    std::vector<std::pair<std::string, int>> vats;  // atom, parent pos
};

struct IrSite {
    std::vector<std::string> vars;   // parents..., xvar
    std::vector<int> dims;
    std::vector<IrCand> cands;
};

struct IrUnknown {
    std::string atom, var;
    int def = 0;
};

struct IrArtifact {
    std::string name;
    std::map<std::string, int> cards;
    std::vector<Table> fixed;        // W and G tables (binding-free)
    std::vector<IrSite> sites;       // CPTs built against a Registry
    std::vector<IrUnknown> unknowns;
    // query atom -> (query var, shipped elimination order)
    std::map<std::string,
             std::pair<std::string, std::vector<std::string>>> queries;
    std::vector<std::string> y_order;
    std::map<std::string, std::string> finals;   // atom -> final var
    // the B port manifest (see loader.hpp / kernel/wire.py)
    std::vector<std::string> ports_in, ports_out, ports_guard,
        ports_weight;
    bool ok = false;
    std::string error;
};

inline IrArtifact load_ir_artifact(std::istream& in) {
    IrArtifact art;
    IrSite site;
    int pending = 0;
    std::string pending_q;           // A atom awaiting its O order
    std::string line;
    while (std::getline(in, line)) {
        if (line.empty() || line[0] == '#') continue;
        std::istringstream ls(line);
        std::string tag;
        ls >> tag;
        if (tag == "C") {
            ls >> art.name;
        } else if (tag == "V") {
            std::string v;
            int c;
            ls >> v >> c;
            art.cards[v] = c;
        } else if (tag == "U") {
            IrUnknown u;
            ls >> u.atom >> u.var >> u.def;
            art.unknowns.push_back(std::move(u));
        } else if (tag == "S") {
            std::string x;
            int np;
            ls >> x >> np;
            site = IrSite{};
            for (int i = 0; i < np; ++i) {
                std::string p;
                ls >> p;
                site.vars.push_back(p);
                site.dims.push_back(2);
            }
            ls >> pending;
            site.vars.push_back(x);
            site.dims.push_back(pending);
        } else if (tag == "K") {
            IrCand c;
            int nd, hook;
            ls >> c.w >> nd;
            for (int i = 0; i < nd; ++i) {
                std::string d;
                ls >> d;
                for (size_t k = 0; k < site.vars.size(); ++k)
                    if (site.vars[k] == d)
                        c.depbits.push_back(static_cast<int>(k));
            }
            ls >> hook;
            if (hook) {
                c.hook = true;
                int compl_, na, nb, nv;
                ls >> c.factor >> compl_ >> na;
                c.complement = compl_ != 0;
                for (int i = 0; i < na; ++i) {
                    std::string a;
                    ls >> a;
                    c.args.push_back(a);
                }
                ls >> nb;
                for (int i = 0; i < nb; ++i) {
                    std::string a;
                    ls >> a;
                    c.base.push_back(a);
                }
                ls >> nv;
                for (int i = 0; i < nv; ++i) {
                    std::string a, pv;
                    ls >> a >> pv;
                    int pos = -1;
                    for (size_t k = 0; k < site.vars.size(); ++k)
                        if (site.vars[k] == pv)
                            pos = static_cast<int>(k);
                    c.vats.emplace_back(a, pos);
                }
            }
            site.cands.push_back(std::move(c));
            if (--pending == 0) art.sites.push_back(std::move(site));
        } else if (tag == "W") {
            std::string x, nv, ov;
            int card;
            ls >> x >> card >> nv >> ov;
            Table t;
            t.vars = {x};
            t.dims = {card};
            bool has_old = ov != "-";
            if (has_old) {
                t.vars.push_back(ov);
                t.dims.push_back(2);
            }
            t.vars.push_back(nv);
            t.dims.push_back(2);
            t.data.assign(t.size(), 0.0);
            for (int j = 0; j < card; ++j) {
                std::string val;
                ls >> val;
                if (!has_old) {
                    t.data[j * 2 + (val == "1" ? 1 : 0)] = 1.0;
                } else if (val == "-") {
                    t.data[(j * 2 + 0) * 2 + 0] = 1.0;
                    t.data[(j * 2 + 1) * 2 + 1] = 1.0;
                } else {
                    int v = val == "1" ? 1 : 0;
                    t.data[(j * 2 + 0) * 2 + v] = 1.0;
                    t.data[(j * 2 + 1) * 2 + v] = 1.0;
                }
            }
            art.fixed.push_back(std::move(t));
        } else if (tag == "G") {
            std::string x, ov;
            int card, n;
            ls >> x >> card >> ov >> n;
            Table t;
            t.vars = {x, ov};
            t.dims = {card, 2};
            t.data.assign(t.size(), 1.0);
            for (int i = 0; i < n; ++i) {
                int j;
                ls >> j;
                t.data[j * 2 + 1] = 0.0;
            }
            art.fixed.push_back(std::move(t));
        } else if (tag == "A") {
            std::string atom, qv;
            ls >> atom >> qv;
            art.queries[atom] = {qv, {}};
            pending_q = atom;
        } else if (tag == "O") {
            std::string qv;
            int n;
            ls >> qv >> n;
            std::vector<std::string> order(n);
            for (auto& v : order) ls >> v;
            if (!pending_q.empty())
                art.queries[pending_q].second = std::move(order);
            pending_q.clear();
        } else if (tag == "Y") {
            int n;
            ls >> n;
            art.y_order.assign(n, "");
            for (auto& v : art.y_order) ls >> v;
        } else if (tag == "F") {
            std::string atom, v;
            ls >> atom >> v;
            art.finals[atom] = v;
        } else if (tag == "B") {
            std::string kind, name;
            ls >> kind >> name;
            if (kind == "in") art.ports_in.push_back(name);
            else if (kind == "out") art.ports_out.push_back(name);
            else if (kind == "guard") art.ports_guard.push_back(name);
            else if (kind == "weight")
                art.ports_weight.push_back(name);
            else {
                art.error = "unknown port kind '" + kind + "'";
                return art;
            }
        } else if (tag == ".") {
            break;
        } else {
            art.error = "unknown record '" + tag + "'";
            return art;
        }
    }
    if (art.cards.empty()) {
        art.error = "empty artifact";
        return art;
    }
    art.ok = true;
    return art;
}

inline IrArtifact load_ir_artifact(const std::string& text) {
    std::istringstream in(text);
    return load_ir_artifact(in);
}

// The evaluator over a loaded artifact: site CPTs are built against
// the app Registry at construction (rebuild() when the world the
// bindings read has changed); every eval appends point factors —
// one per declared unknown (assignment else default), plus optional
// var-level clamps (the intervention hook: any declared variable,
// site vars included, can be pinned).
class IrEval {
  public:
    IrEval(const IrArtifact& art, const Registry& reg)
        : art_(art) {
        rebuild(reg);
    }

    void rebuild(const Registry& reg) {
        tables_ = art_.fixed;
        for (const auto& s : art_.sites)
            tables_.push_back(build_site(s, reg));
    }

    // P(atom present after the horizon | evidence over U slots).
    double marginal(const std::string& atom,
                    const std::map<std::string, int>& evidence = {},
                    const std::map<std::string, int>& clamps = {})
        const {
        auto it = art_.queries.find(atom);
        if (it == art_.queries.end())
            throw std::runtime_error("no shipped schedule for query '"
                                     + atom + "'");
        std::vector<Table> fs = with_points(evidence, clamps);
        return ir_query(fs, it->second.second, it->second.first);
    }

    // P(observed | evidence) — the runtime surprise op; 0 is the
    // UNMODELED verdict.
    double likelihood(const std::map<std::string, int>& observed,
                      const std::map<std::string, int>& evidence = {})
        const {
        std::vector<Table> fs = with_points(evidence, {});
        double denom = ir_mass(fs, art_.y_order);
        if (denom <= 0) return 0.0;
        for (const auto& [atom, val] : observed) {
            auto it = art_.finals.find(atom);
            if (it == art_.finals.end())
                throw std::runtime_error("no final mapping for "
                                         "observable '" + atom + "'");
            fs.push_back(point(it->second, val ? 1 : 0));
        }
        return ir_mass(fs, art_.y_order) / denom;
    }

    const IrArtifact& artifact() const { return art_; }

  private:
    Table point(const std::string& var, int val) const {
        auto c = art_.cards.find(var);
        int card = c == art_.cards.end() ? 2 : c->second;
        Table t;
        t.vars = {var};
        t.dims = {card};
        t.data.assign(card, 0.0);
        if (val >= 0 && val < card) t.data[val] = 1.0;
        return t;
    }

    std::vector<Table> with_points(
        const std::map<std::string, int>& evidence,
        const std::map<std::string, int>& clamps) const {
        std::vector<Table> fs = tables_;
        for (const auto& u : art_.unknowns) {
            auto e = evidence.find(u.atom);
            fs.push_back(point(u.var,
                               e == evidence.end() ? u.def
                                                   : e->second));
        }
        for (const auto& [var, val] : clamps)
            fs.push_back(point(var, val));
        return fs;
    }

    Table build_site(const IrSite& s, const Registry& reg) const {
        Table t;
        t.vars = s.vars;
        t.dims = s.dims;
        int np = static_cast<int>(s.vars.size()) - 1;
        int card = s.dims.back();
        t.data.assign(t.size(), 0.0);
        Interner atoms;
        std::vector<int> bits(np, 0);
        size_t rows = 1;
        for (int k = 0; k < np; ++k) rows *= 2;
        for (size_t row = 0; row < rows; ++row) {
            std::vector<double> w(card, 0.0);
            double tot = 0;
            for (int j = 0; j < card; ++j) {
                const IrCand& c = s.cands[j];
                bool en = true;
                for (int d : c.depbits) en = en && bits[d] == 1;
                if (!en) continue;
                double wt = c.w;
                if (c.hook) {
                    const Binding* fn = reg.find(c.factor);
                    if (!fn)
                        throw std::runtime_error("unbound factor '" +
                                                 c.factor + "'");
                    Counts counts;
                    std::map<Atom, int> m;
                    for (const auto& a : c.base)
                        m[atoms.get(a)] = 1;
                    for (const auto& [a, p] : c.vats)
                        if (p >= 0 && bits[p] == 1)
                            m[atoms.get(a)] = 1;
                    counts.assign(m.begin(), m.end());
                    CountsView view{counts, atoms};
                    double f = (*fn)(c.args, view);
                    if (c.complement) f = 1.0 - f;
                    wt *= f;
                }
                if (wt > 0) w[j] = wt;
                tot += w[j];
            }
            size_t base_idx = row * card;
            if (tot > 0)
                for (int j = 0; j < card; ++j)
                    t.data[base_idx + j] = w[j] / tot;
            for (int k = np - 1; k >= 0; --k) {
                if (++bits[k] < 2) break;
                bits[k] = 0;
            }
        }
        return t;
    }

    const IrArtifact& art_;
    std::vector<Table> tables_;
};

}  // namespace metis
