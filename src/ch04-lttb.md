# LTTB: The Algorithm That Started Everything

> **TL;DR**: LTTB picks the points that matter most to the human eye by thinking in triangles. It's simple, it's fast, and it's the downsampling algorithm you should reach for by default.

Imagine a chart showing a million temperature readings across a year. Your screen is 1920 pixels wide. You have to throw away all but 1920 points. **Which ones do you keep?**

The obvious answer, "every five-hundredth one", is also the wrong one. Uniform sampling will cheerfully land on flat, boring regions and step right past the year's hottest day and coldest night. You just hid the two most important moments of the year from your user.

A guy named Sveinn Steinarsson wrote a master's thesis in 2013 about a smarter way to pick. He called it **Largest-Triangle-Three-Buckets**, LTTB for short. It's the algorithm vizcrush reaches for by default, and the one I reach for maybe 95% of the time I'm downsampling anything. It's also beautifully simple once you see the trick.

The trick is: think in triangles.

## The Triangle Trick

LTTB chops your time series into roughly equal buckets, one bucket per output point, minus the first and last, which are always kept. From each bucket it picks one survivor: the point that forms the biggest triangle with its neighbors.

What triangle? Three vertices:

1. **Left vertex**: the point we selected from the previous bucket
2. **Right vertex**: the _average_ of all points in the _next_ bucket
3. **Candidate vertex**: each point in the current bucket, tried one at a time

```
        candidate point
            *
           /|\
          / | \
         /  |  \        ← area of this triangle
        /   |   \
       /    |    \
      *─────┼─────*
  previously       average of
   selected        next bucket
```

The candidate point that creates the biggest triangle is the one that deviates most from the straight line connecting its neighbors. In other words, it's the most "interesting" point, the peak of a spike, the bottom of a dip, the sharpest bend in a curve.

This is why LTTB works so well. It's not randomly sampling. It's not blindly decimating. It's specifically selecting the points that contribute the most visual information.

## The Algorithm, Step by Step

```
1. Always keep the first point.

2. For bucket i (from 0 to threshold-2):
   a. Look at the NEXT bucket (i+1) and compute its average (x, y).
   b. For each point in the CURRENT bucket:
      - Compute the triangle area between:
        (previous selected point, current point, next bucket average)
   c. Keep the point with the largest area.
   d. That point becomes the "previous selected" for the next iteration.

3. Always keep the last point.
```

The entire thing is a single pass through the data. O(n) time. No sorting needed (the data is already time-ordered). No extra memory beyond the output buffer. It's gorgeous.

## Why the Next-Bucket Average?

This is the clever bit. By looking _ahead_ to the average of the next bucket, LTTB accounts for what's coming next. A point that's interesting in isolation might be redundant given what follows. The look-ahead prevents selecting a point that the next bucket will make obsolete.

This forward-looking property is also why LTTB can't be parallelized on the GPU. Each bucket depends on the next bucket's average, which creates a dependency chain.

## The Triangle Area Formula

The triangle area can be computed without square roots or trigonometry using the cross-product form:

```
area = |(prev_x − next_x) · (curr_y − prev_y)
       − (prev_x − curr_x) · (next_y − prev_y)|
```

Three multiplications, five additions, one absolute value per candidate point. That's why LTTB is fast: the inner loop does almost no work, and every operation maps cleanly onto SIMD lanes.

The same trick shows up later in the book under a different name (the math chapter at the end derives it properly). For now, just know that this is what makes a million-point downsample take under two milliseconds.

LTTB is the right default for smooth data. But trading charts have spikes. Sensors have glitches. Crypto prices do things that LTTB will happily smooth over. The next chapter is about what to do when the "average" behavior isn't what the user needs to see.
