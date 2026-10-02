# Use a local snapshot of the Aedes synapse table

Selects a downloaded snapshot of the Aedes synapse table so that
[`aedes_partner_summary()`](aedes_partner_summary.md) and
[`aedes_synapse_data()`](aedes_synapse_data.md) can answer queries
locally, without contacting CAVE for synapses. Each snapshot records the
root id of both partners of every synapse at one moment in time.

## Usage

``` r
aedes_use_snapshot(
  snapshot = NULL,
  version = NULL,
  timestamp = NULL,
  root = aedes_snapshot_root(),
  set = TRUE
)
```

## Arguments

- snapshot:

  The snapshot tag, or `"latest"` for the most recent snapshot in
  `root`. The default (`NULL`) chooses one to match `version`,
  `timestamp` or the `aedes.version` option.

- version, timestamp:

  A CAVE materialisation version or a timestamp (including `"now"`) to
  choose the snapshot for. Either one also sets the `aedes.version`
  option.

- root:

  The snapshot folder. Defaults to
  [`aedes_snapshot_root()`](aedes_snapshot_root.md).

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
or, for a checkpoint, a `log.parquet` with the synapses whose root ids
changed since its `parent` snapshot. A checkpoint is read as its full
`base` snapshot plus the logs of every checkpoint between them, so it is
only used when all of those are present. Queries use DuckDB (from the
suggested packages duckdb, DBI and dbplyr) and only read the parts of
the parquet files that they need. DuckDB uses every core; set the
`aedes.duckdb_threads` option before the first query to use fewer, e.g.
on a shared machine.

When no `snapshot` is given, the newest one at or before the requested
time is used: `timestamp` or the time of `version` when given, otherwise
the `aedes.version` option (see
[`aedes_set_version()`](aedes_set_version.md)). So by default
(`"latest"`) this is the snapshot of the newest materialisation version,
while for `"now"` it is the newest snapshot.
[`aedes_partner_summary()`](aedes_partner_summary.md) answers queries
for later times by fetching the edits made since the snapshot from CAVE
(see its details).

The `aedes.version` option is only changed when you give `version` or
`timestamp`, so that metadata and root ids from other aedes functions
match the synapse data.

If there is no snapshot in `root`, you are asked whether to download one
with [`aedes_download_snapshot()`](aedes_download_snapshot.md) (in an
interactive session) or get an error saying how to.

Every few hours (the `aedes.snapshot_check_hours` option, default 6;
`Inf` turns this off) it also downloads any new checkpoints that have
been published. A new full snapshot is only announced, since it is
larger: fetch it with
[`aedes_download_snapshot()`](aedes_download_snapshot.md).

## See also

[`aedes_partner_summary()`](aedes_partner_summary.md),
[`aedes_synapse_data()`](aedes_synapse_data.md)

## Examples

``` r
if (FALSE) { # \dontrun{
options(aedes.synapse_snapshot_root = "~/data/aedes/syn_snapshot")
aedes_use_snapshot()
# answered locally at the time of the latest materialisation
aedes_partner_summary("class:DNa")
} # }
```
