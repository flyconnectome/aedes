# Update root_ids and supervoxel_ids from point information as necessary

Update root_ids and supervoxel_ids from point information as necessary

## Usage

``` r
aedes_sequential_update(df, version = NULL, timestamp = NULL)
```

## Arguments

- df:

  A dataframe containing columns root_id, supervoxel_id, point_xyz.

- version:

  Optional materialisation version.

- timestamp:

  Optional CAVE timestamp. Defaults to `'now'` when both timestamp and
  version missing.

## Value

A new dataframe with updated ids.

## Details

Note that point information will only be used if supervoxel information
is missing. Therefore it is essential to delete supervoxel_id for any
rows in which the point_xyz is changed.

By default `root_id`s are brought forward to the current segmentation
state (`timestamp = 'now'`). Callers may instead pin to a specific
materialisation `version` or `timestamp`.
