# Add new neurons (and update existing ones) in the aedes_main flytable

Brings the supplied `ids` to the current segmentation timestamp, reads
the `aedes_main` table fresh, and pins both sides to the same timestamp
via [`aedes_sequential_update()`](aedes_sequential_update.md) so that
join-by-`root_id` is reliable. Rows whose `root_id` is already present
are updated with any extra columns supplied via `...`; rows that are
absent are appended with a `point_xyz` computed by
[`aedes_key_point()`](aedes_key_point.md). `supervoxel_id` and
`serial_id` are left blank — a server-side process fills them in from
`point_xyz`.

## Usage

``` r
aedes_add_neurons(ids, dryrun = TRUE, ...)
```

## Arguments

- ids:

  Root ids of neurons to add or update.

- dryrun:

  If `TRUE` (the default) no writes are performed; the function returns
  the data frames that would have been used.

- ...:

  Additional columns to set on each row (e.g. `cell_class = "KC"`).
  Recycled across all input ids.

## Value

A list. With `dryrun = TRUE` it has elements `up` (rows that would be
updated) and/or `new` (rows that would be appended). With
`dryrun = FALSE` only `new` is returned (so the caller can see which
`point_xyz` values were chosen).
