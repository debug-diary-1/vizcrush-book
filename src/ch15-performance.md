# Making It Fast (Performance Lessons)

> **TL;DR**: Four lessons from building this library: memory layout beats clever algorithms, allocation in the hot path is the silent killer, every WASM boundary crossing has a cost, and most benchmarks are lying to you.

There's a famous quote (I can't remember who said it) that goes something like: "make it work, make it right, make it fast, in that order." Good advice. What they don't tell you is that "make it fast" is actually four separate jobs, and if you skip any one of them, the other three don't matter.

The four jobs are: respect the CPU cache, respect the garbage collector, respect the boundary between JavaScript and WASM, and respect your own benchmarking setup. This chapter is what I learned about each one while shipping vizcrush, mostly by doing it wrong first.

## Memory Layout Is Everything

```javascript
// This is slow:
const points = [{ x: 1, y: 2 }, { x: 3, y: 4 }, ...];
```

Each object is a separate heap allocation. When you iterate, the CPU fetches a cache line (64 bytes), finds a pointer, follows it to some random memory location, fetches another cache line to read the actual data, then does it all again for the next point. Cache miss after cache miss.

```javascript
// This is fast:
const x = new Float64Array([1, 3, ...]);
const y = new Float64Array([2, 4, ...]);
```

Contiguous memory. The CPU fetches a cache line and gets 8 sequential values. Prefetchers predict the linear access pattern and start loading the next cache line before you need it. Night and day difference.

This is why vizcrush uses typed arrays everywhere and returns interleaved data across the WASM boundary: `[x0, y0, x1, y1, ...]`. One contiguous allocation, zero garbage collector involvement, maximum cache utilization.

## Avoid Allocation in the Hot Path

Every `new Object()` in a tight loop is work for the garbage collector later. When the GC runs, it pauses all JavaScript execution: potentially for several milliseconds. During a pan gesture that's firing 60 times per second, a GC pause is a visible stutter.

vizcrush pre-allocates output buffers and returns a single typed array. No intermediate objects. No per-point allocations. The GC has nothing to clean up.

## The WASM Boundary Isn't Free

Calling from JavaScript into WASM has overhead: about 10-50 nanoseconds per call depending on the arguments. If you're calling a WASM function a million times in a loop, the boundary overhead adds up.

vizcrush avoids this by doing all the looping _inside_ WASM. You call `lttb(x, y, threshold)` once, it does the entire million-point computation internally, and returns the result. One boundary crossing, not a million.

## Benchmark the Right Way

Microbenchmarks are liars. I've seen benchmarks show WASM as slower than JS because:

1. **No warmup**: The first run includes JIT compilation time
2. **Too few runs**: A single outlier (GC pause, OS scheduler preemption) skews the result
3. **Mean instead of median**: One 50ms outlier in 100 runs of 1ms each makes the mean 1.5ms

vizcrush's benchmark suite does 5 warmup runs (discarded), then 100 measured runs, reports the median and p95. The CI pipeline compares against a committed baseline and fails on >15% regression (configurable for noisy environments; laptops get 25%).

That's the end of the narrative part of the book. The last chapter is a reference: the math behind every algorithm, for people who want to verify the implementation or modify it. If you came here to use vizcrush, you can close the tab with a clean conscience. If you came here to understand, the math chapter is the dessert.
