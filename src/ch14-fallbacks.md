# Why It Doesn't Break (Fallback Strategy)

> **TL;DR** — vizcrush runs on four different engines depending on what the browser supports. The fast one is first. The universally-compatible slow one is last. The user never sees which is running.

A library that only works when everything goes right is a demo, not a library. vizcrush has to work on a five-year-old Chromebook with a flaky GPU, a brand-new Mac on stable release, and a headless Node environment with no browser at all. One codebase, four very different execution environments, zero tolerance for "sorry, this browser isn't supported."

Here's the rule: **vizcrush must always work**. Not "work if you have the latest Chrome." Always.

The fallback cascade:

```
WebGPU available? → Use compute shaders for parallel ops
    ↓ no
WASM+SIMD available? → Use SIMD-accelerated WASM
    ↓ no
WASM available? → Use scalar WASM (2-4x slower than SIMD)
    ↓ no
Pure JavaScript fallback → Always works, everywhere
```

Detection is done at init time. We validate a minimal WASM module with SIMD instructions to check support (you can't just feature-detect — you need to actually try compiling a SIMD module). For WebGPU, we request an adapter and a device.

The JavaScript fallback is feature-complete. Every algorithm has a pure JS implementation. It's slower — LTTB on 1M points takes ~85ms instead of ~1.7ms — but 85ms is still vastly better than the 850ms+ your chart library would take trying to render all million points.

The WASM modules only load if they exist. In development (before running the WASM build script), the JS fallback kicks in silently. No 404 errors, no console spam. I spent an annoying amount of time making the bundler not try to statically analyze the WASM import path.

Robustness is about never falling off the cliff. Performance is about how fast you run on the flat part. Those are two different disciplines, and the next chapter covers the tricks for the second one.
