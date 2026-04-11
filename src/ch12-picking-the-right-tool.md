# Picking the Right Tool

> **TL;DR** — A flowchart from "what are you trying to do?" to "here's the function to call." Bookmark this chapter. You'll come back to it more than any other.

You've now seen everything vizcrush ships: four downsamplers, three binning strategies, four spatial indexes, seven streaming sketches, five transforms, three 3D primitives, four AI utilities. That's a lot of functions. The question this chapter answers is: **which one do you actually reach for, when?**

If you're already an expert and you just want the flowchart, skip ahead to the end of the chapter. If you want to understand _why_ the flowchart looks the way it does, read straight through — every branch in the tree maps back to a decision we made for a real reason.

## The Three Questions

Before you pick any algorithm, answer three questions about your data. The answer to each one eliminates whole categories of tools.

**Q1: Is the data one-shot or streaming?**

- **One-shot**: you have a fixed dataset on disk or in memory, and you want to render it. You're going to call a function once per zoom level. → Use the _batch_ primitives.
- **Streaming**: data arrives continuously and you want the chart to keep up at 60fps. You'll call a function many times per second. → Use the _streaming_ primitives (chapter 8) and `appendAndDownsample` specifically.

**Q2: What's the underlying structure?**

- **Time series**: x-axis is time or some other monotonic ordering. You want to see shape over time.
- **Scatter**: x and y are independent features. You want to see clusters and density.
- **Spatial**: x and y (and maybe z) are positions. You want to query points by region or proximity.
- **Categorical / distribution**: you care about "how many of each" or "what does the distribution look like" rather than individual points.

**Q3: What matters most to the viewer?**

- **Overall shape** (trends, seasonality)
- **Extreme values** (spikes, crashes, anomalies)
- **Exact extremes** (compliance, audit trails)
- **Density** (clusters, overlaps)
- **Specific points** (hover, selection)

Three questions, three axes. Every algorithm in vizcrush lives at some point in that space.

## The Decision Tree

```
Is it streaming?
├─ YES  → ch 8. Use StreamingStats + appendAndDownsample.
│         ├─ Need variance/std_dev?          → Welford
│         ├─ Need percentiles?
│         │    ├─ p50-p95, general use       → t-digest
│         │    ├─ p99.9+ for SLA             → DDSketch (relative-error)
│         │    └─ Need formal error bound    → KLL
│         ├─ Need cardinality (distinct)?    → HyperLogLog
│         ├─ Need frequency (heavy hitters)? → Count-Min Sketch
│         └─ Need a uniform random sample?   → Reservoir sampling
│
└─ NO (one-shot)
   │
   What's the structure?
   │
   ├─ Time series? (x is monotonic)
   │    │
   │    What matters most?
   │    ├─ Smooth shape, no spikes           → LTTB
   │    ├─ Spikes matter (finance, IoT)      → MinMaxLTTB
   │    ├─ Exact extremes required           → M4
   │    └─ Speed over quality                → LTOB
   │
   ├─ Scatter / density?
   │    │
   │    What dimension?
   │    ├─ 2D density heatmap
   │    │    ├─ Fast                         → bin2d (rectangular)
   │    │    └─ Visually uniform             → hexbin
   │    ├─ 1D histogram                      → bin1d
   │    └─ 3D density / point cloud          → bin3d (voxel)
   │
   ├─ Spatial queries?
   │    │
   │    What query pattern?
   │    ├─ Viewport / range (zoom/pan)       → quadtree
   │    ├─ Hover picking (k-NN)              → kd-tree
   │    ├─ Fixed-radius brush / lasso        → hash grid
   │    ├─ GPU-built structure               → Morton codes
   │    └─ Any of the above, but 3D          → octree (+ frustum)
   │
   ├─ 3D with a camera?
   │    └─ Cull before anything else         → frustum (+ octree)
   │
   └─ Distribution / categorical?
        ├─ Histogram of values               → bin1d
        ├─ Multiple distributions side by side → quantile_normalize
        └─ Just summary statistics           → summarize
```

Keep this diagram nearby. Almost every question someone asks me reduces to a path through it.

## The Canonical Scenarios

Let's walk through seven real situations and see how the tree resolves them. These are the actual questions I get asked.

### Scenario 1: "My dashboard has 10M rows of server CPU usage over a month. It freezes."

**Questions**: one-shot (fixed dataset), time series (x is timestamp), shape matters (trends), maybe spikes too (for incidents).

**Path**: one-shot → time series → spikes matter → **MinMaxLTTB** with `target_points ≈ chart_width` (so ~1920 for a desktop chart, ~800 for a mobile one).

**Why not LTTB**: server CPU has spikes you care about (load surges, GC pauses). LTTB smooths them.

**Why not M4**: overkill. M4 returns 4× the points for not much visual gain at this density.

### Scenario 2: "I have a live feed of 1,000 metrics/second and I want to show the last 10 minutes with running stats."

**Questions**: streaming (live feed), time series, shape + summary stats.

**Path**: streaming → `StreamingStats` for running mean/std/min/max, `appendAndDownsample` for the chart.

**Why not "just use LTTB every second"**: you'd re-scan the entire buffer on every tick. `appendAndDownsample` is specifically designed to avoid the double pass — it combines the append, the eviction, and the LTTB in a single operation with no intermediate allocation.

