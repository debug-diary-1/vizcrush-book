# 3D: Voxels, Octrees, Frustum Culling

> **TL;DR** — Three dimensions break things in two ways. Memory scales worse, and the camera introduces a whole new problem: _visibility_. This chapter is the 3D dialect of everything you learned in chapters 6 and 7, plus a new trick (frustum culling) that only makes sense once you have a camera.

The moment your data has a third dimension, every technique from earlier in the book needs a parallel story. A 2D scatter plot becomes a point cloud. A quadtree becomes an octree. Binning becomes voxelization. And there's one entirely new concept — frustum culling — that doesn't exist in 2D because 2D has no camera.

This chapter covers the three 3D primitives vizcrush ships: `bin3d` (voxel binning), `octree` (3D spatial index), and `frustum` (camera-aware culling).

## Why 3D Is Harder

Two reasons, both of them about scaling.

**Memory scales as N³, not N²**. A 128×128 grid has 16K cells. A 128×128×128 voxel grid has 2 _million_ cells. Double the resolution and you 8× the memory. You cannot naively scale up what worked in 2D — the bookkeeping cost grows faster than the data.

**Visibility is a first-class concern**. In a 2D chart, everything you care about is on the canvas at once. In a 3D scene, the camera looks at a specific region; everything outside that region is invisible and should never be processed. Skipping invisible points before you do anything else is often a bigger win than any algorithmic cleverness on the visible ones.

## Voxel Binning: 2D Binning in Three Dimensions

A voxel is a 3D pixel. You define a bounding box, divide it into an `x_bins × y_bins × z_bins` grid, and count how many input points fall into each cell. The output is a flat array of length `x_bins · y_bins · z_bins` — indexed linearly as `grid[z · y_bins · x_bins + y · x_bins + x]`.

The algorithm is exactly what you'd expect from 2D binning with one more axis:

```
for each point (px, py, pz):
    xi = floor((px − x_min) / x_range · x_bins)
    yi = floor((py − y_min) / y_range · y_bins)
    zi = floor((pz − z_min) / z_range · z_bins)
    clamp xi, yi, zi to [0, bins − 1]
    grid[zi · y_bins · x_bins + yi · x_bins + xi] += 1
```

The output also carries the bin edges (`x_edges`, `y_edges`, `z_edges`) appended to the grid so the caller can label axes or map voxels back to world coordinates without recomputing anything.

**Auto-ranging**: pass `NaN` for any min/max and vizcrush derives it from the data in one pass. This is the common case — you rarely know your exact data bounds ahead of time, and forcing the caller to compute them just to call the binning function is exactly the kind of friction that makes people write their own janky version.

**Use cases**:

- **LIDAR / point clouds**: reduce millions of raw scan points to a dense voxel grid you can ray-march or render directly.
- **Molecular dynamics**: count how often atoms occupy each region of a simulation box to produce a probability density.
- **Medical imaging**: re-bin scattered samples onto a uniform grid for volume rendering.
- **Any 3D histogram**: the "scatter plots lie" problem from chapter 6 is twice as bad in 3D because depth overlap masks density even more aggressively.

**A warning about resolution**: picking `x_bins = y_bins = z_bins = 256` sounds reasonable until you realize you just allocated 16 million `f64` cells — 128 MB of RAM — before putting a single point in. For 3D, **start with resolution around 64 per axis and go up only if you have a reason**. A 64³ grid is 262K cells, fits comfortably in L2 cache, and renders beautifully for most point clouds.

## Octree: Quadtree's 3D Cousin

An octree splits 3D space into eight children at each level instead of four. The naming convention matches the sign of each axis in the parent's local frame:

```
Child 0: −x −y −z    Child 4: −x −y +z
Child 1: +x −y −z    Child 5: +x −y +z
Child 2: −x +y −z    Child 6: −x +y +z
Child 3: +x +y −z    Child 7: +x +y +z
```

Everything you learned about quadtrees in chapter 7 translates directly: build cost is O(n log n), range queries prune whole subtrees, nearest-neighbor queries walk the closer child first. The math is the same, there's just one more axis to partition on.

vizcrush's octree uses two implementation details worth calling out:

**Arena allocation, not pointer trees.** Every node lives in a single flat `Vec<OctNode>`. Children are referenced by index into the arena, not by pointer. This is a huge cache-locality win — walking the tree touches contiguous memory, and serializing the whole tree is a single memory copy. It's also essential for passing the tree across the WASM boundary without rebuilding it on each side.

**Partitioned index array.** Points aren't duplicated into leaf nodes. Instead, each node owns a `[start, end)` slice into a single shared `indices: Vec<u32>` array. Building the tree is essentially an in-place partial sort — points get reordered so that every subtree's points live in a contiguous run. Queries iterate those runs directly. No pointer chasing, no scattered reads.

