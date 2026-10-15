/* SPDX-License-Identifier: Apache-2.0 */
/* The live handle through the C ABI, in C (runtime-binding step 5): the
 * error model, K1/K2 (seed, step, enabled, fire, do), K3 (snapshot,
 * restore: the same rows again), K4 (likelihood), the weight callbacks,
 * the observer, latch and revival, and reload's degrade-to-last-good —
 * on the cascade fixture (two stages, a link, ported clauses); the host's
 * TIME face through metis_rt_tick, and the ground args of a tagged event, on
 * the love triangle's.
 *
 * usage: metis_rt_abi_smoke <live_cascade.wire> <live_love_triangle.wire> */
#include <stdio.h>
#include <string.h>

#include "metis_rt.h"

static int fails = 0;
#define CHECK(c)                                                       \
    do {                                                               \
        if (!(c)) {                                                    \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #c);        \
            ++fails;                                                   \
        }                                                              \
    } while (0)

static double pa(void* user, const char* const* args, size_t n, const metis_rt_view* v) {
    (void)user; (void)args; (void)n; (void)v;
    return 0.3;
}
static double pb(void* user, const char* const* args, size_t n, const metis_rt_view* v) {
    (void)user; (void)args; (void)n;
    return metis_rt_view_count(v, "a") > 0 ? 0.8 : 0.2;
}
static void count_rows(void* user, const metis_rt_event* ev) {
    (void)ev;
    ++*(int*)user;
}

/* a host whose TIME face gives "+ta 2", then a quiet beat, then the end */
static const char* host_lines[] = {"+ta 2"};
static metis_rt_status host_tick(void* user, const metis_rt_count* counts, size_t n,
                                 const char* const** lines, size_t* n_lines, int* end) {
    int* beat = (int*)user;
    (void)counts; (void)n;
    *end = *beat >= 2;
    *lines = host_lines;
    *n_lines = *beat == 0 ? 1 : 0;
    ++*beat;
    return METIS_RT_OK;
}

