# Local Synapse Snapshots

This vignette explains how to use a local copy of the Aedes synapse
table, how to get one and keep it up to date, and how it is organised.
None of the code is run when the package is built, since it needs a
snapshot on disk and access to the aedes CAVE datastack.

## Quick Start

If you have access to the aedes CAVE datastack:

``` r

library(aedes)
aedes_download_snapshot()
aedes_partner_summary("superclass:descending_neuron", partners = "inputs")
```

The first download is about 2.3 GB; later ones normally fetch just a few
MB.

Read on for more details.

## Introduction

The Aedes synapse table has about 111 million synapses. Querying it
through CAVE is fine for a few neurons, but it is slow for tens to
thousands of neurons, especially at the latest state of the dataset. A
local synapse snapshot is a copy of the whole table as parquet files,
which aedes queries with [DuckDB](https://duckdb.org). This gives you:

- **fast queries for the latest state of the dataset (“now”)**. Only the
  edits made since the snapshot are fetched from CAVE, so you can work
  with up to date connectivity for large numbers of neurons. This is
  impractical with live CAVE queries.
- **fast partner summaries**. Thousands of neurons take seconds.
- **the full synapse table**, including the positions of the pre and
  postsynaptic points and the synapse size, for your own dplyr queries.
- **a fast local cache of a materialisation version**. CAVE (via the
  chunkedgraph) already lets you go back to any time; a snapshot makes
  repeating an analysis at one particular version fast.

## Vocabulary

| Term | Meaning |
|----|----|
| synapse table | the CAVE table with every synapse in the dataset |
| static data | the columns of the synapse table that never change: synapse id, pre and postsynaptic supervoxels, positions and size (`static.parquet`, 1.7 GB) |
| snapshot | the root ids of both partners of every synapse at one moment in time, named by a tag such as `v518` |
| base | a full snapshot (0.55 GB), usually at a CAVE materialisation version |
| delta | a snapshot stored as just the synapses whose root ids differ from its base (a few MB to tens of MB) |

## Who Does What

Most people only use snapshots:

- **download** them with
  [`aedes_download_snapshot()`](../reference/aedes_download_snapshot.md)
- **use** them with
  [`aedes_use_snapshot()`](../reference/aedes_use_snapshot.md),
  [`aedes_partner_summary()`](../reference/aedes_partner_summary.md) and
  [`aedes_synapse_data()`](../reference/aedes_synapse_data.md)
- **update** them to a later time with
  [`aedes_update_snapshot()`](../reference/aedes_update_snapshot.md) (or
  just download again)

Someone looking after the snapshots (for now on a lab server) does the
rest:

- **build** the static data and a first base with
  [`aedes_build_snapshot()`](../reference/aedes_build_snapshot.md)
- **make** daily deltas and occasional new bases with
  [`aedes_update_snapshot()`](../reference/aedes_update_snapshot.md)
- **distribute** them with
  [`aedes_publish_snapshot()`](../reference/aedes_download_snapshot.md)

## Using a Snapshot

You select a snapshot once per session. The snapshot folder is found by
[`aedes_snapshot_root()`](../reference/aedes_snapshot_root.md).

``` r

library(aedes)
library(dplyr)
aedes_use_snapshot()
#> Using synapse snapshot 'v518' (2026-09-30 14:12:29 UTC)
```

[`aedes_use_snapshot()`](../reference/aedes_use_snapshot.md) respects
the version you have chosen for other aedes functions (see
[`aedes_set_version()`](../reference/aedes_set_version.md)). By default
this is `"latest"`, the newest CAVE materialisation version, so you get
the snapshot made at that version. With `aedes_set_version("now")` you
get the newest snapshot, which is then brought up to the present on the
fly. You can also ask for a specific `version` or `timestamp`; this also
changes the default for the other aedes functions so that metadata and
connectivity match.

``` r

aedes_use_snapshot(timestamp = "now")
aedes_use_snapshot(version = 513)
```

Partner summaries are now answered locally:

``` r

aedes_partner_summary("superclass:descending_neuron", partners = "inputs")
```

You can ask about later times than the snapshot, including
`timestamp = "now"`. In this case
[`aedes_partner_summary()`](../reference/aedes_partner_summary.md)
fetches just the edits made since the snapshot from CAVE and looks up
new root ids for the synapses that they affect. The update is kept for
the rest of the session, so only the first query after a long gap is
slow.

``` r

aedes_partner_summary("superclass:descending_neuron", partners = "inputs",
                      timestamp = "now")
```

For anything else,
[`aedes_synapse_data()`](../reference/aedes_synapse_data.md) gives you a
lazy table of every synapse that works with dplyr verbs. Nothing is
actually read until you
[`collect()`](https://dplyr.tidyverse.org/reference/compute.html) the
result. For example to count the inputs onto descending neurons by
presynaptic partner:

``` r

dns <- aedes_ids("superclass:descending_neuron")
aedes_synapse_data("post") %>%
  filter(post_root %in% dns) %>%
  count(pre_root, sort = TRUE) %>%
  collect()
```

Root ids come back as `integer64` columns, but you can filter with the
character ids that [`aedes_ids()`](../reference/aedes_meta.md) returns.
With `details = TRUE` the table also has supervoxel ids, the positions
of the pre and postsynaptic points and the synapse size. Note that
[`aedes_synapse_data()`](../reference/aedes_synapse_data.md) reads the
selected snapshot exactly as it is; it does not apply later edits.

## Getting a Snapshot

[`aedes_download_snapshot()`](../reference/aedes_download_snapshot.md)
reads a `manifest.json` from the server where the snapshots are
published (working out its address needs access to the aedes CAVE
datastack) and downloads any snapshots that you don’t have yet, into
[`aedes_snapshot_root()`](../reference/aedes_snapshot_root.md). Every
file is checked against its md5 and the download resumes after an
interruption, so if anything goes wrong just run it again. Snapshots
never change once made, so a later download only fetches new ones:
normally a small delta, and occasionally a new base.

To bring a snapshot up to date yourself:

``` r

aedes_update_snapshot()
#> Updating synapse snapshot 'v518' (2026-09-30 14:12:29 UTC) to
#> 2026-10-01 12:00:00 UTC (now)
```

This only looks up synapses on neurons that have been edited since the
snapshot, so a daily update takes seconds to minutes. Use
`aedes_update_snapshot("latest")` for the time of the newest
materialisation version instead.

## Building and Publishing Snapshots

This section is for whoever looks after the snapshots.
[`aedes_build_snapshot()`](../reference/aedes_build_snapshot.md) builds
everything from scratch:

``` r

aedes_build_snapshot()
```

This does two things:

1.  downloads the source edgelist behind the CAVE synapse table (22 GB),
    checks its md5 and converts it to `static.parquet`. The file is
    found from the description of the CAVE table, so you need access to
    the aedes datastack.
2.  looks up the root id of every supervoxel at the newest
    materialisation version to make the first base, e.g. `v518`.

It takes a few hours and needs about 25 GB of free space while it runs,
but only 2.3 GB once it has finished. If you have the Google Cloud CLI
(`gcloud`) installed the download is quicker; otherwise `curl` is used.
If anything goes wrong just run it again with the same `version` and it
will carry on where it stopped. Before a new base is used, the synapses
of 20 neurons of very different sizes are compared with a CAVE query at
the same version. A snapshot that fails this check is moved aside rather
than used.

After that, a daily job makes a delta for the present and publishes it:

``` r

aedes_update_snapshot()
aedes_publish_snapshot("/path/to/served/folder")
```

[`aedes_publish_snapshot()`](../reference/aedes_download_snapshot.md)
hard links the static data, the newest snapshot and its base into a
folder served over https and writes `manifest.json` last. Deltas grow as
proofreading continues, so every so often (e.g. at a new materialisation
version) make a new base with
`aedes_update_snapshot("latest", rebase = TRUE)`.

## How It Works

### Layout

A snapshot folder holds the static data and a small folder for each
snapshot:

    syn_snapshot/
      static.parquet     id, pre_sv, post_sv, positions, size    1.7 GB
      static.json        source table and md5
      v518/              base
        meta.json        tag, timestamp
        by_pre.parquet   id, pre_root, post_root                 0.55 GB
      20261001T120000/   delta
        meta.json        tag, timestamp, base = "v518"
        delta.parquet    rows that differ from v518              a few MB

The split follows how the data actually change. Supervoxels, positions
and sizes are fixed once synapses have been detected; proofreading only
changes which root id each supervoxel belongs to. So each snapshot only
stores the root ids of the two partners of each synapse, and the static
columns are joined on `id` when you ask for them (`details = TRUE`).

`by_pre.parquet` is sorted by presynaptic root id. Parquet files store
the minimum and maximum of each column for each block of rows (a row
group), so DuckDB can skip most of the file when filtering on a few
`pre_root` values. An optional copy sorted by postsynaptic root
(`by_post.parquet`) speeds up input queries for small numbers of
neurons.

### Deltas

A delta records every row that differs from its base, not just the
changes since the previous delta. This means that reading any snapshot
needs at most two files: the rows of the base whose `id` is not in the
delta, plus the delta itself. It also means that you only ever need to
download the newest delta. The price is that deltas grow as proofreading
continues, until the next base.

### Safety

- snapshots are built in `.staging/` and only moved into place once they
  are complete and have been checked
- `meta.json` (for each snapshot), `static.json` and the published
  `manifest.json` are always the last files written
- parquet files are written to a temporary name and then renamed, so a
  half-written file never looks finished
- the slow steps of a build (the download and the root id lookup, which
  is saved in chunks of a million supervoxels) and downloads can resume
  after a failure

There is no locking, so only one process should write to a snapshot
folder at a time. Any number of R sessions can read from it.

## Comparison with the CAVE Delta Lake Export

The CAVE materialization engine can now export a materialisation version
as a [Delta Lake](https://delta.io) table
([MaterializationEngine#220](https://github.com/CAVEconnectome/MaterializationEngine/pull/220);
see the `deltalake_query` notebook in
[CAVEColab](https://github.com/CAVEconnectome/CAVEColab) for an
example). Each version is a full copy of the synapse table, written once
for each indexed column (e.g. pre and postsynaptic root id, or position)
so that each copy is partitioned and sorted for queries on that column,
in files of about 256 MB with extra indexes (bloom filters) to skip
files quickly.

This makes it possible to query the export **remotely**: a client such
as polars or DuckDB reads just the parts of the files it needs with
HTTPS range requests, with no load on the CAVE server. This works well
for a handful of neurons at a materialisation version, but gets slower
when the synapses you want are spread across many files, and it can’t
answer questions about the present (“now”).

|  | aedes snapshots | CAVE Delta Lake export |
|----|----|----|
| Where queries run | locally, after a download | remotely (range reads) or locally |
| Up front | 1.7 GB static data once, plus a 0.55 GB base | nothing for remote queries |
| Times available | snapshot times, and “now” via CAVE edits | materialisation versions |
| Each new time | a delta of a few MB to tens of MB | a full copy of the table per version |
| Unchanged columns | stored once in `static.parquet` | rewritten with every version |
| Best for | many neurons, the latest state | a few neurons at a version, no setup |

Our approach depends on two features of the synapse table:

- **updates are narrow.** A day of proofreading edits a few hundred
  neurons. Many supervoxels then belong to new root ids, but only the
  synapses on those neurons change, a small fraction of the 111 million
  rows, and the static columns are never touched. So after a one-time
  download of the static data and a base, each new time costs a small
  delta.
- **there is a single writer.** So the only guarantee we need is that
  readers never see a half-built snapshot, which staging plus a rename
  provides.

The result is a set of ordinary parquet files that DuckDB, arrow or
pandas can read directly.
