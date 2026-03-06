# Use binary search to find the last edit operation ID for a CAVE dataset

Use binary search to find the last edit operation ID for a CAVE dataset

## Usage

``` r
last_chunkedgraph_edit(datastack_name, start = 1e+05, stop = 1e+06)

last_aedes_edit(...)
```

## Arguments

- datastack_name:

  CAVE datastack name.

- start:

  Start index for search (must exist).

- stop:

  Finish index for search (must not exist).

## Value

An integer operation ID.

## Functions

- `last_aedes_edit()`: Aedes-specific wrapper.
