# corpus/ceptre — the Ceptre love triangle, under its own license

`love_triangle.llp` is a port of the Ceptre tutorial's love triangle
(`love-triangle.cep`, also `examples/love-triangle.cep` in
[chrisamaphone/interactive-lp](https://github.com/chrisamaphone/interactive-lp)).
It is byte-equal to the copy metispy shipped up to 0.1.0; the catalog's
package is `metis-catalog/domains/ceptre/love_triangle/`.

It stays in the corpus because the parity gates pin its shape, the
multiplicity-3 heartbreak and the `<>` guard:

- `sample_manifest.txt` cases `lt-act` and `lt-heartbreak` (SAMPLE PARITY);
- `ci/check.sh` gate 8, the embedded-directive `--run` and the
  `#interactive` case with stdin closed (`goldens/run_goldens.txt`);
- the C runtime's live, projection and ABI smoke tests, whose fixtures are
  compiled from it (`runtime/fixtures/ceptre/`).

## License

interactive-lp is released under the **Anti-Capitalist Software License
v1.4**, Copyright © 2023 Chris Martens; its text is [`LICENSE`](LICENSE)
here, verbatim. This file derives from it, so it is offered under that
license and **not** under this repository's Apache-2.0 grant. Robofortis is
a one-person company and uses and distributes it as an individual laboring
for themselves (ACSL condition 2a). A User must meet the license's
conditions to use, copy, modify or distribute it.
