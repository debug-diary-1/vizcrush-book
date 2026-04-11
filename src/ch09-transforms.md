# Sorting, Normalizing, Filtering, Reshaping — The Grunt Work

> **TL;DR** — The unglamorous operations that show up in every chart pipeline: sort a million numbers, rescale to [0,1], clip to a viewport, switch to a log axis, align distributions. Each one gets a tight, boring, fast implementation — and the chapter explains the small tricks that make "boring" ten times faster than the obvious approach.

Every glamorous algorithm in this book sits on top of a pile of unglamorous ones. Before LTTB can pick the best points, someone has to hand it data that's sorted by time. Before a heatmap can be color-mapped, someone has to normalize the counts to [0, 1]. Before a chart can zoom, someone has to filter out everything outside the viewport. Before a log-scaled axis can render, someone has to compute a million logarithms.

These are the operations that nobody talks about at conferences. They're the plumbing under the bathroom floor. And, like plumbing, they're invisible when they work and catastrophic when they don't.

This chapter is about the plumbing.

## Radix Sort: O(n) Beats O(n log n)

JavaScript's `Array.sort()` uses TimSort — comparison-based, O(n log n). For numeric data, we can do better.

Radix sort processes numbers digit by digit, from least significant to most. No comparisons needed — just counting occurrences of each digit and redistributing. For 8-byte floats, that's 8 passes of O(n) each, giving O(n) total.

There's a fun trick for sorting floats: IEEE 754 doubles don't sort correctly as raw bits because negative numbers use sign-and-magnitude representation. The fix is a two-line bit hack:

```
to_sortable(v):
  bits = raw 64-bit representation of v
  if sign bit is 1 (negative): flip all 64 bits
  else (positive):             flip only the sign bit
```

After this transformation, the bit patterns sort in the same order as the float values. Radix sort on the transformed bits, then invert the transformation to get the original values back.

## Normalization

Min-max normalization scales values to [0, 1]:

```
normalized = (value - min) / (max - min)
```

Dead simple, but it shows up in every heatmap color-mapping, every scatter plot size encoding, every gradient computation. We pre-compute `1.0 / (max - min)` and multiply instead of dividing in the loop — division is ~10x slower than multiplication on most hardware.

## Range Filtering

When the user zooms to a viewport [xMin, xMax], we need to extract just those points. For unsorted data, it's a linear scan (O(n)). For sorted time-series (which is the common case), we binary search for the start and end indices (O(log n)) and return a slice — no copying at all.

## Log and Power Transforms

A scatter plot of file sizes, request latencies, or cryptocurrency market caps will always look the same: a few huge values dominate the top, and 99% of the data is squashed into the bottom 5% of the chart. The fix is changing the axis scale instead of changing the data — but the chart library still has to compute log values for every point, often in JavaScript, often on every redraw.

vizcrush moves that work into the compute layer: `log_transform`, `ln_transform`, `log10_transform`, and `power_transform` each map an input array to an output array in a single SIMD-friendly pass. The result is a `Float64Array` you hand to your chart library on a linear axis — the math has already happened.

The algorithm is obvious. The only trick worth mentioning: for an arbitrary-base logarithm, compute `ln(base)` _once_ outside the loop and multiply by its reciprocal per element. Natural log is expensive, and computing it once instead of once per element is the kind of change that costs nothing and pays back forever.

Non-positive inputs become `NaN`, not an error and not a silent zero. NaN propagates through the chart library as a gap, which is exactly what should happen for log(−1).

Power transforms apply the same SIMD batching. A million-point square-root transform is around half a millisecond on the WASM path.

## Quantile Normalization

### The Core Idea, Told With Class Rankings

Imagine two classrooms in two different countries, each with 30 students, each with their own English test scores. Class A has scores from 60 to 95. Class B has scores from 40 to 85. A student with a score of 78 in Class A is the "10th best" in that class. A student with a score of 72 in Class B is _also_ the 10th best.

If you want to fairly compare "how good is each student relative to their classmates," raw scores won't work — the tests weren't the same, the grading wasn't the same. What _does_ work is comparing _ranks_. "10th best" means the same thing in both classes, regardless of scale.

Quantile normalization takes this idea and goes one step further. It doesn't just compare ranks — it _rewrites_ every score so that students of the same rank across classes end up with the same number. The 10th-best student in both classes gets the _average_ of the two 10th-best scores. The 1st-best students get the average of the two top scores. And so on.

After this rewrite, the two classes have _identical_ distributions — the same set of sorted scores — but each student's _position_ in their own class is preserved. You've made the two classes directly comparable without distorting their internal rankings.

### Why Anyone Cares

This trick was invented for gene-expression data. Biologists run experiments where each "column" is a different biological sample (a person, a tissue, a mouse) and each "row" is a different gene. The raw expression values can't be compared directly across samples because each sample was measured on its own noisy scale. Quantile normalization makes them comparable by forcing every sample to share the same global distribution of values, while preserving the _relative_ ordering of genes within each sample.

It's narrow-sounding until you realize how often the same problem shows up elsewhere: A/B-test metrics from different buckets that had different baseline behavior, per-user activity data where user sizes differ wildly, time-series from sensors with different calibrations. Anywhere you want to say "let's pretend these all came from the same underlying distribution and just compare ranks" — quantile normalization is your friend.

### The Algorithm

```
1. Sort each column independently. Remember each value's original row index.
2. For each rank position r, compute the mean of all columns' values at that rank.
   Call the result rank_means[r].
3. Replace each value in each column with rank_means[r], where r is that
   value's rank within its own column.
```

Three steps, one slightly slippery catch: NaN handling. If a column has missing values, they sort to the _end_ (not the start, which would corrupt everything), and any rank position where even one column has a NaN produces a NaN rank mean. Missing data stays missing — the algorithm doesn't silently invent numbers for it.

Complexity is O(n_cols · n_rows · log n_rows) for the sorts, O(n_cols · n_rows) for the rest, and the memory footprint is one additional matrix the same size as the input. For a 50,000 × 100 expression matrix — a realistic gene-expression dataset — WASM runs this in tens of milliseconds. Pure JavaScript takes seconds. This is exactly the kind of operation that makes the WASM port pay for itself on the first call.

So that's the two-dimensional world taken care of. What happens when your data has a third dimension, a camera moving around it, and a visibility problem that doesn't exist in flat space? That's what the next chapter is about.
