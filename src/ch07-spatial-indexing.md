# Quadtrees, kd-trees, Hash Grids: Finding Needles Fast

> **TL;DR**: When the user hovers a mouse over a million points, you can't check all million in time. Spatial indexes organize points so most of them get skipped without ever being examined.

Think about how you'd find a book in a physical library. You don't scan every spine on every shelf, that would take days. You walk to the section labeled "Fiction," then "F," then "Fitzgerald." Each step cuts the search space by a huge factor. By the time you've taken three steps, you're looking at a dozen books instead of a hundred thousand.

Spatial indexes are libraries for points. Before you query anything, you spend some time organizing the data into a hierarchy, each level narrower than the last. When a query comes in, "what's under the cursor?", you walk that hierarchy the same way you walked the library. Most of the data gets eliminated before you look at it.

This chapter covers four ways to build that library: quadtrees, kd-trees, spatial hash grids, and Morton codes. They're all solving the same problem with different tradeoffs.

## Quadtree: Divide and Conquer in 2D

A quadtree recursively splits 2D space into four quadrants. You keep splitting until each leaf holds a manageable number of points (we use 64 as the threshold).

```
Level 0:  One node covering the entire space
Level 1:  Four quadrants (NW, NE, SW, SE)
Level 2:  Sixteen sub-quadrants
Level 3:  Sixty-four regions
...
Level 12: Up to 16 million regions (max depth)
```

**Range query** (find all points in a viewport):

Start at the root. If the viewport doesn't intersect this node's bounds, skip the entire subtree. You just eliminated a quarter of the data in one comparison. If the viewport fully contains the node's bounds, return all points in the subtree without checking individually. Otherwise, recurse into children and check individual points.

For a viewport showing 1% of the total area, this typically examines about 3-5% of the tree nodes, skipping the other 95%. On a million points, instead of checking all million, you check maybe 50K. That's the difference between 1ms and 50 microseconds.

**Building the tree** costs O(n log n) but you only do it once. Queries are O(log n + k) where k is the number of results.

## kd-tree: Better for Nearest Neighbors

A kd-tree splits space along alternating axes. Level 0 splits on X at the median. Level 1 splits on Y. Level 2 splits on X again.

The key advantage over quadtrees: kd-trees partition at the _median_, creating balanced trees. Quadtrees partition at the spatial center, which creates unbalanced trees when points cluster.

For k-nearest-neighbor queries (hover tooltips), kd-trees are faster because the binary structure allows tighter pruning. You search the closer child first, establish a candidate distance, then only search the farther child if the splitting plane is closer than your current best, which it usually isn't.

## Morton Codes: GPU-Friendly Spatial Ordering

### The Core Idea, Told With a Road Trip

Suppose you want to visit every house in a city in some reasonable order, not randomly bouncing around, but walking neighboring houses in sequence. A good order would be: finish this block, finish the next block, finish the quadrant, move to the next quadrant. You want a path where consecutive stops are physically close to each other.

That path exists, and it looks like a jagged "Z" repeated at every scale, inside each quadrant, inside each sub-quadrant, all the way down. Mathematicians call it the **Z-order curve**. Drive along it and you visit every location exactly once, with each consecutive pair close to each other.

Morton codes are the _addresses_ along that Z-shaped path. If you assign each 2D point a Morton code, then sort all your points by Morton code, your data magically arranges itself so nearby points sit next to each other in the array. You just turned a 2D spatial problem into a 1D sorting problem, and 1D sorting is something GPUs are phenomenally good at.

### How You Compute One

The trick for turning an `(x, y)` pair into a single number is surprisingly simple: interleave the bits of x and y. Take x's bits and shift them so they sit in the even positions of the output. Take y's bits and shift them into the odd positions. Merge.

```
x = 5  →  binary 101
y = 3  →  binary 011

Interleaved: (x bits in even positions, y bits in odd positions)
             1 0 1 0 1 1 → 101011
             ↑   ↑   ↑
             x   x   x
```

The resulting number has the beautiful property that points which are close in 2D are _mostly_ close in Morton order (the Z-curve has a few long jumps at quadrant boundaries, but they're rare). Close enough, in any case, that sorting by Morton code gets you a tree-building-friendly ordering for free.

### Why This Matters on the GPU

Building a traditional quadtree on the GPU is a nightmare. Tree construction is recursive, and GPUs hate recursion: they want every thread to do the same work on different data in parallel. Morton codes turn the problem into two operations both GPUs love: compute a code for each point (one thread per point, no coordination), then parallel-sort the results.

vizcrush runs the Morton-code step as a compute shader: each GPU thread processes one point, computes its Morton code, and writes it to an output buffer. No synchronization needed. Zero communication between threads. It's the textbook definition of "embarrassingly parallel", and embarrassingly parallel is what GPUs are for.

## Spatial Hash Grid: When You Don't Want a Tree

Trees are great, but they have two costs that hurt for certain workloads. They take O(n log n) to build, and every query walks a hierarchy of nodes. If your data is roughly uniform and your query radius is roughly the same size every time, think "find all neighbors within 5 pixels of the cursor" or "which points are inside this brush stroke", you can do better with no tree at all.

A spatial hash grid divides 2D space into fixed-size cells. Each cell holds a list of point indices. There's no hierarchy, no recursion, no balancing. Insertion is O(1) per point:

```
cx = floor(x / cell_size)
cy = floor(y / cell_size)
key = hash(cx, cy)
cells[key].append(point_index)
```

The cell hash combines `cx` and `cy` into a single 64-bit key using two large primes. This is the standard trick from Teschner's "Optimized Spatial Hashing":

```
hash(cx, cy) = (cx · 73856093) XOR (cy · 19349663)
```

The primes are chosen so that nearby cells get very different hash values, distributing them evenly across the underlying hash table. No clustering, no resize storms.

**Radius queries** are stupidly direct: compute which cells the query circle overlaps, iterate over their indices, and reject points that are inside the bounding box but outside the actual radius. For a query radius matched to the cell size, you visit at most 9 cells (3×3) regardless of how many points you've inserted. A million-point dataset answers a "neighbors within r" query in tens of microseconds.

**The catch**: hash grids fall over when the radius is much larger or smaller than the cell size. Query radius >> cell size means you visit thousands of cells. Query radius << cell size means each cell holds way more candidates than you actually need. The cell size has to be tuned to the query pattern. If your queries are heterogeneous (sometimes brushing 5 pixels, sometimes selecting a viewport), use a kd-tree instead. If they're homogeneous, the hash grid will smoke any tree.

## Picking the Right Spatial Index

| Workload                                | Use this         |
| --------------------------------------- | ---------------- |
| Viewport range queries (zoom/pan)       | quadtree         |
| Hover tooltip (1-NN, k-NN)              | kd-tree          |
| Fixed-radius neighborhood, brush, lasso | hash grid        |
| GPU-built spatial structure             | Morton (Z-order) |

All four of these structures assume your data just _is_, a fixed set of points sitting still. But in the real world, new data arrives every second and old data ages out. That's a different world, and it has its own set of algorithms. Turn the page.