int main(int argc, char** argv) {
    const char* stages[] = {"ua", "ub"};
    const char* ta3[] = {"+ta 3"};
    const char* bad[] = {"ta"};
    metis_rt_step_result r;
    metis_rt_event ev;
    char snap[4096], again[4096];
    size_t len = 0, n = 0;
    int stage = 0, rows = 0, k;
    const char* names[2][8];
    char held[8][64];
    const char* name = NULL;
    double like = -1;
    metis_rt* rt;
    if (argc != 3) {
        fprintf(stderr, "usage: metis_rt_abi_smoke <live_cascade.wire> <live_love_triangle.wire>\n");
        return 2;
    }
    rt = metis_rt_new();
    CHECK(rt != NULL);

    /* the error model */
    CHECK(metis_rt_step(rt, &r, &ev) == METIS_RT_ENOPROGRAM && strlen(metis_rt_error(rt)) > 0);
    CHECK(metis_rt_load(rt, "/nonexistent.wire", NULL, 0, NULL, 0) == METIS_RT_EIO);
    {
        int canon[5] = {0, 0, 1, 2, 3};          /* not a permutation */
        CHECK(metis_rt_load(rt, argv[1], canon, 5, stages, 2) == METIS_RT_EARG);
    }
    CHECK(metis_rt_load(rt, argv[1], NULL, 0, stages, 1) == METIS_RT_EARG);
    CHECK(metis_rt_load(rt, argv[1], NULL, 0, stages, 2) == METIS_RT_OK);
    CHECK(metis_rt_error(rt)[0] == '\0');
    CHECK(metis_rt_n_events(rt, &n) == METIS_RT_OK && n == 5);

    /* the cascade prices pa and pb: unbound, it does not sample */
    CHECK(metis_rt_step(rt, &r, &ev) == METIS_RT_EUNBOUND);
    CHECK(metis_rt_bind_weight(rt, "pa", pa, NULL) == METIS_RT_OK);
    CHECK(metis_rt_step(rt, &r, &ev) == METIS_RT_EUNBOUND);
    CHECK(metis_rt_bind_weight(rt, "pb", pb, NULL) == METIS_RT_OK);
    CHECK(metis_rt_on_event(rt, count_rows, &rows) == METIS_RT_OK);
    CHECK(metis_rt_seed(rt, 11) == METIS_RT_OK);

    /* K2: a do row, then the tier */
    CHECK(metis_rt_do(rt, bad, 1, &ev) == METIS_RT_EARG);
    CHECK(metis_rt_do(rt, ta3, 1, &ev) == METIS_RT_OK);
    CHECK(ev.kind == METIS_RT_EXO && strcmp(ev.name, "do +ta 3") == 0 && ev.n_produce == 1 &&
          ev.produce[0].n == 3 && ev.index == -1);
    CHECK(metis_rt_enabled(rt, NULL, NULL, 0, &n) == METIS_RT_OK && n == 2);
    {
        int idx[2];
        double w[2];
        CHECK(metis_rt_enabled(rt, idx, w, 2, &n) == METIS_RT_OK);
        /* aon at pa = 0.3, aoff at its complement, each times ta's 3 */
        CHECK(n == 2 && w[0] + w[1] > 2.999 && w[0] + w[1] < 3.001 &&
              (w[0] / (w[0] + w[1]) - 0.3) * (w[0] / (w[0] + w[1]) - 0.7) < 1e-12 &&
              (w[0] / (w[0] + w[1]) - 0.3) * (w[0] / (w[0] + w[1]) - 0.7) > -1e-12);
    }
    /* event 4 is the link ab (ua -> ub): not in the tier while ta remains */
    CHECK(metis_rt_fire(rt, 4, &ev) == METIS_RT_ENOTENABLED);
    CHECK(metis_rt_fire(rt, 0, &ev) == METIS_RT_OK && ev.kind == METIS_RT_CLAUSE &&
          ev.p > 0 && ev.p < 1);

    /* K3: snapshot, eight rows, restore, the same eight rows */
    CHECK(metis_rt_snapshot(rt, NULL, 0, &len) == METIS_RT_OK && len > 0 && len < sizeof snap);
    CHECK(metis_rt_snapshot(rt, snap, sizeof snap, &len) == METIS_RT_OK &&
          strncmp(snap, "metis-live 1\n", 13) == 0);
    for (k = 0; k < 8; ++k) {
        CHECK(metis_rt_step(rt, &r, &ev) == METIS_RT_OK);
        names[0][k] = r == METIS_RT_FIRED ? strncpy(held[k], ev.name, 63) : "-";
        if (r != METIS_RT_FIRED) CHECK(metis_rt_do(rt, ta3, 1, &ev) == METIS_RT_OK);
    }
    CHECK(metis_rt_restore(rt, "not a snapshot") == METIS_RT_EARG);
    CHECK(metis_rt_restore(rt, snap) == METIS_RT_OK);
    for (k = 0; k < 8; ++k) {
        CHECK(metis_rt_step(rt, &r, &ev) == METIS_RT_OK);
        names[1][k] = r == METIS_RT_FIRED ? ev.name : "-";
        CHECK(strcmp(names[0][k], names[1][k]) == 0);
        if (r != METIS_RT_FIRED) CHECK(metis_rt_do(rt, ta3, 1, &ev) == METIS_RT_OK);
    }

    /* K4: from the snapshot, nothing observed is certain; an atom the
     * program never names, observed at 1, is impossible */
    {
        const char* none[] = {"nowhere"};
        int one[] = {1};
        CHECK(metis_rt_likelihood(rt, snap, 2, NULL, NULL, 0, &like) == METIS_RT_OK &&
              like > 0.999999 && like < 1.000001);
        CHECK(metis_rt_likelihood(rt, snap, 2, none, one, 1, &like) == METIS_RT_OK &&
              like == 0.0);
    }

    /* latch, then a do row revives the stage it latched in */
    CHECK(metis_rt_stage(rt, &stage, &name) == METIS_RT_OK);
    {
        int before = stage;
        CHECK(metis_rt_latch_done(rt) == METIS_RT_OK);
        CHECK(metis_rt_step(rt, &r, &ev) == METIS_RT_OK && r == METIS_RT_STOPPED);
        CHECK(metis_rt_stage(rt, &stage, &name) == METIS_RT_OK && stage == METIS_RT_DONE &&
              strcmp(name, "(done)") == 0);
        CHECK(metis_rt_do(rt, NULL, 0, &ev) == METIS_RT_OK && strcmp(ev.name, "tick") == 0);
        CHECK(metis_rt_stage(rt, &stage, &name) == METIS_RT_OK && stage == before);
    }
    CHECK(rows > 0);

    /* reload: a failure keeps the old program and its state */
    CHECK(metis_rt_snapshot(rt, snap, sizeof snap, &len) == METIS_RT_OK);
    CHECK(metis_rt_reload(rt, "/nonexistent.wire", NULL, 0, stages, 2) == METIS_RT_EIO &&
          strstr(metis_rt_error(rt), "serves on") != NULL);
    CHECK(metis_rt_snapshot(rt, again, sizeof again, &len) == METIS_RT_OK &&
          strcmp(snap, again) == 0);
    CHECK(metis_rt_reload(rt, argv[1], NULL, 0, stages, 2) == METIS_RT_OK);
    CHECK(metis_rt_fired(rt, &n) == METIS_RT_OK && n == 0);

    /* the host's TIME face (repl.py _tick): its lines as one exo row; a quiet
     * beat adds no row unless quiet_rows; the end applies nothing */
    {
        int beat = 0, applied = -1, end = -1;
        metis_rt_host host;
        memset(&host, 0, sizeof host);
        host.user = &beat;
        host.tick = host_tick;
        CHECK(metis_rt_tick(rt, NULL, 0, &ev, &applied, &end) == METIS_RT_EARG);
        CHECK(metis_rt_tick(rt, &host, 0, &ev, &applied, &end) == METIS_RT_OK && applied == 1 &&
              end == 0 && strcmp(ev.name, "do +ta 2") == 0 && ev.n_args == 0);
        CHECK(metis_rt_tick(rt, &host, 0, &ev, &applied, &end) == METIS_RT_OK && applied == 0 &&
              end == 0);
        CHECK(metis_rt_tick(rt, &host, 1, &ev, &applied, &end) == METIS_RT_OK && applied == 0 &&
              end == 1);
        beat = 1;                                          /* a quiet beat, with quiet rows */
        CHECK(metis_rt_tick(rt, &host, 1, &ev, &applied, &end) == METIS_RT_OK && applied == 1 &&
              strcmp(ev.name, "tick") == 0);
    }
    metis_rt_free(rt);

    /* the ground args of a fired tagged event: rule[A=x,B=y,C=z] -> x, y, z */
    rt = metis_rt_new();
    CHECK(metis_rt_load(rt, argv[2], NULL, 0, NULL, 0) == METIS_RT_OK);
    CHECK(metis_rt_seed(rt, 5) == METIS_RT_OK);
    CHECK(metis_rt_step(rt, &r, &ev) == METIS_RT_OK && r == METIS_RT_FIRED);
    {
        const char* lb = strchr(ev.name, '[');
        CHECK(lb != NULL && ev.n_args == 3);
        if (lb && ev.n_args == 3) {
            char want[256];
            snprintf(want, sizeof want, "%.*s[A=%s,B=%s,C=%s]", (int)(lb - ev.name), ev.name,
                     ev.args[0], ev.args[1], ev.args[2]);
            CHECK(strcmp(want, ev.name) == 0);
        }
    }
    metis_rt_free(rt);

    if (fails == 0) printf("C ABI SMOKE OK\n");
    return fails ? 1 : 0;
}
