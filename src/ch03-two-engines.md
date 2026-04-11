# The Two Engines: WASM and WebGPU

> **TL;DR** — WebAssembly is a fast single-runner; WebGPU is a slow-to-start army of thousands. Small jobs go to WASM, big parallel jobs go to WebGPU, and vizcrush picks automatically.

Here's a short thought experiment. You need to mow a hundred square meters of grass. Would you rather have one fast lawn mower, or five hundred people with scissors?

The lawn mower wins for a small lawn. By the time you've organized the scissors crew, explained the plan, and handed out gloves, the mower is already done. But now scale the problem up. A _thousand_ square meters. A hundred thousand. At some point the mower is overwhelmed and those five hundred snipping hands, working in parallel, finish before the mower's engine cools down.

That's the WASM versus WebGPU story, almost exactly. WASM is the fast mower: one thread, low overhead, starts instantly. WebGPU is the scissor crew: slow to organize, unbeatable once it gets going. The interesting question is where the crossover happens — and that's what vizcrush computes automatically so you never have to think about it.

## Engine 1: WebAssembly with SIMD

WebAssembly is a binary instruction format that browsers execute at near-native speed. Unlike JavaScript, there's no garbage collector pausing your code at random moments, no JIT compiler deciding halfway through that your function needs to be recompiled because you passed it a string instead of a number.

We write the core algorithms in a systems language, compile them to a `.wasm` file (typically under 15KB gzipped), and the browser loads and executes it at roughly 80-90% of native speed.

SIMD stands for Single Instruction, Multiple Data. Imagine you need to subtract a minimum value from a million numbers (normalization). Normal code does them one at a time. SIMD packs four numbers into a single 128-bit register and processes all four in one instruction:

```
Without SIMD:
  a[0] - min → result[0]     // one instruction
  a[1] - min → result[1]     // one instruction
  a[2] - min → result[2]     // one instruction
  a[3] - min → result[3]     // one instruction

With SIMD128:
  [a[0], a[1], a[2], a[3]] - [min, min, min, min] → [r[0], r[1], r[2], r[3]]
  // one instruction does all four
```

For 64-bit floats (which is what we use — nobody wants to lose precision on financial data), SIMD processes two values per instruction. Still a 2x speedup for free, on top of the WASM speed advantage over JavaScript.

The build pipeline enables SIMD128 at compile time so every supported instruction is used where it helps.

## Engine 2: WebGPU Compute Shaders

WebGPU is different. Where WASM is fast sequential code on the CPU, WebGPU is massively parallel code on the GPU.

A modern GPU has hundreds or thousands of small cores. They're individually slower than a CPU core, but there are so many of them that for the right workload, they crush it. The "right workload" means: each data point can be processed independently without looking at other data points.

2D binning is a perfect example. For each of 500K scatter points, you compute which grid cell it falls into and increment that cell's counter. Each point's computation is completely independent — a thousand GPU threads can each process their own subset with no communication needed.

The code for GPU computation is written in WGSL, a C-like shading language:

```wgsl
@compute @workgroup_size(256)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let idx = gid.x;
  if (idx >= params.point_count) { return; }

  // This function runs 256 times in parallel per workgroup,
  // across ceil(point_count / 256) workgroups.
  // Total: every point gets its own "thread."

  let px = x_data[idx];
  let py = y_data[idx];
  var xi = u32((px - params.x_min) / range_x * f32(params.x_bins));
  var yi = u32((py - params.y_min) / range_y * f32(params.y_bins));

  // atomicAdd is thread-safe — many threads can
  // increment the same cell without corruption
  atomicAdd(&grid[yi * params.x_bins + xi], 1u);
}
```

## When Which Engine Wins

There's a crossover point. GPU dispatch has overhead — uploading data to GPU memory, compiling the shader, reading results back. That overhead is about 1ms regardless of data size. So for small datasets, the CPU (WASM) is faster because it starts immediately. For large datasets, the GPU wins because its parallelism overwhelms the overhead.

In practice:

| Data size | WASM+SIMD | WebGPU | Pick               |
| --------- | --------- | ------ | ------------------ |
| 10K       | 0.5ms     | 1.5ms  | WASM               |
| 100K      | 4ms       | 2.5ms  | WebGPU             |
| 1M        | 40ms      | 5ms    | WebGPU (8x faster) |

vizcrush checks at runtime what's available and picks automatically. You can override it if you want, but the defaults are pretty good.

There's also an algorithmic constraint. LTTB can't run on the GPU because each bucket selection depends on the _previous_ selected point — it's inherently sequential. bin2d can't run efficiently on the CPU at scale because it's embarrassingly parallel and the GPU was literally designed for this.

So it's not "GPU good, CPU bad." It's "right tool for the structure of the algorithm."

Speaking of structure — the first algorithm we're going to meet is a beautifully sequential one, which means it'll never leave the CPU. It's also the one that got me into writing this library in the first place.
