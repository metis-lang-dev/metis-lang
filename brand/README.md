# brand — the metis mark

The source is a generated design (Gemini, 2026-10-25), which the user chose. It is the circle, with the tree of
circuits and the head, and the word METIS below it: `metis-icon-source.jpeg`, 1024². The icons are made from it by
`make_icons.py` (Pillow, numpy). It drops the empty frame the source carries in its pixels: a white rounded square,
and a transparency checkerboard around the mark and inside its circle.

| file | what | used by |
|---|---|---|
| `metis-logo-512.png` | the circle and the word, transparent | docs, slides |
| `metis-mark-512.png` | the circle alone, transparent | small sizes, dark grounds (the navy word is faint there) |
| `vscode-icon.png` | the logo, 256² | `contrib/vscode/images/icon.png` (the extension's icon; `icon-mark.png` beside it is the mark) |
| `favicon-32.png`, `favicon-192.png` | the mark, transparent | metis-lang-dev.github.io `assets/` |
| `apple-touch-icon.png` | the mark on white, 180² | metis-lang-dev.github.io `assets/` (iOS fills a transparent ground with black) |

To make them again: `python3 brand/make_icons.py`, then copy the files where the table says.
