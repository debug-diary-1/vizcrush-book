# Why It Doesn't Break (Fallback Strategy)

> **TL;DR**: Every algorithm ships in two implementations: Rust/WASM and pure JavaScript. Detection happens once at init, selection happens per call, and the user never sees which one ran.

A library that only works when everything goes right is a demo, not a library. vizcrush has to work on a five-year-old Chromebook, a brand-new Mac on stable release, and a headless Node environment with no browser at all. One codebase, wildly different execution environments, zero tolerance for "sorry, this browser isn't supported."

Here's the rule: **vizcrush must always work**. Not "work if you have the latest Chrome." Always.

The fallback cascade:

```
WebAssembly available? → Use the Rust/WASM build
    ↓ no
Pure JavaScript core   → Always works, everywhere
```

Two tiers, not four. An earlier design imagined a taller ladder (WebGPU on top, separate SIMD and scalar WASM rungs below), but chapter 3 already told you what the measurements did to that idea: no WebGPU path was ever wired, and the SIMD build turned out byte-identical to the scalar one. The honest architecture is two engines with full parity.

Detection is done once at init time. You can't just check `typeof WebAssembly`; we validate a minimal WASM module to confirm the environment will actually compile one. After that, selection is per call: below a small data size the kernel prefers the JS core regardless, because crossing the WASM boundary has a fixed cost that tiny inputs never repay.

The JavaScript core is feature-complete and parity-tested: every algorithm has a pure JS implementation verified in CI to produce the same output as the WASM build. And calling it a "fallback" undersells it. On 1M-point LTTB it runs in roughly 1.5–6ms depending on the engine, and in Firefox it's the *faster* path. Either way, both engines are orders of magnitude better than the 850ms+ your chart library would burn trying to render all million points.

The WASM modules only load if they exist. In development (before running the WASM build script), the JS core kicks in silently. No 404 errors, no console spam. I spent an annoying amount of time making the bundler not try to statically analyze the WASM import path.

Robustness is about never falling off the cliff. Performance is about how fast you run on the flat part. Those are two different disciplines, and the next chapter covers the tricks for the second one.
