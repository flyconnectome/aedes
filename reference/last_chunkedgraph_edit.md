# Use binary search to find the last edit operation ID for a CAVE dataset

Use binary search to find the last edit operation ID for a CAVE dataset

## Usage

``` r
last_chunkedgraph_edit(
  datastack_name,
  start = 1e+05,
  stop = 1e+06,
  window = 100
)

last_aedes_edit(...)
```

## Arguments

- datastack_name:

  CAVE datastack name.

- start:

  Start index for search (must exist).

- stop:

  Finish index for search (must not exist).

- window:

  Number of consecutive ids checked at each probe point. Must be larger
  than the biggest gap between existing operation ids.

## Value

An integer operation ID.

## Details

Operation ids are not contiguous (gaps of up to ~20 ids are seen in
practice), so the search asks whether *any* operation exists in a window
of `window` ids starting at each probe point.

## Functions

- `last_aedes_edit()`: Aedes-specific wrapper.
