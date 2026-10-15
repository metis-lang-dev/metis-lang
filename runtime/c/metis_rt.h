/* SPDX-License-Identifier: Apache-2.0 */
/* metis_rt — the C ABI of the metis runtime (libmetis_rt).
 *
 * The runtime is header-only C++17 (runtime/include/metis); this is the
 * one C surface over it, for a C or C++ device host and for cgo
 * (metis-agent go/internal/rt), built the way llama.cpp's libllama is.
 *
 * The contract (every call below keeps it):
 *   - Ownership. Every metis_rt_* handle is created by a _new call and
 *     freed by its _free; the caller owns it. Strings and arrays inside
 *     an event, the counts and the stage name are owned by the handle and
 *     stay valid until the next call on that handle (an event handed to
 *     an on_event callback: until the callback returns). Snapshots are
 *     caller buffers: a size query, then a fill.
 *   - Errors. Every fallible call returns a metis_rt_status; on a
 *     handle, metis_rt_error(rt) gives the last error's text, owned by
 *     the handle ("" after a call that succeeded). A call without a handle
 *     reports into the struct it fills. No C++ exception crosses this
 *     boundary.
 *   - Threads. A handle is not thread-safe; distinct handles are
 *     independent.
 *
 * What a handle serves (metis::Live, live.hpp; metis-agent
 * docs/RUNTIME-BINDING.md §3): an artifact's ground.wire, with the
 * sidecar's normative event order (canon) and stage names passed in —
 * the caller parses sidecar.json. K1 seed/step/fire, K2 enabled/do,
 * K3 snapshot/restore, K4 likelihood; the weight ports bound by C
 * callbacks; an event observer; reload with degrade-to-last-good.
 */
#ifndef METIS_RT_H
#define METIS_RT_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32)
#  define METIS_RT_API __declspec(dllexport)
#elif defined(__GNUC__)
#  define METIS_RT_API __attribute__((visibility("default")))
#else
#  define METIS_RT_API
#endif

/* bumped on any incompatible change to this header */
#define METIS_RT_ABI_VERSION 2

typedef enum {
    METIS_RT_OK = 0,           /* the call did what it says */
    METIS_RT_EIO = 1,          /* a file could not be opened or read */
    METIS_RT_EPARITY = 2,      /* conformance ran, and a check failed */
    METIS_RT_EARG = 3,         /* a NULL or malformed argument */
    METIS_RT_EINTERNAL = 4,    /* the runtime threw; the text says what */
    METIS_RT_ENOPROGRAM = 5,   /* no program loaded on this handle */
    METIS_RT_EUNBOUND = 6,     /* a weight port the program prices is unbound */
    METIS_RT_ENOTENABLED = 7,  /* fire: the event is not in the tier now */
    METIS_RT_ELOAD = 8         /* the artifact did not load (reload: the old serves on) */
} metis_rt_status;

/* ---- conformance (no handle) ------------------------------------------ */

typedef enum {
    METIS_RT_CORPUS_GROUND = 0,  /* the ground-program filter corpus (goldens.txt) */
    METIS_RT_CORPUS_IR = 1,      /* the IR corpus, first record `C ` (ir_goldens.txt) */
    METIS_RT_CORPUS_SAMPLE = 2   /* the sampler corpus, first record `B ` (sample_goldens.txt) */
} metis_rt_corpus;

/* the parity of one golden corpus (MetisCtrl's parity{ok, total, cases,
 * first_fail}); a plain struct the caller allocates */
typedef struct {
    int ok;                 /* checks that held */
    int total;              /* checks run */
    int cases;              /* cases in the corpus */
    metis_rt_corpus corpus; /* which engine replayed it */
    char first_fail[256];   /* the first failed check, "" when none */
} metis_rt_parity;

/* the ABI version this library was built with (METIS_RT_ABI_VERSION) */
METIS_RT_API int metis_rt_abi_version(void);

/* Replays a committed golden corpus through the runtime's own engines,
 * chosen by its first record (tools/metis_run, tools/sample_run).
 * Fills *out and returns METIS_RT_OK only when ok == total > 0. */
METIS_RT_API metis_rt_status metis_rt_conformance(const char* path,
                                                  metis_rt_parity* out);

/* ---- the live handle ---------------------------------------------------- */

typedef struct metis_rt metis_rt;

typedef enum {
    METIS_RT_CLAUSE = 0,
    METIS_RT_LINK = 1,
    METIS_RT_EXO = 2           /* a do-line row (metis_rt_do) */
} metis_rt_kind;

#define METIS_RT_DONE (-1)     /* the stage index of the latched world */

typedef struct {
    const char* atom;
    int n;
} metis_rt_count;

/* one fired or applied row (metis::LiveEvent) */
typedef struct {
    int index;                 /* wire index; -1 for an exo row */
    int canon;                 /* normative index; -1 for an exo row */
    metis_rt_kind kind;
    int stage;                 /* the stage it fired in */
    int post;                  /* a link's destination; -1 */
    const char* name;          /* the event's; exo: "do +a -b 2" or "tick" */
    const metis_rt_count* consume;
    size_t n_consume;
    const metis_rt_count* produce;
    size_t n_produce;
    const metis_rt_count* persist;
    size_t n_persist;
    const char* const* ops;    /* exo: the applied do-lines, normalized */
    size_t n_ops;
    double p;                  /* its probability in its tier; 0 for exo */
} metis_rt_event;

