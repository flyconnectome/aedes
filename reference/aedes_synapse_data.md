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

  `"pre"` or `"post"` to read the copy sorted by that root, or `NULL`
  (the default) for the copy sorted by synapse `id`.

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
pre and postsynaptic points), `centroid_x`... `centroid_z` and `size`.

Filtering on `pre_root` or `post_root` is fastest when `side` matches,
since the snapshot keeps a copy sorted by each and DuckDB can then skip
most of the file. Use
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
