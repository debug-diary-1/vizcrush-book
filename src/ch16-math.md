# The Math Behind It All

> **TL;DR** — The formulas every earlier chapter referred to but didn't spell out. Safe to skip. Useful if you want to modify the algorithms, verify them, or argue about them on the internet.

This chapter is the appendix, not the finale. If the earlier chapters gave you the story, this chapter is the receipts — the actual formulas behind each algorithm, written out for anyone who wants to check the homework.

You don't need any of this to _use_ vizcrush. You might want some of it if you plan to port an algorithm, tune a parameter past its default, or write your own variant. Skim the headings and dip in where you're curious.

## Triangle Area (Cross Product Form)

Given three points (x₁,y₁), (x₂,y₂), (x₃,y₃):

```
Area = ½ |x₁(y₂ - y₃) + x₂(y₃ - y₁) + x₃(y₁ - y₂)|
```

This is the absolute value of half the cross product of vectors (P₂-P₁) and (P₃-P₁). No square roots or trigonometry. Three multiplications, five additions, one absolute value. This is what makes LTTB fast — the inner loop does almost no work per candidate.

## Welford's Derivation

Starting from the definition of sample mean:

```
μₙ = (1/n) Σ xᵢ
```

When xₙ₊₁ arrives:

```
μₙ₊₁ = μₙ + (xₙ₊₁ - μₙ) / (n+1)
```

For the sum of squared deviations M₂:

```
M₂,ₙ₊₁ = M₂,ₙ + (xₙ₊₁ - μₙ)(xₙ₊₁ - μₙ₊₁)
```

The product `(xₙ₊₁ - μₙ)(xₙ₊₁ - μₙ₊₁)` is always non-negative (both factors have the same sign because μₙ₊₁ is between μₙ and xₙ₊₁). This means M₂ increases monotonically — no cancellation errors.

Sample variance: `σ² = M₂ / (n - 1)`

## Morton Code Bit Interleaving

To interleave the bits of two 16-bit integers into one 32-bit integer:

```
expand_bits(v):
    v = (v | v << 8) & 0x00FF00FF
    v = (v | v << 4) & 0x0F0F0F0F
    v = (v | v << 2) & 0x33333333
    v = (v | v << 1) & 0x55555555
    return v

morton(x, y) = expand_bits(x) | (expand_bits(y) << 1)
```

Each step "spreads" the bits apart with zeros between them. The final OR merges x bits into even positions and y bits into odd positions.

## IEEE 754 Sortable Encoding

A 64-bit float in IEEE 754:

```
[sign: 1 bit] [exponent: 11 bits] [mantissa: 52 bits]
```

Positive floats already sort correctly as unsigned integers (exponent ordering, mantissa breaks ties). Negative floats sort _backwards_ (more negative = larger bit pattern).

The fix:

- **Positive**: flip the sign bit (so positives sort after negatives)
- **Negative**: flip ALL bits (inverting the backward ordering)

This is an order-preserving bijection from f64 to u64, enabling radix sort on floats.

## t-digest Scale Function

The compression function that controls centroid size:

```
k(q) = (δ / 2π) · arcsin(2q - 1) + δ/2
```

where q ∈ [0,1] is the quantile position and δ is the compression parameter.

The derivative dk/dq approaches infinity at q=0 and q=1, forcing centroids near the tails to be small (high resolution). At q=0.5, the derivative is at its minimum, allowing large centroids (low resolution where it doesn't matter).

## DDSketch Logarithmic Buckets

Given a relative-accuracy target α ∈ (0, 1):

```
γ     = (1 + α) / (1 - α)
b(v)  = ⌈ln(v) / ln(γ)⌉      ← bucket index for value v
```

Any value v falls into bucket `b(v)`, and any two values in the same bucket differ by at most a factor of γ. That's where the relative-error guarantee comes from: pick α, derive γ, every quantile estimate is within α of the truth on a multiplicative scale.

## HyperLogLog Estimate

For `m = 2ᵖ` registers with values M[0..m):

```
raw = α_m · m² / Σᵢ 2^(-M[i])
```

where `α_m` is a bias-correction constant (0.7213/(1+1.079/m) for large m).

Small-range correction: when many registers are still zero, linear counting is more accurate — `m · ln(m / zeros)`. Large-range correction uses the Heule et al. empirical bias table (not reproduced here).

## Hexagonal Grid Coordinates

A regular hexagon with radius r:

```
Width between parallel edges:  r√3
Distance between hex centers:  2r (horizontal), r√3 (vertical)
Row offset:                    r for odd rows, 0 for even rows
```

Point-to-hex assignment:

```
row = round((y - y_min) / (r√3))
offset = r if row is odd, else 0
col = round((x - x_min - offset) / (2r))
```

This is an approximation. The exact nearest-hex computation requires checking the three closest candidates — but the round-based approximation is correct for >98% of points and the error only occurs at hex boundaries where it doesn't matter for visualization.
