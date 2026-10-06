# Bring a local Aedes synapse snapshot up to date

Saves a new snapshot of the Aedes synapse table at a later time, by
applying the edits made since an existing snapshot. Queries at or near
the new snapshot time are then fast, since they need few or no CAVE
lookups.

## Usage

``` r
aedes_update_snapshot(
  timestamp = "now",
  from = "latest",
  tag = NULL,
  root = aedes_snapshot_root(),
  rebase = FALSE,
  set = TRUE
)
```

## Arguments

- timestamp:

  The time for the new snapshot: `"now"` (the default), `"latest"` for
  the time of the newest CAVE materialisation version, a POSIXct or a
  string accepted by
  [`as.POSIXct()`](https://rdrr.io/r/base/as.POSIXlt.html).

- from:

  The snapshot to start from, or `"latest"` (the default) for the most
  recent published or full snapshot in `root` at or before `timestamp`.
  Local checkpoints are skipped, so each new one is a single step from a
  published snapshot.

- tag:

  The name of the new snapshot. Defaults to the timestamp, e.g.
  `"20261001T120000"`.

- root:

  The snapshot folder. Defaults to
  [`aedes_snapshot_root()`](aedes_snapshot_root.md).

- rebase:

  Whether to also save the new snapshot as a full snapshot.

- set:

  Whether to make this the default snapshot for the session.

## Value

The result of [`aedes_use_snapshot()`](aedes_use_snapshot.md) for the
new snapshot.

## Details

Only synapses on neurons that were edited since `from` are looked up in
CAVE, so updating a day-old snapshot typically takes seconds to minutes.
The new snapshot is saved as a checkpoint: a small `log.parquet` of the
synapses whose root ids changed since `from` (typically about 1 MB per
day of edits). Reading a checkpoint combines the logs back to the last
full snapshot, which stays fast for months of edits; use `rebase = TRUE`
to also save a full snapshot (about 0.6 GB) that later checkpoints start
from.

A `timestamp` given as a time is rounded down to a whole millisecond
(the precision of CAVE edit times).

## See also

[`aedes_use_snapshot()`](aedes_use_snapshot.md)

## Examples

``` r
if (FALSE) { # \dontrun{
options(aedes.synapse_snapshot_root = "~/data/aedes/syn_snapshot")
aedes_update_snapshot()
aedes_partner_summary("class:DNa", timestamp = "now")
} # }
```
