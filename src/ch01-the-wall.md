# The Wall

> **TL;DR**: Chart libraries are great at 10K points and surprisingly bad at 100K. This chapter is about why that cliff exists, why the obvious fixes (workers, servers) don't fix it, and where vizcrush fits in.

Here's something nobody tells you when you start building data dashboards: chart libraries have a cliff.

D3, Plotly, ECharts, Chart.js: they all work beautifully at 10K points. At 50K they start to stutter on pan and zoom. At 100K you can see frames dropping. At 500K your users start filing bug reports. At a million points, the browser gives up entirely.

I call this the 100K Datapoint Wall.

The math behind it is simple and unforgiving. When a chart library renders a dataset, it does roughly this:

```
For every point in your data:
  1. Read the value                    → O(n)
  2. Convert to pixel coordinates      → O(n)
  3. Issue a draw call                 → O(n)
  4. Browser composites the result     → O(n)
```

Four passes, each touching every point. For a million points that's four million operations, and you need all of them done in 16.6 milliseconds to hit 60fps. JavaScript on a single thread cannot do this. Not on an M3 Max, not on a Threadripper, not on anything.

And here's the part that should bother you: **most of that work is invisible**.

A chart that's 1920 pixels wide can show at most 1,920 distinct x-positions. If you have 2 million data points, roughly a thousand of them land on every single pixel. You're computing coordinates, issuing draw calls, and burning CPU cycles for points that literally cannot be distinguished from each other on screen.

That's not a rendering problem. That's a data problem.

## Why Workers Don't Fix It

The knee-jerk reaction is "throw it in a Web Worker." I tried this. Here's what actually happens:

You call `postMessage` to send your data to the worker. JavaScript has to serialize that data, and serializing 100K objects takes about 150ms. The worker processes it (maybe 50ms), serializes the result back (another 50ms), and posts it to the main thread.

Total round trip: 250ms. For a single frame.

Now imagine the user is pinch-zooming on their phone, generating 10 touch events per second. Each one needs a fresh downsample. Your worker is perpetually behind, returning stale results for viewports the user has already scrolled past. It feels laggy no matter how fast the actual computation is because the serialization overhead dominates everything.

The problem isn't compute speed. The problem is getting data across the boundary.

## Why Server-Side Pre-Aggregation Has Limits

"Just aggregate on the server" sounds reasonable until you think about it:

- Round trip latency (50-200ms) is visible on every zoom gesture
- You need dedicated aggregation infrastructure that costs money
- Offline-first apps can't phone home
- The server doesn't know your exact screen width, pixel density, or current viewport bounds

Server aggregation makes sense for initial page load. It falls apart for interactive exploration.

## The Actual Solution

vizcrush takes a different approach: do the computation _in the browser_ but not in JavaScript.

The core algorithms are written in Rust and compiled to WebAssembly, with a pure-JavaScript implementation of every algorithm alongside it — a "fallback" that, in some browsers, turns out to be the faster path (chapter 3 has the surprising numbers). A thin JavaScript layer detects what the environment supports and picks accordingly.

No serialization. No network calls. No Web Worker boundary. The WASM module reads directly from the same typed array memory that JavaScript uses. A million-point LTTB downsample takes about 2 milliseconds.

That's the 30-second pitch. The rest of the book is _how_.