typedef enum {
    METIS_RT_FIRED = 0,
    METIS_RT_QUIET = 1,        /* nothing enabled: the host's tick, or latch_done */
    METIS_RT_STOPPED = 2       /* the world is latched */
} metis_rt_step_result;

METIS_RT_API metis_rt* metis_rt_new(void);
METIS_RT_API void metis_rt_free(metis_rt* rt);
METIS_RT_API const char* metis_rt_error(const metis_rt* rt);

/* Load a ground wire (an artifact's ground.wire). canon[i] = wire event
 * i's normative index (the sidecar's events[i].canon; NULL = the wire's
 * order); stage_names = the sidecar's stages (NULL = the wire's unnamed
 * stages). Replaces whatever the handle served; the seed given before
 * (metis_rt_seed) and the bound weights carry over. */
METIS_RT_API metis_rt_status metis_rt_load(metis_rt* rt, const char* wire_path,
                                           const int* canon, size_t n_canon,
                                           const char* const* stage_names,
                                           size_t n_stages);

/* The hot swap (Evaluator::reload's contract): a new artifact, or an
 * error and the old one serving on, its state untouched. The state is not
 * carried across (re-seeded with the last seed). A program that prices a
 * port not bound here fails the reload (METIS_RT_EUNBOUND). */
METIS_RT_API metis_rt_status metis_rt_reload(metis_rt* rt, const char* wire_path,
                                             const int* canon, size_t n_canon,
                                             const char* const* stage_names,
                                             size_t n_stages);

/* the counts a weight binding reads while it is called */
typedef struct metis_rt_view metis_rt_view;
METIS_RT_API int metis_rt_view_count(const metis_rt_view* view, const char* atom);

/* a weight port's value for one ground event: its resolved args, the
 * counts now (complement and pricing are the runtime's) */
typedef double (*metis_rt_weight_fn)(void* user, const char* const* args,
                                     size_t n_args, const metis_rt_view* counts);

/* Bind (or rebind) a weight port; the binding persists across loads.
 * Sampling, enabled and likelihood return METIS_RT_EUNBOUND while a port
 * the program prices is unbound. */
METIS_RT_API metis_rt_status metis_rt_bind_weight(metis_rt* rt, const char* port,
                                                  metis_rt_weight_fn fn, void* user);

/* the observer: called after every fired or applied row (step, fire, do),
 * with the row; NULL removes it */
typedef void (*metis_rt_event_fn)(void* user, const metis_rt_event* ev);
METIS_RT_API metis_rt_status metis_rt_on_event(metis_rt* rt, metis_rt_event_fn fn,
                                               void* user);

METIS_RT_API metis_rt_status metis_rt_seed(metis_rt* rt, uint64_t seed);

/* K1: one normative selection over the tier and its firing.
 * *result: FIRED (*ev filled when ev is not NULL), QUIET or STOPPED. */
METIS_RT_API metis_rt_status metis_rt_step(metis_rt* rt, metis_rt_step_result* result,
                                           metis_rt_event* ev);

/* K1: fire wire event `index` if it is in the tier now (a forced row) */
METIS_RT_API metis_rt_status metis_rt_fire(metis_rt* rt, int index, metis_rt_event* ev);

/* K2: the firing tier, (wire index, weight) in the normative order. Fills
 * up to cap entries; *n = the tier's size (a size query with cap 0). */
METIS_RT_API metis_rt_status metis_rt_enabled(metis_rt* rt, int* index, double* weight,
                                              size_t cap, size_t* n);

/* K2: one exogenous row from do-lines ("+atom [n]", "-atom [n]", a "do "
 * prefix allowed; none: a "tick" row); a latched world revives */
METIS_RT_API metis_rt_status metis_rt_do(metis_rt* rt, const char* const* lines,
                                         size_t n_lines, metis_rt_event* ev);

/* nothing can fire and the host's episode is over: latch the world */
METIS_RT_API metis_rt_status metis_rt_latch_done(metis_rt* rt);

/* the state now: the stage (METIS_RT_DONE when latched) and its name;
 * the counts by atom name, sorted; the rows fired or applied */
METIS_RT_API metis_rt_status metis_rt_stage(metis_rt* rt, int* stage, const char** name);
METIS_RT_API metis_rt_status metis_rt_counts(metis_rt* rt, const metis_rt_count** counts,
                                             size_t* n);
METIS_RT_API metis_rt_status metis_rt_fired(metis_rt* rt, size_t* fired);
METIS_RT_API metis_rt_status metis_rt_n_events(metis_rt* rt, size_t* n);

/* K3: the live state as portable text ("metis-live 1": the stage, the
 * latched stage, the rng, the fired length, counts by atom name). Writes
 * up to cap bytes and a NUL when it fits; *len = the text's length (a
 * size query with cap 0). */
METIS_RT_API metis_rt_status metis_rt_snapshot(metis_rt* rt, char* buf, size_t cap,
                                               size_t* len);

/* K3: all or nothing — a malformed snapshot changes nothing */
METIS_RT_API metis_rt_status metis_rt_restore(metis_rt* rt, const char* snapshot);

/* K4: P(each observed atom has exactly its count | the program, from the
 * snapshot's state, over `steps`), priced as the tier is: the watch's
 * surprise test (metispy kernel/record.py surprise_record) */
METIS_RT_API metis_rt_status metis_rt_likelihood(metis_rt* rt, const char* from_snapshot,
                                                 int steps, const char* const* atoms,
                                                 const int* counts, size_t n,
                                                 double* likelihood);

#ifdef __cplusplus
}
#endif

#endif /* METIS_RT_H */
