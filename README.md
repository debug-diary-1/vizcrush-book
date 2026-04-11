# The vizcrush Book

The free, web-native edition of _GPU-Accelerated Data Primitives for Browser Visualization_ — the companion book to the [vizcrush](https://github.com/pallavL01/vizcrush) library.

Read it online at **[book.vizcrush.dev](https://book.vizcrush.dev)** (once the GitHub Pages deploy lands) or build it locally.

## What it covers

Twelve chapters, ~15K words, read front to back in about 90 minutes:

1. The Wall — why browser charts die at 100K points
2. What vizcrush Actually Does
3. The Two Engines: WASM and WebGPU
4. LTTB — the algorithm that started everything
5. MinMaxLTTB, M4, LTOB
6. Binning (1D, 2D, hexagonal)
7. Quadtrees, kd-trees, hash grids
8. Streaming and sketches (Welford, t-digest, KLL, DDSketch, HLL, CMS, reservoir)
9. Sorting, normalizing, filtering, reshaping
10. Fallback strategy
11. Performance lessons
12. The math behind it all

This is not API reference — that lives with the library itself. This book explains _why_ the algorithms work, and when to pick which one.

## Building locally

You'll need [mdBook](https://rust-lang.github.io/mdBook/):

```sh
cargo install mdbook
```

Then, from the repo root:

```sh
mdbook serve       # live-reload preview at http://localhost:3000
mdbook build       # static site into ./book/
```

## Contributing

PRs welcome for:

- Typos, grammar, clarity
- Technical corrections (cite the paper or benchmark)
- Translations (open an issue first so we can coordinate branches)

Not accepting:

- New algorithm chapters that don't exist in the library — the book tracks what vizcrush actually ships
- Opinion inversions ("actually LTTB is bad") — the book is a point of view, not a survey paper

## License

Free edition: [CC BY-NC 4.0](./LICENSE). Non-commercial redistribution, translation, and quotation are encouraged. Commercial use requires permission — a paid extended edition is planned.
