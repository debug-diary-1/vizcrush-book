# AI-Assisted Viz: Anomaly, Shape, Auto-Config

> **TL;DR**: These four utilities turn a dataset into structured answers that a language model can actually consume. No neural networks, no embeddings. Just classical statistics wired up as the hooks LLMs use to reason about data they'll never see.

Everything else in this book is about making the browser fast enough to show a million points. This chapter is about something different: using statistics to figure out _what you should be showing in the first place_.

The word "AI" in the chapter title is only half accurate. There's no neural network. No model weights. No inference server. These four tools (anomaly detection, shape fingerprints, auto-configuration, summarization) are classical statistics applied well. The "AI" label only fits because they're the hooks that _real_ language models can call to reason about your data without ever seeing the raw numbers.

An LLM doesn't need to ingest two million sensor readings. It needs to ask "are there any anomalies?" and "what does this shape look like?" and "how should I render it?" and get back three small, structured answers. That's what this chapter's primitives provide.

## Anomaly Detection: The Modified Z-Score

The textbook anomaly detector uses the mean and standard deviation: flag anything more than 3σ from the mean. This is popular, widely implemented, and _wrong for real data_.

The problem is that a single huge outlier pulls both the mean and the standard deviation toward itself. The very values you're trying to detect contaminate the statistics you're using to detect them. You end up raising the threshold just enough to hide the thing you wanted to find.

The fix is to use _robust_ statistics: ones that don't get dragged around by extreme values. vizcrush uses the Modified Z-Score, based on Median Absolute Deviation (MAD):

```
median       = median(y)
abs_devs[i]  = |y[i] − median|
MAD          = median(abs_devs)
z[i]         = 0.6745 · (y[i] − median) / MAD
```

The median is immune to outliers. You can add a value of a billion to a dataset and the median barely moves. The MAD is the median of the absolute deviations, which inherits the same immunity. The constant `0.6745` rescales MAD so that, for normally-distributed data, `|z| > 3` corresponds to the same threshold as the classical 3σ test. You get the familiar cutoff without the contamination problem.

`detect_anomalies(y, sensitivity)` returns an interleaved array `[index₀, value₀, score₀, index₁, value₁, score₁, ...]`. One entry per flagged point. The interleaving is deliberate: a single `Float64Array` is the zero-copy format for the WASM → JS boundary, and the caller can iterate three at a time without parsing anything.

**When to use it**:

- Highlighting spikes on a live monitoring chart before the eye can spot them
- Feeding an LLM agent a short list of "interesting moments" instead of the full series
- Triggering alerts on streaming data where the mean is untrustworthy

**Edge case worth knowing**: if MAD is zero (meaning more than half your data points share the exact same value), the function returns an empty list rather than dividing by zero. This is the right call. A dataset with that structure has no meaningful dispersion to measure anomalies against, and silently producing `Infinity` scores would be worse than returning nothing.

## Shape Vectors: "Find Me Charts That Look Like This"

Suppose you have a thousand dashboards and a user says "I want to find all the ones that look like this CPU spike I'm staring at." You can't do a visual comparison against a thousand charts. You need a way to turn each chart's _shape_ into a number, and then compare those numbers.

That's what `compute_shape_vector(y, dimensions)` does. It produces a fixed-length vector of numbers that captures the visual character of a time series. The vector encodes the overall trend, the volatility, the spike ratio, the autocorrelation at a few different lags, and a normalized histogram of the distribution. Two series that look alike end up with similar vectors. Two that look different end up far apart.

The vectors can be compared with cosine similarity, used as keys in a nearest-neighbor search, or fed to a clustering algorithm to group dashboards automatically. It's a cheap, explainable alternative to "run a deep learning model over every chart."

**The components (conceptually)**:

1. **Normalized histogram**. Rescale the data to [0, 1], bin it, record the density per bin. Captures distribution shape: bimodal, skewed, uniform.
2. **Trend coefficient**. Fit a line to the data and record the slope. Captures "is this going up or down."
3. **Volatility**. Standard deviation of the first differences. Captures "how jagged is this."
4. **Spike ratio**. Count of points outside 2σ divided by total count. Captures "how many outliers."
5. **Autocorrelation at multiple lags**. Correlation between `y[t]` and `y[t − lag]` for a few different lag values. Captures periodicity and smoothness.

All of these are cheap to compute in a single or double pass. None of them require keeping the original data around once the vector is built: the vector _is_ the summary.

