# Bring a local Aedes synapse snapshot up to date

Saves a new snapshot of the Aedes synapse table at a later time, by
applying the edits made since an existing snapshot. Queries at or near
the new snapshot time are then fast, since they need few or no CAVE
lookups.

## Usage

``` r
aedes_synapse_snapshot_update(
  timestamp = "now",
  from = "latest",
  tag = NULL,
  root = aedes_synapse_snapshot_root(),
  rebase = FALSE,
  set = TRUE
)
```

## Arguments

- timestamp:

  The time for the new snapshot: a POSIXct or a string accepted by
  [`as.POSIXct()`](https://rdrr.io/r/base/as.POSIXlt.html), or `"now"`
  (the default).

- from:

  The snapshot to start from, or `"latest"` (the default) for the most
  recent snapshot in `root`.

- tag:

  The name of the new snapshot. Defaults to the timestamp, e.g.
  `"20261001T120000"`.

- root:

  The snapshot folder. Defaults to
  [`aedes_synapse_snapshot_root()`](aedes_synapse_snapshot_root.md).

- rebase:

  Whether to save a full snapshot rather than a delta.

- set:

  Whether to make this the default snapshot for the session.

## Value

The result of [`aedes_synapse_snapshot()`](aedes_synapse_snapshot.md)
for the new snapshot.

## Details

Only synapses on neurons that were edited since `from` are looked up in
CAVE, so updating a day-old snapshot typically takes seconds to minutes.
The new snapshot is saved as a small `delta.parquet` file of the
synapses that differ from the full snapshot it is based on. Each delta
holds all changes since that full snapshot, so deltas grow over time;
use `rebase = TRUE` to save a full snapshot (about 0.6 GB) that later
deltas start from.

## See also

[`aedes_synapse_snapshot()`](aedes_synapse_snapshot.md)

## Examples

``` r
if (FALSE) { # \dontrun{
options(aedes.synapse_snapshot_root = "~/data/aedes/syn_snapshot")
aedes_synapse_snapshot_update()
aedes_partner_summary("cell_class:DNa", timestamp = "now")
} # }
```
