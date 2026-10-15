/* SPDX-License-Identifier: Apache-2.0 */
/* The binding's first gate, in C on purpose (the header must compile as
 * C): every committed golden corpus named on the command line, replayed
 * through libmetis_rt's metis_rt_conformance, must give the parity
 * tools/metis_run gives natively (ci/check.sh gate 6: IR PARITY 46/46).
 *
 * usage: metis_rt_conformance <corpus-file>... */
#include <stdio.h>

#include "metis_rt.h"

int main(int argc, char** argv) {
    int i, fails = 0;
    if (argc < 2) {
        fprintf(stderr, "usage: metis_rt_conformance <corpus-file>...\n");
        return 2;
    }
    if (metis_rt_abi_version() != METIS_RT_ABI_VERSION) {
        fprintf(stderr, "ABI %d, header %d\n", metis_rt_abi_version(),
                METIS_RT_ABI_VERSION);
        return 1;
    }
    for (i = 1; i < argc; ++i) {
        metis_rt_parity p;
        metis_rt_status s = metis_rt_conformance(argv[i], &p);
        printf("C ABI %sPARITY %d/%d (%d cases) %s\n", p.ir ? "IR " : "",
               p.ok, p.total, p.cases, argv[i]);
        if (s != METIS_RT_OK) {
            printf("  status %d: %s\n", (int)s, p.first_fail);
            ++fails;
        }
    }
    return fails ? 1 : 0;
}
