# The vizcrush Book

_High-Performance Data Primitives for Browser Visualization_

---

I wrote vizcrush because I got tired of watching browser tabs die.

If you've ever built a dashboard that loads 500K data points and watched Chrome's "Page Unresponsive" dialog pop up: you know the feeling. The data is right there, the chart library is fine, but the browser just can't handle it. That's the problem this library solves.

This book is the story of _how_ it solves it. Not an API reference (the library's docs do that). This is the part you read front to back, once, and walk away understanding _why_ the algorithms inside work the way they do, _when_ to reach for each one, and _what_ tradeoffs you're making when you do.

---

## Who this book is for

You will get the most out of this book if you're:

- **A frontend or full-stack engineer** building dashboards or data-heavy UIs, and you've hit the wall where your chart library stops being fun.
- **A data scientist or analyst** who writes code and wants to understand what "downsampling," "binning," "sketches," or "spatial indexing" actually mean in code instead of in papers.
- **An engineer outside the web stack** (backend, embedded, mobile) who's curious about the specific tricks that make browser-side data viz fast.
- **A student or self-learner** working through "how do real libraries handle large datasets?"

You will probably bounce if you:

- Want a reference manual with every function signature documented. (The library repo has that.)
- Want a math-heavy treatment with proofs and formal error bounds. (A few papers are cited; go read those.)
- Want a "build a chart library" tutorial. This book intentionally stops at the _data_ layer; the rendering is your business.

### A note on prerequisites

This book is technical, but not gatekeeping. If a term is unfamiliar and this book doesn't explain it, the best thing you can do in 2026 is **ask your favorite language model** (Claude, ChatGPT, whatever). They'll give you a perfectly good definition of "SIMD," "atomic operation," "cache line," or "Float64Array" in three seconds. This book deliberately doesn't spend pages on those definitions; it spends them on the insights you _can't_ get from a definition.

That's the deal: I'll tell you the _why_: the thing a textbook won't. You handle the _what_ with whatever tool you prefer. Everyone's time gets respected.

### How to read it

- **Chapters 1–3** set up the problem and the two engines (Rust/WebAssembly and the pure-JS core). Read these first, in order.
- **Chapters 4–11** tour the algorithms, one family at a time. Each chapter is self-contained; skim the TL;DRs and dive into whichever ones are relevant to your problem.
- **Chapters 12–13** are the "decide and build" chapters: pick the right tool, then see it in code. If you only read two chapters, read these two.
- **Chapters 14–16** are the under-the-hood tour: fallbacks, performance lessons, and the math. Optional, but the fun part if you've already finished the rest.

Every chapter has a one-sentence TL;DR at the top. If the TL;DR doesn't make you curious, skip the chapter. There's no test at the end.

Let's get into it.

---

_This is the free, web-native edition of the book. The source lives at [github.com/debug-diary-1/vizcrush-book](https://github.com/debug-diary-1/vizcrush-book). vizcrush itself lives at [github.com/debug-diary-1/vizcrush](https://github.com/debug-diary-1/vizcrush)._
