# Lazy access to all synapses in a local snapshot

Returns a lazy dbplyr table of every synapse in a local snapshot (see
[`aedes_synapse_snapshot()`](aedes_synapse_snapshot.md)) for use with
dplyr verbs. Nothing is read until you
[`dplyr::collect()`](https://dplyr.tidyverse.org/reference/compute.html)
the result.

## Usage

``` r
aedes_synapse_data(
  side = NULL,
  static = FALSE,
  snapshot = getOption("aedes.synapse_snapshot", "latest"),
  root = getOption("aedes.synapse_snapshot_root")
)
```

## Arguments

- side:

  `"post"` to read the copy sorted by `post_root` when the snapshot has
  one. `NULL` (the default) and `"pre"` read the copy sorted by
  `pre_root`.

- static:

  Whether to add supervoxel, position and size columns.

- snapshot:

  The snapshot tag, or `"latest"` (the default) for the most recent
  snapshot in `root`.

- root:

  The snapshot folder. Defaults to the `aedes.synapse_snapshot_root`
  option.

## Value

A lazy `tbl`.

## Details

The table has columns `id`, `pre_root` and `post_root` (as `integer64`).
With `static = TRUE` it also has the columns of `static.parquet`:
`pre_sv`, `post_sv`, `pre_x`...`post_z` (raw voxel coordinates of the
pre and postsynaptic points) and `size`. Use the midpoint of the pre and
post points where you need one location per synapse.

Rows are sorted by `pre_root`, so filtering on a few `pre_root` values
lets DuckDB skip most of the file. Snapshots with a `by_post.parquet`
also keep a copy sorted by `post_root`, which `side = "post"` reads. Use
[`bit64::as.integer64()`](https://bit64.r-lib.org/reference/as.integer64.character.html)
for root ids in filters.

## See also

[`aedes_synapse_snapshot()`](aedes_synapse_snapshot.md)

## Examples

``` r
if (FALSE) { # \dontrun{
library(dplyr)
ids <- bit64::as.integer64(aedes_ids("cell_class:DNa"))
aedes_synapse_data("post") %>%
  filter(post_root %in% ids) %>%
  count(pre_root, sort = TRUE) %>%
  collect()
} # }
```
