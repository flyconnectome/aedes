# Lazy access to all synapses in a local snapshot

Returns a lazy dbplyr table of every synapse in a local snapshot (see
[`aedes_use_snapshot()`](aedes_use_snapshot.md)) for use with dplyr
verbs. Nothing is read until you
[`dplyr::collect()`](https://dplyr.tidyverse.org/reference/compute.html)
the result. This needs a local snapshot; there is no CAVE equivalent.

## Usage

``` r
aedes_synapse_data(
  side = NULL,
  details = FALSE,
  snapshot = getOption("aedes.synapse_snapshot", "latest"),
  root = aedes_snapshot_root(),
  timestamp = NULL
)
```

## Arguments

- side:

  `"post"` to read the copy sorted by `post_root` when the snapshot has
  one. `NULL` (the default) and `"pre"` read the copy sorted by
  `pre_root`.

- details:

  Whether to add supervoxel, position and size columns.

- snapshot:

  The snapshot tag, or `"latest"` for the most recent snapshot in
  `root`. Defaults to the one chosen by
  [`aedes_use_snapshot()`](aedes_use_snapshot.md).

- root:

  The snapshot folder. Defaults to
  [`aedes_snapshot_root()`](aedes_snapshot_root.md).

- timestamp:

  A time (including `"now"`) to get the synapses at, in place of
  `snapshot`.

## Value

A lazy `tbl`.

## Details

The table has columns `id`, `pre_root` and `post_root` (as `integer64`).
With `details = TRUE` it also has `pre_sv`, `post_sv`,
`pre_x`...`post_z` (raw voxel coordinates of the pre and postsynaptic
points) and `size`, from `static.parquet`. Use the midpoint of the pre
and post points where you need one location per synapse.

Rows are sorted by `pre_root`, so filtering on a few `pre_root` values
lets DuckDB skip most of the file. Snapshots with a `by_post.parquet`
also keep a copy sorted by `post_root`, which `side = "post"` reads. Use
[`bit64::as.integer64()`](https://bit64.r-lib.org/reference/as.integer64.character.html)
for root ids in filters.

With `timestamp`, the synapses are those of the newest snapshot at or
before that time when it is at most
`getOption("aedes.synapse_max_age", 60)` seconds older. Otherwise the
edits made since the newest published snapshot are looked up in CAVE
(seconds to minutes) and kept in memory for the rest of the session,
where later calls for times up to `max_age` seconds later reuse them.
Nothing is written to disk; use
[`aedes_update_snapshot()`](aedes_update_snapshot.md) to keep a
checkpoint for later sessions.

## See also

[`aedes_use_snapshot()`](aedes_use_snapshot.md)

## Examples

``` r
if (FALSE) { # \dontrun{
library(dplyr)
ids <- aedes_ids("class:DNa")
aedes_synapse_data("post") %>%
  filter(post_root %in% ids) %>%
  count(pre_root, sort = TRUE) %>%
  collect()
} # }
```
