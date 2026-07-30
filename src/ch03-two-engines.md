# The Two Engines: WASM and the JS Core

> **TL;DR**: Every vizcrush algorithm ships twice: once in Rust compiled to WebAssembly, once in plain JavaScript over typed arrays. In Chrome, WASM is about 4× faster. In Firefox and Safari, the JS core holds its own or outright wins. vizcrush picks per call; you never have to think about it.

Conventional wisdom says WebAssembly runs at "near-native speed" and JavaScript is the slow interpreted cousin. We believed it too. An early draft of this chapter told a much tidier story, complete with a crossover table showing exactly when each engine wins. Then we actually benchmarked across three browser engines, and the tidy story fell apart. What replaced it is more interesting, and it's the real content of this chapter: performance claims you haven't measured are fiction, even when they're plausible.

## Engine 1: Rust compiled to WebAssembly

WebAssembly is a binary instruction format that browsers execute without the overheads JavaScript carries: no garbage collector pausing your code at random moments, no JIT compiler deciding halfway through that your function needs recompiling because you passed it a string instead of a number.

We write the core algorithms in Rust and compile them to `.wasm` modules (8–27KB gzipped per package). The build enables the SIMD128 feature, and here's the first honest surprise: enabling it changes nothing. The SIMD build is byte-identical to the scalar build. SIMD (Single Instruction, Multiple Data) is real and powerful, but compilers only auto-vectorize loops with no data-dependent branching, and downsampling loops branch constantly ("which of these candidate points makes the biggest triangle?"). You don't get SIMD "for free" by flipping a compiler flag; you get it by restructuring algorithms around it, which is future work, not shipped reality.

## Engine 2: The JS core everyone underestimates

The JavaScript implementation is not a grudging fallback. It's the same algorithm, written over `Float64Array` with monomorphic inner loops, which happens to be exactly the shape of code modern JIT compilers optimize best. No boxed objects, no property lookups, no polymorphism: just flat memory and arithmetic. After warmup, a JIT turns that into machine code that looks a lot like what the Rust compiler produced.

## What We Measured

Batch-timed LTTB, one million points down to one thousand, three engines:

| Engine                  | WASM   | JS core | Winner            |
| ----------------------- | ------ | ------- | ----------------- |
| Chromium (V8)           | 1.5ms  | 6.0ms   | WASM, ~4× faster  |
| Firefox (SpiderMonkey)  | 17.2ms | 2.1ms   | JS, ~8× faster    |
| WebKit (JavaScriptCore) | 2.0ms  | 1.4ms   | JS, ~1.4× faster  |

Read that middle row again. In Firefox, the "fast" engine is eight times slower than the "fallback." And in every engine, WASM's first call is the slowest, because module instantiation and warmup aren't free.

The lesson: "WASM vs JS" is not a property of your code. It's a property of the engine running it. Any library that quotes you a single universal speedup number for WASM is telling you about one browser.

## So Why Keep WASM at All?

Because Chromium is where most users are, and a 4× win in the common case is worth shipping. The decision rule is simple: use WASM when WebAssembly is available, keep the JS core first-class and parity-tested (same inputs, same outputs, verified in CI), and let either one carry the load without the caller noticing. Below a small data size the kernel prefers the JS core anyway, since crossing the WASM boundary has a fixed cost that tiny inputs never pay back.

## What About the GPU?

You may have noticed a missing engine. Binning half a million points is embarrassingly parallel; GPUs were built for exactly that; WebGPU exposes them to the browser. There are literally WGSL compute-shader drafts sitting in the vizcrush repository.

They are not wired up, and the numbers above explain why. GPU compute pays a fixed toll: upload the data to GPU memory, compile and dispatch the shader, read the results back. That toll is on the order of milliseconds. Every operation in this book already finishes in single-digit milliseconds on the CPU at browser-realistic data sizes, so the GPU's parallelism has nothing to amortize; the CPU is done before the GPU finishes clearing its throat. If profiling ever surfaces a workload where that stops being true, the drafts are waiting.

So it's not "GPU good, CPU bad," and it's not "WASM fast, JS slow." It's: measure, on the engines your users actually run.

Speaking of measuring, the first algorithm we're going to meet is a beautifully sequential one, which means the question of parallelism never even comes up. It's also the one that got me into writing this library in the first place.
