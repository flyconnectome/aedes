# Fetch operation details from a CAVE chunkedgraph

Fetch operation details from a CAVE chunkedgraph

## Usage

``` r
chunkedgraph_operation_details(
  ops,
  datastack_name,
  chunksize = 50,
  return.data.frame = TRUE,
  ...
)

aedes_operation_details(ops, ...)
```

## Arguments

- ops:

  Integer vector of operation IDs.

- datastack_name:

  CAVE datastack name.

- chunksize:

  Number of operations per API request.

- return.data.frame:

  If `TRUE` (default), return a data.frame; otherwise return a raw named
  list.

- ...:

  Additional arguments (currently unused).

## Value

A data.frame with one row per operation (or a named list if
`return.data.frame = FALSE`).

## Functions

- `aedes_operation_details()`: Aedes-specific wrapper.
