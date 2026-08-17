# Using vizcrush: A Tour in Code

> **TL;DR**: Every vizcrush function, shown in the smallest possible TypeScript example. Copy, paste, ship. If you only read one chapter in this book, make it this one, and bookmark it.

The rest of the book explains _what_ vizcrush does and _why_ it does it the way it does. This chapter is the bridge: how to actually call these functions from a real project. One code example per algorithm family, in TypeScript, with the understanding that every example assumes `pnpm install`, a bundler that handles ESM, and a modern browser.

If you want to follow along, the library lives at [github.com/debug-diary-1/vizcrush](https://github.com/debug-diary-1/vizcrush).

## Install

vizcrush is published as a set of narrow packages. Install only what you need:

```sh
pnpm add @vizcrush/core @vizcrush/downsample
```

Add more as you go, `@vizcrush/bin`, `@vizcrush/aggregate`, `@vizcrush/spatial`, `@vizcrush/spatial3d`, `@vizcrush/bin3d`, `@vizcrush/transform`, `@vizcrush/ai`, `@vizcrush/react`.

## Step 1: Initialize and Check Capabilities

Before you call anything, ask vizcrush what it can do. The `init()` call probes the environment and picks the backend: the Rust/WASM build when WebAssembly is available, the pure-JS core otherwise.

```ts
import { init } from "@vizcrush/core";

const ctx = await init();

console.log(ctx.backend);
// 'wasm' | 'js'

console.log(ctx.capabilities);
// { webgpu: true, wasm: true, wasmSimd: true, sharedArrayBuffer: false }
```

You only call `init()` once per page. The returned `ctx` object is shared by every other vizcrush call. The `capabilities` object is raw environment probes for your own diagnostics; only `wasm` decides the backend. Per call, small inputs run on the JS core regardless (the WASM boundary has a fixed cost that tiny arrays never pay back), and you can force a path with `{ backend: "js" | "wasm" }` if you're benchmarking. The reader will not notice any of this.

Nothing else in this chapter needs you to look at `ctx` again. It's always there in the background doing the right thing.

## Step 2: Downsample a Time Series

You have a million points. Your chart can show 1920. `lttb` does the selection:

```ts
import { lttb } from "@vizcrush/downsample";

// x and y are Float64Arrays, same length
const { x: outX, y: outY } = await lttb(x, y, 1920);

// outX and outY have length 1920, feed them to your chart
```

That's the whole API. Pass typed arrays in, get typed arrays out. If `x` is already sorted (which it is for time series), you don't need to do anything else.

For spiky data, swap in `minMaxLttb`:

```ts
import { minMaxLttb } from "@vizcrush/downsample";

const { x: outX, y: outY } = await minMaxLttb(x, y, 1920);
```

Same signature, different guarantees. See chapter 5 for when to pick which.

**Sync variant**: if you're in a hot render loop and can't `await`, use `lttbSync`. It runs the JS core directly and returns the result immediately.

## Step 3: Build a 2D Density Heatmap

`bin2d` is for scatter plots where overlapping dots hide your clusters:

```ts
import { bin2d } from "@vizcrush/bin";

const result = await bin2d(x, y, {
  xBins: 128,
  yBins: 128,
  // omit bounds to auto-detect from the data
});

// result.counts is a Uint32Array of length 128 * 128
// result.xEdges and result.yEdges give you the bin boundaries
```

Render `result.counts` as a heatmap, map count to color, done. You now see density instead of a blob of dots.

For visually isotropic clusters, use `hexbin` instead:

```ts
import { hexbin } from "@vizcrush/bin";

const hexes = await hexbin(x, y, { radius: 10 });
// hexes is an array of { x, y, count }, one per non-empty hex
```

## Step 4: Index Points for Hover and Range Queries

Interactive charts need to answer "what point is under the cursor" in under a millisecond. Build a quadtree once, query it many times:

```ts
import { buildQuadtree, queryRange, queryNearest } from "@vizcrush/spatial";

const tree = await buildQuadtree(x, y);

// Range query: all point indices in a viewport
const indices = queryRange(tree, {
  xMin: 100,
  yMin: 200,
  xMax: 500,
  yMax: 600,
});

// k-NN query: the 5 closest points to the cursor
const nearest = queryNearest(tree, cursorX, cursorY, 5);

// indices / nearest are Uint32Arrays, map them back to your data
```

For fixed-radius queries (brush selection, find-neighbors-within-r), use a hash grid instead:

```ts
import { buildHashGrid, hashGridQueryRadius } from "@vizcrush/spatial";

const grid = await buildHashGrid(x, y, { cellSize: 20 });
const neighbors = hashGridQueryRadius(grid, cursorX, cursorY, 15);
```

The right index depends on the query pattern, see the decision tree in chapter 12.

## Step 5: Stream Live Data Without Re-scanning

For a live dashboard, two things matter: rolling stats that update in O(1), and a chart that stays smooth as new batches arrive.

```ts
import { streamingStats, appendAndDownsample } from "@vizcrush/aggregate";

const stats = streamingStats(20_000); // rolling window of 20K values
const displayBuffer = new Float64Array(20_000);
let displayCount = 0;

function onNewBatch(newValues: Float64Array) {
  // Update running min / max / mean / stddev in O(1) per value
  stats.push(newValues);

  console.log(stats.mean, stats.stdDev, stats.min, stats.max);

  // Append to the rolling display buffer and downsample in one call
  const out = appendAndDownsample(
    displayBuffer,
    displayCount,
    newValues,
    20_000, // max buffer size
    1920 // display-point count
  );

  // out.buffer is the new rolling buffer state
  // out.downsampled is ready to render
  displayCount = out.count;

  chart.update(out.downsampled);
}
```

The point of `appendAndDownsample` is that it's a _single pass_, append, evict, and LTTB in one operation with no intermediate allocations. The GC has nothing to do. 60fps streaming charts become boring to build.

## Step 6: Percentiles on a Stream

Live SLA monitoring, p50, p95, p99 over the rolling window:

```ts
import { DDSketch } from "@vizcrush/aggregate";

const sketch = new DDSketch(0.01); // 1% relative error

function onLatencyBatch(latencies: Float64Array) {
  for (const lat of latencies) sketch.add(lat);

  const p50 = sketch.quantile(0.5);
  const p95 = sketch.quantile(0.95);
  const p99 = sketch.quantile(0.99);

  chart.updateBands({ p50, p95, p99 });
}
```

`DDSketch` gives relative-error guarantees, ideal when latencies span microseconds to seconds. For general percentile work without the relative-error story, `KllSketch` is the same API.

For cardinality ("how many distinct users"), use `HyperLogLog` the same way:

```ts
import { HyperLogLog } from "@vizcrush/aggregate";

const hll = new HyperLogLog(14); // precision → ~0.8% error
for (const userId of newUsers) hll.add(userId);
console.log("approx distinct:", hll.estimate());
```

## Step 7: Transforms Before Plotting

Log-scaling a million points in JavaScript is the kind of thing that makes a chart feel sluggish. Do it in WASM instead:

```ts
import { log10Transform, normalize } from "@vizcrush/transform";

const logY = log10Transform(y);           // NaN for non-positive values
const scaled = normalize(logY);           // min-max to [0, 1]

chart.setData({ x, y: scaled });
```

Every transform takes a `Float64Array`, returns a `Float64Array`. No in-place mutation, no surprises.

## Step 8: 3D Point Clouds

Voxel binning for a density field:

```ts
import { bin3d } from "@vizcrush/bin3d";

const grid = await bin3d(x, y, z, {
  xBins: 64,
  yBins: 64,
  zBins: 64,
});
// grid.counts is a Float64Array of length 64 * 64 * 64
```

Octree + frustum culling for an interactive viewer:

```ts
import { buildOctree, queryRange3d } from "@vizcrush/spatial3d";
import { cullByFrustum } from "@vizcrush/spatial3d";

const octree = await buildOctree(x, y, z);

// Every frame, given the current camera:
function renderFrame(viewProj: Float32Array) {
  // Step 1: reject everything outside the frustum (cheap pre-filter)
  const visibleIndices = cullByFrustum(x, y, z, viewProj);

  // Step 2: render the surviving points, use octree for hover picking
  renderer.draw(visibleIndices);
}
```

The culling step is the win. You can render 20M-point scans at 60fps because 95% of the points never reach the GPU pipeline.

## Step 9: Let the Library Decide

If you're not sure which algorithm to pick, or you're building an agent that needs to decide for itself, call `autoConfig`:

```ts
import { autoConfig } from "@vizcrush/ai";

const recommendation = autoConfig(x, y, { targetWidth: 1920 });

console.log(recommendation);
// {
//   algorithm: "minmax_lttb",
//   targetPoints: 1920,
//   binResolution: 128,
//   spatialIndex: "quadtree",
//   estimatedSpeedup: 42.3,
//   reasoning: "Data has spikes (3.2% outliers at 2σ); MinMaxLTTB preserves them."
// }
```

The `reasoning` field is the interesting part, it's a short human-readable string explaining why the recommendation is what it is. You can show it to a user, feed it to an LLM, or ignore it. Everything else is a drop-in parameter for the actual algorithm calls.

For a quick summary of any dataset:

```ts
import { summarize, detectAnomalies, computeShapeVector } from "@vizcrush/ai";

const summary = summarize(y);
// { count, mean, stdDev, min, max, median, skewness, kurtosis }

const anomalies = detectAnomalies(y, 3.0);
// Float64Array of [index, value, score, ...]

const shape = computeShapeVector(y, 16);
// Float64Array of 16 features, cosine-similar to "similar" charts
```

## Step 10: React Hook

For React users, `@vizcrush/react` wraps the common patterns:

```tsx
import { useDownsample } from "@vizcrush/react";

function Chart({ rawX, rawY }: { rawX: Float64Array; rawY: Float64Array }) {
  const { data, isLoading } = useDownsample(rawX, rawY, {
    algorithm: "auto",
    targetPoints: 1920,
  });

  if (isLoading) return <div>Downsampling…</div>;
  return <LineChart data={data} />;
}
```

The hook handles:

- Calling `init()` once and reusing the context
- Re-running the downsample when inputs change
- Suspending on the WASM load
- Cleaning up GPU buffers on unmount

If you're not using React, the vanilla API above is all you need, the hook is a convenience, not a requirement.

## The Mental Model

Every vizcrush function follows the same shape:

1. **Input**: one or more `Float64Array` (or equivalent typed array). Contiguous memory, no objects, no per-point allocations.
2. **Output**: another `Float64Array` (or a small handle for things like spatial indexes). Same contract.
3. **No rendering**: vizcrush never touches the DOM, the canvas, or the chart library. You pass the output to your renderer of choice.

Once you internalize this, every new algorithm in the library fits the same template. `bin1d` takes an array, returns an array. `lttb` takes arrays, returns arrays. `compute_shape_vector` takes an array, returns an array. You never wrestle with object models or configuration schemas, typed arrays all the way down.

The next time you find yourself about to write `for (let i = 0; i < 500_000; i++)` in JavaScript, stop. Check this book's decision chapter. There's probably a vizcrush function that already did the work, faster, without blocking your main thread.

The remaining three chapters are for the curious: how vizcrush stays working when the hardware doesn't cooperate, the performance lessons I learned the hard way, and, for anyone who wants to dig into the math, a reference of the formulas behind the algorithms.
