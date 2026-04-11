# What vizcrush Actually Does

> **TL;DR** — vizcrush is a data-compute layer, not a chart library. Numbers in, numbers out. You keep your chart library, whichever one it is.

I want to be very precise about this because it trips people up: **vizcrush does not render anything**.

No canvas. No SVG. No DOM nodes. No WebGL draw calls. Nothing visual.

It takes a big array of numbers in, and returns a smaller (or differently shaped) array of numbers out. What you do with those numbers is your business — feed them to D3, Plotly, Chart.js, ChartGPU, a plain `<canvas>`, whatever. vizcrush doesn't care and doesn't want to know.

Think of it as a food processor. You put raw ingredients in. It chops, slices, and dices. It doesn't cook anything or plate it for you. That's the chart library's job.

Here's the layer cake:

```
┌─────────────────────────────────────────────┐
│  Rendering: ChartGPU, D3, Plotly, ECharts   │  ← draws pixels
├─────────────────────────────────────────────┤
│  Data Compute: vizcrush                     │  ← THIS LAYER
├─────────────────────────────────────────────┤
│  GPU Access: WebGPU, WebAssembly            │  ← hardware
└─────────────────────────────────────────────┘
```

The rendering layer is mature. The GPU access layer is emerging. The data compute layer in between was missing. That's the gap.

## The Zero-Loss Thing

People hear "downsampling" and think "lossy compression." It's not. Let me be clear about what happens:

Your original 2-million-point dataset stays in memory, untouched. vizcrush creates a _view_ — a selection of points optimized for the current screen. When the user zooms into a small region, vizcrush re-selects from the full dataset for that region. Every zoom level gets pixel-perfect representation.

A human looking at the downsampled chart cannot distinguish it from the full-resolution chart. That's not a marketing claim — it's a mathematical property of the LTTB algorithm. The points are selected specifically to maximize visual fidelity for the given number of output pixels.

Your data is safe. We just pick the points that matter.

Now, how do we pick them quickly? There are two very different machines we can point at the problem, and the next chapter is about when to use which.
