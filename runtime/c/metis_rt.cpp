// SPDX-License-Identifier: Apache-2.0
// libmetis_rt — the one translation unit behind the C ABI (metis_rt.h):
// the header-only runtime, compiled once, with nothing thrown across.
#include "metis_rt.h"

#include <cstdio>
#include <cstring>
#include <exception>
#include <fstream>
#include <map>
#include <memory>
#include <set>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

#include "metis/golden.hpp"
#include "metis/ir.hpp"
#include "metis/live.hpp"
#include "metis/loader.hpp"
#include "metis/sample_golden.hpp"

struct metis_rt_view {
    const metis::CountsView* counts;
};

namespace {

// a status with its text: thrown inside, caught at the boundary
struct Fail {
    metis_rt_status status;
    std::string text;
};

void set_text(char* dst, size_t cap, const std::string& s) {
    std::snprintf(dst, cap, "%s", s.c_str());
}

metis_rt_corpus corpus_of(const char* path) {
    std::ifstream in(path);
    std::string line;
    while (std::getline(in, line)) {
        if (line.empty() || line[0] == '#') continue;
        if (line.rfind("C ", 0) == 0) return METIS_RT_CORPUS_IR;
        if (line.rfind("B ", 0) == 0) return METIS_RT_CORPUS_SAMPLE;
        return METIS_RT_CORPUS_GROUND;
    }
    return METIS_RT_CORPUS_GROUND;
}

// the storage behind one metis_rt_event (valid until the next call)
struct EventStore {
    metis::LiveEvent ev;
    std::vector<metis_rt_count> consume, produce, persist;
    std::vector<const char*> ops;
    std::vector<std::string> args;
    std::vector<const char*> arg_ptrs;
    metis_rt_event out{};

    const metis_rt_event& fill(metis::LiveEvent e) {
        ev = std::move(e);
        auto counts = [](const std::vector<std::pair<std::string, int>>& v,
                         std::vector<metis_rt_count>& dst) {
            dst.clear();
            for (const auto& [a, n] : v) dst.push_back({a.c_str(), n});
        };
        counts(ev.consume, consume);
        counts(ev.produce, produce);
        counts(ev.persist, persist);
        ops.clear();
        for (const auto& o : ev.ops) ops.push_back(o.c_str());
        out.index = ev.index;
        out.canon = ev.canon;
        out.kind = ev.kind == "link" ? METIS_RT_LINK
                 : ev.kind == "exo" ? METIS_RT_EXO : METIS_RT_CLAUSE;
        out.stage = ev.stage;
        out.post = ev.post;
        out.name = ev.name.c_str();
        out.consume = consume.data();
        out.n_consume = consume.size();
        out.produce = produce.data();
        out.n_produce = produce.size();
        out.persist = persist.data();
        out.n_persist = persist.size();
        out.ops = ops.data();
        out.n_ops = ops.size();
        out.p = ev.p;
        // the ground args (metispy repl._ground_args): rule[X=a,Y=b] -> a, b
        args.clear();
        const size_t lb = ev.name.find('[');
        if (lb != std::string::npos && ev.kind != "exo") {
            std::string tag = ev.name.substr(lb + 1);
            if (!tag.empty() && tag.back() == ']') tag.pop_back();
            size_t start = 0;
            for (;;) {
                const size_t c = tag.find(',', start);
                const std::string kv = tag.substr(start, c - start);
                if (!kv.empty()) {
                    const size_t eq = kv.find('=');
                    args.push_back(eq == std::string::npos ? kv : kv.substr(eq + 1));
                }
                if (c == std::string::npos) break;
                start = c + 1;
            }
        }
        arg_ptrs.clear();
        for (const auto& a : args) arg_ptrs.push_back(a.c_str());
        out.args = arg_ptrs.data();
        out.n_args = arg_ptrs.size();
        return out;
    }
};

}  // namespace

struct metis_rt {
    std::unique_ptr<metis::Live> live;
    std::string error;
    uint64_t seed = 0;
    std::map<std::string, std::pair<metis_rt_weight_fn, void*>> weights;
    std::vector<std::string> unbound;      // ports the program prices, unbound
    metis_rt_event_fn observer = nullptr;
    void* observer_user = nullptr;
    EventStore event;
    std::vector<metis_rt_count> counts;
    std::map<std::string, int> counts_store;
    std::string stage_name;

    metis::Live& need() {
        if (!live) throw Fail{METIS_RT_ENOPROGRAM, "no program loaded"};
        return *live;
    }
    metis::Live& priced() {
        metis::Live& l = need();
        if (!unbound.empty())
            throw Fail{METIS_RT_EUNBOUND, "unbound weight port '" + unbound.front() + "'"};
        return l;
    }

