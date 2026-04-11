# Streaming and Sketches: Numbers That Never Stop

> **TL;DR** — When data arrives forever, you can't keep it all. Streaming algorithms and sketches let you answer hard questions — percentiles, distinct counts, frequencies — with a fixed amount of memory no matter how long the stream runs.

Imagine trying to count every car that drives past your house for the rest of your life. Not a bad challenge. Add a twist: keep a running average of how fast they were going, a running list of the fastest and slowest, and an estimate of the 99th-percentile speed — all without writing anything down except a single Post-it note.

It sounds impossible. It's not. The algorithms in this chapter do something like that every day, for terabytes of live data, on fixed memory budgets. They're small, elegant, and _deeply_ clever. Most of them are 60-year-old math that got rediscovered when streaming data became normal.

Real-time dashboards are a different beast from the batch work in the rest of the book. Data arrives continuously — a server monitoring system might push 1,000 metrics per second. You need rolling statistics (min, max, mean, standard deviation) that update instantly, plus a chart that stays smooth at 60fps despite constant data churn.

The naive approach recalculates from scratch on every batch: scan all 20K buffered values for min/max, compute the mean, compute the variance. That's O(n) per update. At 20 updates per second on a 20K buffer, that's 400K operations per second wasted on re-computation.

## Welford's Algorithm: One Pass, No Surprises

Carl Welford published this in 1962 and it's still the best way to compute running variance. Here's the idea:

When a new value arrives, you can update the mean and variance without re-scanning the entire dataset. Each update is O(1):

```
New value x arrives (count becomes n):

  delta  = x - old_mean
  mean   = old_mean + delta / n
  delta2 = x - mean                ← note: uses the NEW mean
  M₂     = M₂ + delta * delta2

  variance = M₂ / (n - 1)
  std_dev  = sqrt(variance)
```

The brilliant part is using both `delta` (difference from old mean) and `delta2` (difference from new mean). Their product is always positive, which means M₂ always increases. No catastrophic cancellation, no accumulated rounding errors. I've seen implementations using the textbook formula `variance = E[x²] - E[x]²` produce negative variance on large datasets because of floating-point cancellation. Welford's never does that.

## The Rolling Window

vizcrush's streaming stats maintain a circular buffer. When the buffer is full, adding a new value evicts the oldest one. We need to _remove_ the old value's contribution from the running statistics.

Removing from Welford's is the reverse operation: subtract the old value's delta contribution from M₂, then update the mean. It works, but there's one gotcha — if the evicted value was the current min or max, we need to rescan the buffer to find the new extreme. This rescan is O(window_size), but it's infrequent (only when the min or max ages out).

## appendAndDownsample: The Streaming Sweet Spot

For streaming charts, the common pattern is:

```
1. New batch arrives (50 points)
2. Append to rolling buffer
3. If buffer exceeds max size, drop oldest
4. Downsample entire buffer to display-point count
5. Update chart
```

vizcrush combines steps 2-4 into a single function. No temporary buffer allocations, no double iteration. The LTTB pass operates directly on the combined data.

## t-digest: Percentiles Without Sorting

If someone asks "what's the 99th percentile of the last million values," you can't sort a million numbers every time. t-digest (Ted Dunning, 2019) maintains a compressed representation using "centroids" — each centroid stores a mean and a weight (how many values it represents).