**Use case**: a user pins a shape they care about. You store its vector. Every new chart gets its vector computed once, compared against the pinned vectors, and tagged. The UI can then say "this looks like the CPU spike pattern" without any human labeling.

**The dimensions parameter**: pass how many dimensions you want in the output. Higher dimensions capture more nuance but make comparison slower and more sensitive to noise. For most dashboards, 16–32 dimensions is plenty: enough to distinguish archetypal shapes, small enough to compare thousands of vectors in milliseconds.

## Summarize: Statistics Small Enough to Fit in a Prompt

`summarize(y)` computes the classical set of summary statistics: count, mean, standard deviation, min, max, median, skewness, kurtosis. All in one pass over sorted data (the sort is O(n log n); everything else is O(n) once).

Two of those are worth pausing on.

**Skewness** measures asymmetry. Positive skew means the right tail is longer (big outliers on the high side). Negative means the left tail is longer. Zero is symmetric. The formula:

```
skewness = (1/n) · Σ ((yᵢ − mean) / stddev)³
```

Cubing preserves sign (negative deviations stay negative), so the sum cancels for a symmetric distribution and grows for a one-sided one.

**Kurtosis** measures tail weight. High kurtosis means a distribution with fatter tails than a Gaussian: more extreme values than you'd expect. Low kurtosis means thinner tails. The formula:

```
kurtosis = (1/n) · Σ ((yᵢ − mean) / stddev)⁴
```

Fourth power because we want to emphasize extremes and we don't care about sign at that point.

Together, skewness and kurtosis answer the question "is this data normally distributed or not?" A Gaussian has skewness 0 and excess kurtosis 0. Financial returns have high kurtosis. The 2008 crash was possible. Sensor noise tends to be low-kurtosis and symmetric. Knowing these two numbers tells you whether the standard statistical machinery will even work on your data.

**Why this matters for AI**: the entire summary fits in a dozen floats. You can put it in a prompt. An LLM sees "count 1.2M, mean 47.3, stddev 18.1, skew 2.4, kurtosis 9.1" and instantly knows this is a long-tailed distribution. No scatter plot required. The model's recommendation becomes better because its input became smaller and more structured.

## Auto-Configuration: Let the Library Decide

`auto_config(x, y, target_width)` looks at a dataset and returns a structured recommendation for how to render it. The output includes:

- **Algorithm**: which downsampler to use (`lttb`, `minmax_lttb`, etc.)
- **Target points**: how many points to output (usually a small multiple of display width)
- **Bin resolution**, for scatter / heatmap data
- **Spatial index**, `quadtree`, `kdtree`, or `hashgrid`
- **Streaming config**, window size + update interval, if the data looks live
- **Estimated speedup**, a rough factor compared to rendering every point
- **Reasoning**, a short string explaining _why_ these choices

The decision logic is simple and transparent, no opaque model. It checks basic properties of the data (is x monotonically increasing → time series; is the spread huge → probably needs log scale; how many points are outside 2σ → spikey or smooth) and applies rules from the decision chapter you'll find later in this book.

The reasoning string is the interesting part. When the recommendation is wrong, a human, or a language model, can read the reasoning and override it. When the recommendation is right, the reasoning is documentation: "I picked MinMaxLTTB because 3.2% of your points are more than 2σ from the mean, so spike preservation matters for this dataset."

**Two ways to use this**:

1. **Interactive**: call `auto_config` when the user first loads a dataset. Apply the result as defaults. Let them adjust.
2. **Agent-driven**: an LLM calls `auto_config` through the MCP server (see the library docs), gets the structured result plus the reasoning, and either applies it or asks the user "I'd recommend MinMaxLTTB because of spikes, OK?"

Either way, the goal is the same: move the decision-making logic out of "someone had to read the docs and pick correctly" into the library itself. Every step away from hand-tuning is a step toward dashboards that just work.

## The Throughline

None of this is glamorous machine learning. No embeddings, no fine-tuning, no GPUs training anything. Just statistics applied with some taste and wired up to a structured output format that tools, human or otherwise, can actually consume.

That's the point. The "AI-readiness" of a library isn't about adding a model. It's about making your data's properties queryable in a form a model can reason about without hallucinating. A summary with skewness and kurtosis beats "here's 2 million raw samples, figure it out." A shape vector beats "look at this screenshot." An auto-config result beats "read the docs and choose."

Build the primitives that answer _specific questions_, and the rest of the AI story writes itself.

That's the last of the algorithm chapters. You've now met every tool in the vizcrush toolbox. The next two chapters are about _choosing_, how to pick the right tool for a specific problem, and how to actually wire it into a real codebase.