    metis::Registry registry() const {
        metis::Registry reg;
        for (const auto& [port, b] : weights) {
            const metis_rt_weight_fn fn = b.first;
            void* user = b.second;
            reg.weight(port, [fn, user](const std::vector<std::string>& args,
                                        const metis::CountsView& view) {
                std::vector<const char*> a;
                for (const auto& s : args) a.push_back(s.c_str());
                metis_rt_view v{&view};
                return fn(user, a.data(), a.size(), &v);
            });
        }
        return reg;
    }

    // the ports `l` prices that are not bound here
    std::vector<std::string> missing(const metis::Live& l) const {
        std::set<std::string> need;
        for (const auto& r : l.program().refs)
            if (!r.factor.empty() && !weights.count(r.factor)) need.insert(r.factor);
        return {need.begin(), need.end()};
    }

    // price `l` with the bindings when every port it prices is bound
    void price(metis::Live& l, std::vector<std::string>& gaps) {
        gaps = missing(l);
        if (gaps.empty() && !weights.empty()) l.bind(registry());
    }

    void observe(const metis_rt_event& e) {
        if (observer) observer(observer_user, &e);
    }
};

namespace {

std::unique_ptr<metis::Live> build(const char* wire_path, const int* canon, size_t n_canon,
                                   const char* const* stage_names, size_t n_stages) {
    if (!wire_path) throw Fail{METIS_RT_EARG, "no wire path"};
    std::ifstream in(wire_path);
    if (!in) throw Fail{METIS_RT_EIO, std::string("cannot open ") + wire_path};
    metis::LoadedProgram lp = metis::load_program(in);
    if (!lp.ok) throw Fail{METIS_RT_ELOAD, std::string(wire_path) + ": " + lp.error};
    if (stage_names) {
        if (n_stages != lp.program.stage_names.size())
            throw Fail{METIS_RT_EARG, std::to_string(n_stages) + " stage names for " +
                                          std::to_string(lp.program.stage_names.size()) +
                                          " stages"};
        for (size_t i = 0; i < n_stages; ++i) {
            if (!stage_names[i]) throw Fail{METIS_RT_EARG, "a NULL stage name"};
            lp.program.stage_names[i] = stage_names[i];
        }
    }
    std::vector<int> order;
    if (canon) order.assign(canon, canon + n_canon);
    try {
        return std::make_unique<metis::Live>(std::move(lp), order);
    } catch (const std::invalid_argument& e) {
        throw Fail{METIS_RT_EARG, e.what()};
    }
}

// one entry point: the error cleared, every throw turned into a status
template <class F>
metis_rt_status guard(metis_rt* rt, F&& body) {
    if (!rt) return METIS_RT_EARG;
    rt->error.clear();
    try {
        body();
        return METIS_RT_OK;
    } catch (const Fail& f) {
        rt->error = f.text;
        return f.status;
    } catch (const std::invalid_argument& e) {
        rt->error = e.what();
        return METIS_RT_EARG;
    } catch (const std::exception& e) {
        rt->error = e.what();
    } catch (...) {
        rt->error = "unknown exception";
    }
    return METIS_RT_EINTERNAL;
}

}  // namespace

