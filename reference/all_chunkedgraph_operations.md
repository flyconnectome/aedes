# Fetch all edit operations for a CAVE dataset

Finds the last operation via binary search then fetches details for all
IDs from 1 to that maximum.

## Usage

``` r
all_chunkedgraph_operations(
  datastack_name,
  last = NULL,
  compute_centroids = FALSE,
  ...
)

aedes_all_operations(...)
```

## Arguments

- datastack_name:

  CAVE datastack name.

- last:

  Optional integer; if `NULL` (default), determined automatically via
  [`last_chunkedgraph_edit()`](last_chunkedgraph_edit.md).

- compute_centroids:

  Passed to
  [`chunkedgraph_operation_details()`](chunkedgraph_operation_details.md).

- ...:

  Additional arguments passed to
  [`chunkedgraph_operation_details()`](chunkedgraph_operation_details.md).

## Value

A data.frame of all operation details.

## Functions

- `aedes_all_operations()`: Aedes-specific wrapper.
