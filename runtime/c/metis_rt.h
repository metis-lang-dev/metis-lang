/* SPDX-License-Identifier: Apache-2.0 */
/* metis_rt — the C ABI of the metis runtime (libmetis_rt).
 *
 * The runtime is header-only C++17 (runtime/include/metis); this is the
 * one C surface over it, for a C or C++ device host and for cgo
 * (metis-agent go/internal/rt), built the way llama.cpp's libllama is.
 *
 * The contract (it holds for every call this header grows):
 *   - Ownership. Every metis_rt_* handle is created by a _load or _new
 *     call and freed by its _free; the caller owns it. Strings and
 *     arrays inside an event are owned by the handle and stay valid
 *     until the next call on that handle. Snapshots are caller buffers:
 *     a size query, then a fill.
 *   - Errors. Every fallible call returns a metis_rt_status; on a
 *     handle, metis_rt_error(rt) gives the last error's text, owned by
 *     the handle. A call without a handle reports into the struct it
 *     fills. No C++ exception crosses this boundary.
 *
 * So far (runtime-binding step 1): the conformance seam only — the
 * archive's MetisCtrl Eval(path), the committed goldens replayed by the
 * runtime's own golden engines. The handle calls come with step 5.
 */
#ifndef METIS_RT_H
#define METIS_RT_H

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
#define METIS_RT_ABI_VERSION 1

typedef enum {
    METIS_RT_OK = 0,        /* the call did what it says */
    METIS_RT_EIO = 1,       /* a file could not be opened or read */
    METIS_RT_EPARITY = 2,   /* conformance ran, and a check failed */
    METIS_RT_EARG = 3,      /* a NULL or malformed argument */
    METIS_RT_EINTERNAL = 4  /* the runtime threw; the text says what */
} metis_rt_status;

/* the parity of one golden corpus (MetisCtrl's parity{ok, total,
 * cases, first_fail}); a plain struct the caller allocates */
typedef struct {
    int ok;                 /* checks that held */
    int total;              /* checks run */
    int cases;              /* cases in the corpus */
    int ir;                 /* 1: an IR corpus (first record `C `);
                               0: the ground-program filter corpus */
    char first_fail[256];   /* the first failed check, "" when none */
} metis_rt_parity;

/* the ABI version this library was built with (METIS_RT_ABI_VERSION) */
METIS_RT_API int metis_rt_abi_version(void);

/* Replays a committed golden corpus (corpus/goldens/ir_goldens.txt,
 * goldens.txt) through the runtime: an IR corpus by run_ir_goldens,
 * any other by run_goldens, the same dispatch as tools/metis_run.
 * Fills *out and returns METIS_RT_OK only when ok == total > 0. */
METIS_RT_API metis_rt_status metis_rt_conformance(const char* path,
                                                  metis_rt_parity* out);

#ifdef __cplusplus
}
#endif

#endif /* METIS_RT_H */