The key insight: centroids near the tails (p=0 and p=1) are kept small, giving high precision exactly where percentile queries need it. The p50 centroid might represent thousands of values (low precision, but p50 doesn't need it). The p99.9 centroid might represent only 3 values (high precision, because p99.9 matters for SLA monitoring).

Memory usage is bounded — typically 100-500 centroids regardless of how many values you've ingested. A billion-value stream uses the same memory as a thousand-value stream.

## KLL Sketch: Quantiles With Provable Error Bounds

t-digest is great in practice, but it doesn't come with a formal worst-case guarantee. If you need to write in a paper or a compliance doc that "the 95th percentile estimate is within 1% of truth, I can prove it," you want KLL instead.

### The Core Idea, Told With Stairs

Imagine you're collecting values in a bucket. When the bucket fills up, you can't keep everything, so you play a little game: sort what you have, then keep every _other_ element and throw the rest away. You pour the survivors into a _second_, bigger bucket. That bucket represents twice the information per slot — each element now "stands in for" two of the originals.

Second bucket fills up. Same game. Sort it, keep every other, dump the survivors into a _third_ bucket, which now represents four originals per slot. And so on, up the stairs.

At the top of the staircase, you've got a small sample that represents a huge stream. Each bucket remembers its "weight" — how many original items each stored value stands for. When you ask "what's the 90th percentile," the algorithm walks the stairs, weighting each sample appropriately, and gives you an answer.

That's KLL (Karnin-Lang-Liberty, 2016) in plain English. Each "compactor" is one step on the staircase. The key property: total memory grows only _logarithmically_ with how much data you stream. Double the input, add one step. Double again, add one more. You could stream a trillion items and the staircase would still fit in a kilobyte or two.

### The Clever Wrinkle

The step "sort, keep every other element" has a subtle problem: if you always keep the even-indexed ones, you introduce bias — the lower half of every pair slightly dominates. KLL alternates: sometimes keep the evens, sometimes keep the odds. Over many compactions, the bias cancels out, and you get the formal guarantee: your rank error is bounded by ε with high probability, using memory that scales as `O((1/ε) log² log(1/δ))`.

For the default setting (`k=200`), expect ~1% rank error in a few kilobytes, for any input size you can reasonably imagine.

### When to Pick KLL vs. t-digest

- **t-digest**: better tail accuracy (p99.9, p99.99) for SLA monitoring. Empirically excellent. Use when operators trust you.
- **KLL**: clean theoretical bounds. Use when a reviewer, auditor, or paper demands a proof.

## DDSketch: Relative-Error Quantiles for Latency

### The Core Idea, Told With a Ruler

Imagine a ruler for measuring fish. If your ruler has one-centimeter markings, it's great for measuring small fish — a 4 cm guppy reads accurately. For a 4-meter tuna, the centimeter markings are overkill; the tuna is 400 cm whether you read it as 399 or 401, and nobody cares.

Now imagine the opposite ruler: the smallest marking is 10 cm. Great for tuna (400 cm ± 5 cm, no problem). But now the guppy reads as "about 0 cm" and you've completely lost it.

Real latency data is the fish problem. A web request can take 5 microseconds (database cache hit) or 5 minutes (deadlock on a cross-region replica). Both numbers matter. Neither ruler works for both.

DDSketch's trick: build a ruler whose _markings get wider as values get bigger_. Small values get fine markings. Big values get coarse ones. The key property is that any two values within the same marking are guaranteed to be within a fixed _percentage_ of each other — 1% for the default setting.

### How It Works

Pick an error target — say, 1%. From that, compute a number called `γ` (gamma) slightly bigger than 1. Now lay out your "markings" (really, buckets) so that bucket `i` covers values from `γⁱ` to `γⁱ⁺¹`.

Any two values in the same bucket differ by at most a factor of γ. That's where the 1% guarantee comes from: by construction, you can never mis-estimate a value by more than that fixed percentage, no matter how small or large it is.

Inserting a new value takes two operations: compute its log, divide by `log(γ)`, round up. That's the bucket index. Increment the bucket's counter. Done.

Buckets are stored in a sparse map keyed by index, so empty buckets cost nothing. A real latency stream might only touch a few hundred of them in total — memory stays tiny.

DDSketch is what Datadog uses for latency percentiles, and once you see the ruler analogy it's obvious why. It's also the right tool for anything where you care about _ratios_ rather than absolute differences: sizes in bytes, prices in dollars, response times in milliseconds. Anywhere "how much bigger is this than that" is a more natural question than "how much larger in absolute terms."

## HyperLogLog: Counting Distinct Things

"How many unique users hit the site today?" sounds easy until you realize you can't fit a hundred million user IDs in a hash set on a phone. You need a way to estimate _how many distinct things_ showed up without keeping the things themselves.

### The Core Idea, Told With Coins

Flip a coin until you get tails. Count how many heads in a row you got first.

Most of the time you'll get a short streak — zero, one, two heads. A streak of five heads is rare. A streak of ten is _very_ rare. If I walk up to you and tell you "the longest streak I saw today was ten heads," you can make a reasonable guess that I flipped a _lot_ of coins. Roughly 2¹⁰ ≈ 1,000 of them. Not because every streak of ten corresponds to exactly a thousand flips, but because on average you need about that many tries before a ten-streak shows up.

HyperLogLog plays the exact same game with data. Every item you feed it gets hashed into a random-looking 64-bit number. The library tracks the longest run of leading zeros it has seen across all those numbers. A run of 20 zeros is rare enough that it strongly suggests you've processed around 2²⁰ ≈ a million unique items. A run of 30 suggests a billion.

That's the whole trick. You never stored the items. You stored a single number: the longest streak you've seen. From that number alone, you can estimate how many distinct things walked past you.

### Why One Counter Isn't Enough

A single streak counter is wildly noisy. One really lucky hash could give you a 30-streak after only a hundred items, and now your estimate is off by a factor of ten million.

The fix is: use _many_ counters and average them. Split the incoming hash into two pieces — a "bucket prefix" (the first few bits) and a "remainder." The bucket prefix decides _which_ counter gets updated. The remainder is where you count the leading-zero streak.

```
Hash an item.
  First 14 bits → pick one of 16,384 counters.
  Remaining bits → count the leading zeros, update that counter if longer.
```

Different items hit different counters. Each counter sees roughly `total / 16,384` unique items and records its own longest streak. Averaging those 16,384 streaks is wildly more accurate than trusting any single one — variance drops by a factor of the square root of the counter count, which for 16,384 counters is about 128×.

The default configuration uses 16,384 single-byte counters, for a grand total of 16 KB of memory — smaller than a single PNG icon on a web page. Error at that size is about 0.8%. That's billions-of-events cardinality estimation in a buffer that fits in L1 cache.

### Edge Cases

When a stream has very few items, most counters are still zero and the estimate is biased high. When it has astronomically many, there's a different kind of bias at the top end. The implementation includes corrections from the Heule et al. "HyperLogLog in Practice" paper for both tails. You don't need to think about them — they kick in automatically — but they're why the library's estimates are accurate at a thousand items and at a trillion items, not just at the sizes the original paper happened to test.

## Count-Min Sketch: Counting How Often Things Happen

HyperLogLog tells you _how many_ distinct things you saw. Count-Min Sketch (Cormode-Muthukrishnan, 2005) tells you _how often_ a specific thing showed up — the "heavy hitters" problem.

The structure is a 2D table: `depth` rows by `width` columns. Each row has its own hash function. To increment, you hash the value with each row's hash and increment the cell `table[row * width + hash]`. To query, you look up all `depth` cells and return the _minimum_.

```
table[0][h₀(x)] += 1
table[1][h₁(x)] += 1
table[2][h₂(x)] += 1
...
estimate(x) = min over all rows
```

Why the minimum? Each cell is an upper bound on the true count (other items hash there too and inflate it). The minimum is the tightest upper bound across rows. With width ε⁻¹ and depth log(δ⁻¹), the estimate is within ε·N of the true count with probability 1−δ.

The catch: it can _overestimate_ but never underestimate. Perfect for "find me anything that appeared more than 1% of the time" queries. Wrong for "exactly how many times did X appear" — use a real hash table for that.

vizcrush ships an 8KB-default sketch (width=1024, depth=5) that handles millions of events per second on a single thread.

## Reservoir Sampling: A Random Sample From a Stream

You have an infinite stream of values and you want to keep a uniformly random sample of size k, without ever knowing the total length in advance. Vitter's Algorithm R from 1985 does this in three lines of logic:

```
For each new item (1-indexed count n):
  if the reservoir has fewer than k items:
    append the new item
  else:
    pick a random index j in [0, n)
    if j < k: replace reservoir[j] with the new item
```

The first k items go straight in. After that, item N is kept with probability k/N, and if it's kept it replaces a uniformly random existing slot. The algebra works out so that at every point in time, every item seen so far has exactly k/N probability of being in the reservoir. No bias toward early or late items. No knowledge of N required.

vizcrush uses an XOR-shift PRNG (the same one we use for hash seeding) instead of a real RNG, because we want deterministic results in tests and reproducible bug reports. If you need cryptographic randomness for sampling, you're solving a different problem and should not be using this.

The use case is simple: you're streaming a billion events, you want to feed a 1,000-point scatter plot, and you want every event to have an equal chance of being shown. Reservoir sampling is the right call.

So far we've been talking about _picking_ the right data to show. Before you can pick well, though, you often need to clean up what you have — sort it, normalize it, filter it, reshape it. That's the boring but critical plumbing of the next chapter.