**Add a t-digest or DDSketch** alongside if the user also wants to see p50/p95/p99 bands.

### Scenario 3: "My 500K-point scatter plot shows 10 dots when it should show clusters."

**Questions**: one-shot, scatter, density matters.

**Path**: one-shot → scatter → density → **bin2d** at 128×128. Color-map the result to show the density field.

**If the clusters look square/blocky**: switch to **hexbin**. Hexagons have equidistant neighbors, so round clusters render as round clusters instead of square ones.

**Also**: build a quadtree on the raw points if users will want to pick individual points after seeing the heatmap.

### Scenario 4: "I need to show the 99th percentile of API latency over the last hour, and it has to stay accurate as new data streams in."

**Questions**: streaming, percentiles, specifically p99, latency (log-scaled).

**Path**: streaming → percentiles → p99 on latency → **DDSketch** with `α = 0.01` (1% relative error).

**Why DDSketch and not t-digest**: DDSketch's relative-error guarantee means "1% of the true value" whether latency is 5ms or 5 minutes. t-digest's accuracy is _absolute_ and degrades on log-scaled data.

**Why not KLL**: KLL is great when you need a formal worst-case bound for a paper. For SLA monitoring, DDSketch's practical behavior is better.

### Scenario 5: "I want to show which genes are 'unique' in a 100-sample × 50K-gene expression matrix."

**Questions**: one-shot, matrix (multi-distribution), shape comparison.

**Path**: one-shot → multiple distributions → **quantile_normalize** to make samples comparable, then compute per-row summary statistics for ranking.

**Why not plain normalization**: min-max scales to the same range but doesn't align shapes. Two samples with identical sort orders can have completely different min-max normalized values. Quantile normalization forces both samples into the same distribution shape, so a rank of "5th highest" maps to the same value in every sample.

### Scenario 6: "I have a LIDAR scan with 20M points and I'm rendering a first-person fly-through."

**Questions**: one-shot dataset but interactive rendering, 3D, camera-aware.

**Path**: one-shot → 3D → camera-aware → **frustum cull first** (prune to the ~5% visible on each frame), then query an **octree** built over the surviving points for hover picking and distance-based LOD.

**Don't voxelize** unless you also want a density heatmap. The raw points are what you want to render; culling + indexing is what keeps it fast.

**Memory tip**: build the octree once. Rebuild it only when the underlying point cloud changes (on new LIDAR sweeps), not on every frame.

### Scenario 7: "An LLM agent is asking about my data and I don't want to stream 10MB of raw numbers to it."

**Questions**: one-shot, any shape, needs compressed representation.

**Path**: call **`summarize`** and **`compute_shape_vector`** (chapter 11). Feed the resulting 8–32 floats to the model instead of the raw data. If the model asks "are there anomalies," also call **`detect_anomalies`** and pass the flagged indices.

**Also consider `auto_config`**: it'll give the model a structured recommendation it can apply or override. The `reasoning` field is a short human-readable string — ideal for prompt injection into the assistant's context.

## Parameter Guidance

The decision tree tells you _which_ algorithm. The next question is _with what parameters_. Short answers here; longer notes inline throughout the book.

### Downsampling

- **`target_points`** — start with chart width in pixels (~1920 for desktop, ~800 for mobile). Double it for retina displays if you want extra margin for sharp lines.
- **MinMaxLTTB bucket multiplier** — the default 4× is almost always right. Higher preserves more spikes but slows things down.

### Binning

- **`bins`** — target a density where most cells have >5 points. For 500K points, 128×128 is a good start. For 50K, try 64×64.
- **`3D bins`** — start at 64³ or less. Memory scales cubically.

### Spatial indexes

- **Quadtree leaf size** — 64. Don't touch unless you're building a specialized tool.
- **Hash grid cell size** — match your typical query radius. Slightly larger is safer than slightly smaller.

### Streaming sketches

- **HyperLogLog precision `p`** — 14 gives ~0.8% error using 16KB. Drop to 12 for ~1.6% error using 4KB if memory is tight.
- **KLL `k`** — 200 gives ~1% rank error. 400 for ~0.5%.
- **DDSketch `α`** — 0.01 (1% relative error) for most latency work. 0.005 if you're obsessive.
- **t-digest compression** — 100 is fine for most dashboards. 200 if you care about p99.9.
- **Count-Min Sketch (width, depth)** — (1024, 5) is the default and handles "what are the top-k heavy hitters" for millions of distinct keys.

### AI utilities

- **Anomaly sensitivity** — 3.0 (modified z-score equivalent of 3σ). Raise to 4–5 to reduce false positives; lower to 2 to catch softer anomalies.
- **Shape vector dimensions** — 16 to 32. More dimensions capture more nuance but make comparison noisier.

## A Two-Line Summary

Most problems in visualization fall into one of two buckets:

1. **Too much data for the screen** — downsample, bin, or sketch.
2. **Too much data for the query** — index it (quadtree, kd-tree, hash grid, octree) or cull it (frustum, range filter).

Almost every algorithm in this book is a specific answer to one of those two problems. When you're stuck, start with that framing and pick the tool that matches your structure.

Everything else is parameters.

The flowchart tells you _what_. The next chapter tells you _how_ — with real code, real imports, and real API calls you can copy and paste.
