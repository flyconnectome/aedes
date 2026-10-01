# Use a local snapshot of the Aedes synapse table

Selects a downloaded snapshot of the Aedes synapse table so that
[`aedes_partner_summary()`](aedes_partner_summary.md) and
[`aedes_synapse_data()`](aedes_synapse_data.md) can answer queries
locally, without contacting CAVE for synapses. Each snapshot records the
root id of both partners of every synapse at one moment in time.

## Usage

``` r
aedes_synapse_snapshot(
  snapshot = "latest",
  root = aedes_synapse_snapshot_root(),
  set = TRUE
)
```

## Arguments

- snapshot:

  The snapshot tag, or `"latest"` (the default) for the most recent
  snapshot in `root`.

- root:

  The snapshot folder. Defaults to
  [`aedes_synapse_snapshot_root()`](aedes_synapse_snapshot_root.md).

- set:

  Whether to make this the default snapshot for the session.

## Value

When `set = TRUE`, the previous option values (invisibly, suitable for
passing to [`options()`](https://rdrr.io/r/base/options.html)).
Otherwise a list with the snapshot `tag`, `timestamp` and `root`.

## Details

A snapshot folder contains `static.parquet` (one row per synapse, with
its supervoxels, positions and size) and one sub-folder per snapshot
tag. A tag folder has a `meta.json` with the snapshot `timestamp` and
either the full root id table (`by_pre.parquet`, sorted by presynaptic
root, plus an optional `by_post.parquet` sorted by postsynaptic root)
or, for a delta snapshot, a `delta.parquet` with the rows that differ
from its full `base` snapshot. Queries use DuckDB (from the suggested
packages duckdb, DBI and dbplyr) and only read the parts of the parquet
files that they need.

Selecting a snapshot with `set = TRUE` also sets the `aedes.version`
option to the snapshot's timestamp (see
[`aedes_set_version()`](aedes_set_version.md)), so that metadata and
root ids from other aedes functions match the synapse data.
[`aedes_partner_summary()`](aedes_partner_summary.md) can still answer
queries for later times, including `timestamp = "now"`, by fetching the
edits made since the snapshot from CAVE (see its details).

## See also

[`aedes_partner_summary()`](aedes_partner_summary.md),
[`aedes_synapse_data()`](aedes_synapse_data.md)

## Examples

``` r
if (FALSE) { # \dontrun{
options(aedes.synapse_snapshot_root = "~/data/aedes/syn_snapshot")
aedes_synapse_snapshot()
# now answered locally at the snapshot time
aedes_partner_summary("cell_class:DNa")
} # }
```
