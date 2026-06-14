# Predict the L/R side of Aedes neurons

Returns the logical side of each requested neuron. The side can come
from the manual `side` annotation in the FlyTable metadata (when
present) or be derived from the soma's position relative to the Aedes
midline via [`aedes_point_side`](aedes_point_side.md).

## Usage

``` r
aedes_soma_side(
  ids,
  method = c("auto", "manual", "position"),
  threshold = 0,
  mesh = aedes::aedes_neuropil_mesh,
  chunksize = 20L,
  cl = NULL,
  version = NULL,
  timestamp = NULL
)
```

## Arguments

- ids:

  Root IDs, a query string (see [`aedes_ids`](aedes_meta.md)), or a
  pre-fetched metadata data.frame from [`aedes_meta`](aedes_meta.md)
  (must contain a `root_id` column).

- method:

  One of `"auto"` (default), `"manual"`, `"position"`. See Details.

- threshold:

  Absolute X displacement (nm) below which `position` reports a soma as
  midline (`"M"`). Default `0`. Ignored by `manual`.

- mesh, chunksize, cl:

  Forwarded to [`aedes_soma_position`](aedes_soma_position.md).

- version, timestamp:

  Optional CAVE materialisation selectors, forwarded to
  [`aedes_meta`](aedes_meta.md) and
  [`aedes_soma_position`](aedes_soma_position.md).

## Value

A character vector of `"L"`, `"R"`, `"M"`, `"U"` or `NA`, one entry per
input root id.

## Details

Methods:

- `auto`:

  Try `manual` first, then fill any remaining `NA`s using `position`.

- `manual`:

  Read the `side` column of [`aedes_meta`](aedes_meta.md). Values are
  uppercased; entries outside `"L"`, `"R"`, `"M"`, `"U"` become `NA`.

- `position`:

  Classify each soma by its signed displacement from the Aedes midline
  via [`aedes_point_side`](aedes_point_side.md). `threshold` is
  forwarded as-is; the default `0` means `position` never returns `"M"`.
  `"M"` is reserved for bilaterally symmetric / unpaired neurons
  annotated as such.

## See also

[`aedes_point_side`](aedes_point_side.md),
[`aedes_soma_position`](aedes_soma_position.md),
[`aedes_meta`](aedes_meta.md)

## Examples

``` r
if (FALSE) { # \dontrun{
aedes_soma_side("class:DNa")
aedes_soma_side("648518347465408914") # known L
aedes_soma_side("class:DNa", method = "position")
} # }
```