**The thresholds**: leaf nodes hold up to 64 points, maximum depth is 12. These come from the same reasoning as the quadtree — 64 is small enough that brute-force comparison in a leaf is cheap, and depth 12 (roughly 68 billion maximum cells) is way more than anyone needs but keeps pathological clustered inputs from blowing the stack.

**When to use an octree vs. a voxel grid**:

- Voxel grid: you want to know _density_ per region. Memory is fixed by resolution, not by point count.
- Octree: you want to _query_ points — "all points inside this box," "k nearest to this cursor ray," "which points are inside this selection volume." Memory is fixed by point count, not by resolution.

If your use case is "show me a heatmap of density" → voxel. If it's "let the user hover and pick" → octree. If it's both, build both — they're cheap and they solve different problems.

## Frustum Culling: Don't Process What You Can't See

A camera in 3D doesn't see all of space. It sees a _frustum_: a truncated pyramid with six boundary planes (near, far, left, right, top, bottom). Anything outside those six planes is invisible, and any compute you spend on it is wasted.

Frustum culling is the operation of testing each point against those six planes and keeping only the ones inside. It's conceptually the 3D equivalent of range filtering from chapter 9, but with an important twist: the "range" is defined by six tilted planes rather than two axis-aligned intervals, and the planes change every time the camera moves.

### The Math

A plane in 3D is defined by the equation `a·x + b·y + c·z + d = 0`. The vector `(a, b, c)` is the plane's normal direction, and `d` shifts the plane along that normal. For any point `P = (px, py, pz)`, the signed distance from the plane is:

```
dist(P) = a · px + b · py + c · pz + d
```

If we choose the convention that positive distance means "inside the frustum," then a point is visible if and only if `dist(P) > 0` for all six planes.

```
visible(P) = (dist_near(P)   > 0)
           & (dist_far(P)    > 0)
           & (dist_left(P)   > 0)
           & (dist_right(P)  > 0)
           & (dist_top(P)    > 0)
           & (dist_bottom(P) > 0)
```

Six multiply-adds per plane, six planes, one AND reduction. 36 operations per point to answer "is this visible" — vastly cheaper than computing what color it should be or where it lands in screen space.

### Why Plane Normalization Matters

When you first construct a plane from `(a, b, c, d)`, the `(a, b, c)` vector is probably not unit-length — it depends on how the plane was derived (projection matrices, cross products, etc). Non-normalized planes still give you the correct _sign_ for point-in-frustum tests, but the _magnitude_ of `dist(P)` isn't a real distance — it's scaled by `|(a, b, c)|`.

For a pure visibility test, this doesn't matter. But the moment you want to compute "how far is this point from the near plane" — for LOD selection, depth sorting, or progressive rendering — you need real distances. vizcrush normalizes planes at construction by dividing all four coefficients by `|(a, b, c)|`, so `dist(P)` is always the true signed distance in world units.

```
|n|   = sqrt(a² + b² + c²)
a, b, c, d ← a/|n|, b/|n|, c/|n|, d/|n|
```

Do it once at construction. You never think about it again.

### Integrating Frustum Culling with the Octree

The real power combo: prune the octree against the frustum _before_ you walk it.

At each octree node, test the node's bounding box against the frustum. Three outcomes:

1. **Box fully inside frustum** → return every point in the subtree, no further testing.
2. **Box fully outside frustum** → skip the entire subtree.
3. **Box straddles the frustum** → recurse into children and test individually.

A scene with 10 million points but a camera looking at 5% of the space typically processes maybe 500K points. That's a 20× win before you do anything else.

This is how every serious 3D viewer — Potree, deck.gl, Three.js with BVH — stays interactive on huge point clouds. It's not the renderer that's fast. It's the culling that makes the renderer's job small enough to be fast.

## 3D Decision Cheat Sheet

| Task                                              | Use                               |
| ------------------------------------------------- | --------------------------------- |
| 3D heatmap / density field                        | `bin3d` (voxel)                   |
| Hover picking, box selection, k-NN in 3D          | `octree`                          |
| Rejecting invisible points before render          | `frustum`                         |
| Interactive point cloud viewer                    | `frustum` + `octree` (cull then query) |
| Progressive LOD streaming                         | `frustum` (normalized) + distance-based LOD |

Everything else you know from earlier chapters still applies — the 3D primitives compose with downsampling (LTTB over the visible set after culling), with streaming (voxel updates on a rolling window), and with normalization (remap z into a color channel). The dimensional jump changes the structures, not the ideas.

Speaking of "the ideas" — most of this book has been about computing things faster or smaller. The next chapter is different. It's about computing things that _explain themselves_, so that a language model (or a curious human) can reason about your data without staring at ten million raw values.
