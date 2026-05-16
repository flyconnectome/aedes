# Populate the on-disk operation cache from an existing data.frame

Useful for seeding the cache from previously fetched results.

## Usage

``` r
populate_chunkedgraph_ops_cache(
  df,
  datastack_name,
  cache = rappdirs::user_cache_dir("aedes", appauthor = FALSE)
)
```

## Arguments

- df:

  A data.frame of operation details as returned by
  [`chunkedgraph_operation_details()`](chunkedgraph_operation_details.md).

- datastack_name:

  CAVE datastack name.

- cache:

  Cache directory. Defaults to the user cache dir managed by `rappdirs`.
