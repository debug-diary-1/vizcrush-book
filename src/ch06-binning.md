# Binning: When Scatter Plots Lie To You

> **TL;DR** — A scatter plot of a million points looks the same as ten. Binning turns the overlap problem into a density heatmap — and reveals the clusters that were hiding all along.

Pour a glass of water into a second glass that already has water in it. Now tell me how much water is in the second glass.

You can't, really. Once the water mixes, there's no "this is the new water, this is the old water." Scatter plots have the same problem: once two dots land on the same pixel, the pixel has no idea whether it's holding two points or two thousand. The canvas loses information the moment the pen touches it.

The consequence is surprisingly ugly. A scatter plot with 500K points can look _identical_ to one with 5K points — the middle fills up with ink, and visual density goes to maximum everywhere there's data. Real clusters are invisible. Real gaps are invisible. Your chart is a Rorschach test.

Binning is the fix. Instead of plotting dots, we count them — and then we plot the counts.

## 1D: The Humble Histogram

The simplest bin: divide a range into N equal segments, count how many values fall in each.

```
Range [0, 100], 10 bins:
  Bin [0-10):  45 values   ████████████████
  Bin [10-20): 12 values   ████
  Bin [20-30):  8 values   ███
  ...

Just division and counting. O(n), single pass.
```

The only tricky part is edge cases: what happens when a value equals the maximum? It would compute `bin_index = num_bins`, which is out of bounds. We clamp it to `num_bins - 1`. This puts the max value in the last bin, which is the least surprising behavior.

## 2D: Density Grids

bin2d extends this to two dimensions. The output is a flat grid:

```
grid[row * num_cols + col] = count of points in that cell
```

For a 128×128 grid, you get 16,384 cells. Each cell holds a count. You can color-map these counts to produce a heatmap — suddenly those invisible overlapping dots reveal clusters, corridors, and density gradients.

This is where the GPU shines. Each input point's bin assignment is independent of every other point. A WebGPU compute shader dispatches one thread per point:

```wgsl
let xi = u32((px - x_min) / x_range * f32(x_bins));
let yi = u32((py - y_min) / y_range * f32(y_bins));
atomicAdd(&grid[yi * x_bins + xi], 1u);
```

The `atomicAdd` is essential. Multiple GPU threads might try to increment the same cell simultaneously. Without atomic operations, you'd get race conditions — lost counts, corrupted data. `atomicAdd` guarantees correctness at the cost of slight serialization when threads collide on the same cell (rare in practice with 16K+ cells).

## Hexagonal Binning

If you put a rectangular grid on a scatter plot, you get visual artifacts at the corners. Diagonal neighbors of a square are √2 times farther than edge neighbors, which creates directional bias — clusters look square instead of round.

Hexagons fix this. Every neighbor of a hex is equidistant. The grid tiles the plane more uniformly, and the resulting heatmap looks more natural.

The coordinate math is a bit more involved — you need to account for alternating row offsets — but the binning logic is the same: compute which hex center is closest, increment its count.

Binning turns a wall of overlapping dots into a legible density field. But sometimes you don't want a summary — you want to interrogate specific points. "Which of these points is under my cursor?" "Give me everything in this viewport." That's the job of the next chapter.