extern "C" {

int metis_rt_abi_version(void) { return METIS_RT_ABI_VERSION; }

metis_rt_status metis_rt_conformance(const char* path, metis_rt_parity* out) {
    if (out == nullptr) return METIS_RT_EARG;
    std::memset(out, 0, sizeof *out);
    if (path == nullptr) {
        set_text(out->first_fail, sizeof out->first_fail, "no path");
        return METIS_RT_EARG;
    }
    try {
        if (!std::ifstream(path)) {
            set_text(out->first_fail, sizeof out->first_fail,
                     std::string("cannot open ") + path);
            return METIS_RT_EIO;
        }
        const metis_rt_corpus kind = corpus_of(path);
        const metis::GoldenResult r =
            kind == METIS_RT_CORPUS_IR ? metis::run_ir_goldens(path)
            : kind == METIS_RT_CORPUS_SAMPLE ? metis::run_sample_goldens(path)
                                             : metis::run_goldens(path);
        out->ok = r.ok;
        out->total = r.total;
        out->cases = r.cases;
        out->corpus = kind;
        set_text(out->first_fail, sizeof out->first_fail, r.first_fail);
        return r.total > 0 && r.ok == r.total ? METIS_RT_OK : METIS_RT_EPARITY;
    } catch (const std::exception& e) {
        set_text(out->first_fail, sizeof out->first_fail, e.what());
    } catch (...) {
        set_text(out->first_fail, sizeof out->first_fail, "unknown exception");
    }
    return METIS_RT_EINTERNAL;
}

metis_rt* metis_rt_new(void) {
    try {
        return new metis_rt();
    } catch (...) {
        return nullptr;
    }
}

void metis_rt_free(metis_rt* rt) { delete rt; }

const char* metis_rt_error(const metis_rt* rt) { return rt ? rt->error.c_str() : "no handle"; }

metis_rt_status metis_rt_load(metis_rt* rt, const char* wire_path, const int* canon,
                              size_t n_canon, const char* const* stage_names,
                              size_t n_stages) {
    return guard(rt, [&] {
        auto live = build(wire_path, canon, n_canon, stage_names, n_stages);
        std::vector<std::string> gaps;
        rt->price(*live, gaps);
        live->seed(rt->seed);
        rt->live = std::move(live);
        rt->unbound = std::move(gaps);
    });
}

metis_rt_status metis_rt_reload(metis_rt* rt, const char* wire_path, const int* canon,
                                size_t n_canon, const char* const* stage_names,
                                size_t n_stages) {
    return guard(rt, [&] {
        std::unique_ptr<metis::Live> live;
        try {
            live = build(wire_path, canon, n_canon, stage_names, n_stages);
        } catch (const Fail& f) {
            throw Fail{f.status, "reload refused, the old program serves on: " + f.text};
        }
        std::vector<std::string> gaps;
        rt->price(*live, gaps);
        if (!gaps.empty())
            throw Fail{METIS_RT_EUNBOUND, "reload refused, the old program serves on: "
                                          "unbound weight port '" + gaps.front() + "'"};
        live->seed(rt->seed);
        rt->live = std::move(live);
        rt->unbound.clear();
    });
}

int metis_rt_view_count(const metis_rt_view* view, const char* atom) {
    if (!view || !view->counts || !atom) return 0;
    return view->counts->count(atom);
}

metis_rt_status metis_rt_bind_weight(metis_rt* rt, const char* port, metis_rt_weight_fn fn,
                                     void* user) {
    return guard(rt, [&] {
        if (!port || !fn) throw Fail{METIS_RT_EARG, "bind_weight: a port and a function"};
        rt->weights[port] = {fn, user};
        if (rt->live) rt->price(*rt->live, rt->unbound);
    });
}

metis_rt_status metis_rt_on_event(metis_rt* rt, metis_rt_event_fn fn, void* user) {
    return guard(rt, [&] {
        rt->observer = fn;
        rt->observer_user = user;
    });
}

metis_rt_status metis_rt_seed(metis_rt* rt, uint64_t seed) {
    return guard(rt, [&] {
        rt->seed = seed;
        if (rt->live) rt->live->seed(seed);
    });
}

metis_rt_status metis_rt_step(metis_rt* rt, metis_rt_step_result* result,
                              metis_rt_event* ev) {
    return guard(rt, [&] {
        if (!result) throw Fail{METIS_RT_EARG, "step: no result"};
        metis::LiveEvent e;
        switch (rt->priced().step(&e)) {
            case metis::StepResult::Fired: {
                *result = METIS_RT_FIRED;
                const metis_rt_event& out = rt->event.fill(std::move(e));
                if (ev) *ev = out;
                rt->observe(out);
                break;
            }
            case metis::StepResult::Quiet: *result = METIS_RT_QUIET; break;
            case metis::StepResult::Done: *result = METIS_RT_STOPPED; break;
        }
    });
}

metis_rt_status metis_rt_fire(metis_rt* rt, int index, metis_rt_event* ev) {
    return guard(rt, [&] {
        metis::Live& l = rt->priced();
        if (index < 0 || static_cast<size_t>(index) >= l.program().program.events.size())
            throw Fail{METIS_RT_EARG, "fire: no event " + std::to_string(index)};
        metis::LiveEvent e;
        if (!l.fire(index, &e))
            throw Fail{METIS_RT_ENOTENABLED, "fire: " + l.program().program.events[index].name +
                                                 " is not enabled"};
        const metis_rt_event& out = rt->event.fill(std::move(e));
        if (ev) *ev = out;
        rt->observe(out);
    });
}

metis_rt_status metis_rt_enabled(metis_rt* rt, int* index, double* weight, size_t cap,
                                 size_t* n) {
    return guard(rt, [&] {
        if (!n || (cap && (!index || !weight))) throw Fail{METIS_RT_EARG, "enabled: buffers"};
        const auto ws = rt->priced().enabled();
        *n = ws.size();
        for (size_t k = 0; k < ws.size() && k < cap; ++k) {
            index[k] = ws[k].first;
            weight[k] = ws[k].second;
        }
    });
}

metis_rt_status metis_rt_do(metis_rt* rt, const char* const* lines, size_t n_lines,
                            metis_rt_event* ev) {
    return guard(rt, [&] {
        if (n_lines && !lines) throw Fail{METIS_RT_EARG, "do: no lines"};
        std::vector<std::string> ls;
        for (size_t i = 0; i < n_lines; ++i) {
            if (!lines[i]) throw Fail{METIS_RT_EARG, "do: a NULL line"};
            ls.emplace_back(lines[i]);
        }
        const metis_rt_event& out = rt->event.fill(rt->need().apply(ls));
        if (ev) *ev = out;
        rt->observe(out);
    });
}

metis_rt_status metis_rt_latch_done(metis_rt* rt) {
    return guard(rt, [&] { rt->need().latch_done(); });
}

metis_rt_status metis_rt_stage(metis_rt* rt, int* stage, const char** name) {
    return guard(rt, [&] {
        const metis::Live& l = rt->need();
        if (stage) *stage = l.stage();
        rt->stage_name = l.stage_name(l.stage());
        if (name) *name = rt->stage_name.c_str();
    });
}

metis_rt_status metis_rt_counts(metis_rt* rt, const metis_rt_count** counts, size_t* n) {
    return guard(rt, [&] {
        if (!counts || !n) throw Fail{METIS_RT_EARG, "counts: outputs"};
        rt->counts_store = rt->need().named_counts();
        rt->counts.clear();
        for (const auto& [a, c] : rt->counts_store) rt->counts.push_back({a.c_str(), c});
        *counts = rt->counts.data();
        *n = rt->counts.size();
    });
}

metis_rt_status metis_rt_fired(metis_rt* rt, size_t* fired) {
    return guard(rt, [&] {
        if (!fired) throw Fail{METIS_RT_EARG, "fired: output"};
        *fired = rt->need().fired();
    });
}

metis_rt_status metis_rt_n_events(metis_rt* rt, size_t* n) {
    return guard(rt, [&] {
        if (!n) throw Fail{METIS_RT_EARG, "n_events: output"};
        *n = rt->need().program().program.events.size();
    });
}

metis_rt_status metis_rt_tick(metis_rt* rt, const metis_rt_host* host, int quiet_rows,
                              metis_rt_event* ev, int* applied, int* end) {
    return guard(rt, [&] {
        if (!host || !host->tick || !applied || !end)
            throw Fail{METIS_RT_EARG, "tick: a host with a tick face, and outputs"};
        metis::Live& l = rt->need();
        const auto now = l.named_counts();
        std::vector<metis_rt_count> counts;
        for (const auto& [a, n] : now) counts.push_back({a.c_str(), n});
        const char* const* lines = nullptr;
        size_t n_lines = 0;
        int over = 0;
        const metis_rt_status s =
            host->tick(host->user, counts.data(), counts.size(), &lines, &n_lines, &over);
        if (s != METIS_RT_OK) throw Fail{s, "tick: the host's tick failed"};
        *applied = 0;
        *end = over ? 1 : 0;
        if (over) return;
        if (n_lines == 0 && !quiet_rows) return;     // a quiet beat adds no row
        std::vector<std::string> ls;
        for (size_t i = 0; i < n_lines; ++i) {
            if (!lines[i]) throw Fail{METIS_RT_EARG, "tick: a NULL do-line"};
            ls.emplace_back(lines[i]);
        }
        const metis_rt_event& out = rt->event.fill(l.apply(ls));
        *applied = 1;
        if (ev) *ev = out;
        rt->observe(out);
    });
}

metis_rt_status metis_rt_snapshot(metis_rt* rt, char* buf, size_t cap, size_t* len) {
    return guard(rt, [&] {
        if (!len || (cap && !buf)) throw Fail{METIS_RT_EARG, "snapshot: buffers"};
        const std::string s = rt->need().snapshot();
        *len = s.size();
        if (cap > s.size()) std::memcpy(buf, s.c_str(), s.size() + 1);
    });
}

metis_rt_status metis_rt_restore(metis_rt* rt, const char* snapshot) {
    return guard(rt, [&] {
        if (!snapshot) throw Fail{METIS_RT_EARG, "restore: no snapshot"};
        rt->need().restore(snapshot);
    });
}

metis_rt_status metis_rt_likelihood(metis_rt* rt, const char* from_snapshot, int steps,
                                    const char* const* atoms, const int* counts, size_t n,
                                    double* likelihood) {
    return guard(rt, [&] {
        if (!from_snapshot || !likelihood || steps < 0 || (n && (!atoms || !counts)))
            throw Fail{METIS_RT_EARG, "likelihood: arguments"};
        std::map<std::string, int> observed;
        for (size_t i = 0; i < n; ++i) {
            if (!atoms[i]) throw Fail{METIS_RT_EARG, "likelihood: a NULL atom"};
            observed[atoms[i]] = counts[i];
        }
        *likelihood = rt->priced().likelihood(from_snapshot, steps, observed);
    });
}

}  // extern "C"
