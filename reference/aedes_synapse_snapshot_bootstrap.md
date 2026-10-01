# Build the synapse snapshot from scratch

Builds a complete local synapse snapshot on a new machine: downloads the
edgelist behind the CAVE synapse table, converts it to `static.parquet`,
then looks up the root ids of every synapse at a materialisation version
to make the snapshot `v<version>`. This takes a few hours and needs
about 25 GB of free space while it runs (2 GB after).

## Usage

``` r
aedes_synapse_snapshot_bootstrap(
  root = aedes_synapse_snapshot_root(create = TRUE),
  version = NULL,
  keep_source = FALSE,
  n_verify = 20,
  by_post = FALSE
)
```

## Arguments

- root:

  Folder for the snapshot (created if needed).

- version:

  A CAVE materialisation version; `NULL` for the newest one that is
  available for at least a day.

- keep_source:

  Whether to keep the downloaded source file (in `<root>/.staging`).

- n_verify:

  Number of neurons to compare with CAVE.

- by_post:

  Whether to also write a copy of the root ids sorted by postsynaptic
  root (see [`aedes_synapse_data()`](aedes_synapse_data.md)).

## Value

The snapshot tag, invisibly.

## Details

The source file (a 22 GB csv) is found from the description of the CAVE
synapse table, so you need access to the aedes CAVE datastack. It is
downloaded with `gcloud storage cp` when the Google Cloud CLI is
installed (fastest), otherwise with `curl`, and checked against its md5.
It is deleted once `static.parquet` has been written unless
`keep_source = TRUE`. `static.json` records the CAVE table name and md5
of the source file.

Root ids are looked up at the time of the materialisation `version`: by
default the newest available version that does not expire within a day.
The lookup is saved in chunks as it goes, so if it is interrupted (or
the server fails) just run `aedes_synapse_snapshot_bootstrap()` again
with the same `version` to carry on. Nothing is visible as a snapshot
until it is complete and has been checked: the synapses of `n_verify`
neurons of different sizes are compared with a CAVE query at the same
version, and a snapshot with any difference is moved to `<root>/.failed`
instead.

Later snapshots are built as small deltas against this one by
[`aedes_synapse_snapshot_update()`](aedes_synapse_snapshot_update.md).

## See also

[`aedes_synapse_snapshot()`](aedes_synapse_snapshot.md),
[`aedes_synapse_snapshot_update()`](aedes_synapse_snapshot_update.md)

## Examples

``` r
if (FALSE) { # \dontrun{
aedes_synapse_snapshot_bootstrap()
aedes_synapse_snapshot()
} # }
```
