# MinMaxLTTB, M4, LTOB — When LTTB Isn't Enough

> **TL;DR** — LTTB smooths spikes. For data where the spikes _are_ the story, you need a different algorithm. This chapter covers the three understudies and when to cast each one.

The first time I shipped LTTB to a real user, I got a Slack message within an hour: _"your chart is lying to me."_

The user was watching BTC prices. In their raw data, there was a moment where the price stabbed up $2,000 in a single candle and came back down just as fast. In my beautifully downsampled chart, that spike was _gone_ — smoothed into a gentle curve that suggested nothing interesting had happened.

LTTB didn't have a bug. It did exactly what it was designed to do: pick the points that look most "interesting" relative to their neighbors. The problem is that a single extreme value, surrounded by normal ones, doesn't look very interesting to an algorithm measuring triangle areas. The trend matters more than the moment. So the moment disappears.

The user didn't care about the math. They cared that a trading decision had just been made on a lie. I spent that weekend reading papers.

## MinMaxLTTB: Don't Drop the Spikes

I first hit this problem with crypto trading data. BTC price can spike $2,000 in a single candle and recover just as fast. LTTB's triangle-area metric tends to smooth over these spikes because the overall trend matters more to the triangle than a momentary extreme.

MinMaxLTTB fixes this with a two-phase approach:

**Phase 1 — MinMax pre-selection.** Divide the data into 4× the target number of buckets. From each bucket, unconditionally keep the point with the minimum y and the point with the maximum y. This guarantees every spike is in the candidate set, no matter how brief.

**Phase 2 — Run LTTB on the pre-selected points.** Now LTTB does its visual-shape optimization on a dataset where the spikes are already locked in.

The result: you get LTTB's visual quality _plus_ guaranteed spike preservation. The cost is that Phase 1 adds a pass through the data, but it's a simple min/max scan — cheap.

Use MinMaxLTTB for financial data, IoT sensor alarms, or anything where missing a momentary extreme would be a bug.

## M4: Four Points Per Pixel

M4 takes a totally different philosophy. For each output bucket, it keeps exactly four points:

1. The **first** point (left temporal boundary)
2. The **last** point (right temporal boundary)
3. The **minimum** y (the low)
4. The **maximum** y (the high)

If you squint, this is a candlestick chart — open, close, low, high — for each pixel column. It's guaranteed to preserve exact extremes. The downside is it produces up to 4× more output points than LTTB for the same number of buckets.

When to use it: when your compliance team says "the chart must show the exact minimum and maximum values that occurred" and they don't care about visual elegance.

## LTOB: LTTB's Lazy Cousin

LTOB (Largest-Triangle-One-Bucket) simplifies LTTB by using the current bucket's own boundary points as the triangle vertices instead of looking ahead to the next bucket's average.

It's about 20% faster and 5-10% worse visually. I honestly don't recommend it over LTTB unless you're on extremely constrained hardware and every microsecond counts. But it's there if you need it.

## Picking the Right One

When someone asks me "which algorithm should I use," I ask one question: **does the data have spikes that matter?**

- No spikes, smooth trends → **LTTB**
- Spikes matter (finance, IoT alarms) → **MinMaxLTTB**
- Must preserve exact min/max (compliance) → **M4**
- Maximum speed, quality secondary → **LTOB**

vizcrush has an `auto_downsample` function that makes this decision based on a hint you provide (`'time_series'`, `'financial'`, `'sensor'`, `'scatter'`).

All four of these algorithms assume your data has a natural x-axis to thin out along — time, distance, index, something. Scatter plots don't have that luxury. You can't "downsample along X" when X and Y are independent. That's a whole different problem, and it has its own chapter next.
