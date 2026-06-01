# Look up the soma position for one or more Aedes neurons

Returns the recorded soma position (in nm) for each input root id, using
FlyTable annotations and/or the FlyWire nucleus segmentation.

## Usage

``` r
aedes_soma_position(
  ids,
  method = c("auto", "flytable", "nucleus", "l2+mesh", "l2", "mesh"),
  units = c("nm", "raw"),
  nuclei = c("largest", "all"),
  mesh = aedes::aedes_neuropil_mesh,
  chunksize = 20L,
  cl = NULL,
  version = NULL,
  timestamp = NULL
)
```

## Arguments

- ids:

  Root IDs or a FlyTable query string accepted by
  [`aedes_ids()`](aedes_meta.md).

- method:

  One of `"auto"`, `"flytable"`, `"nucleus"`, `"l2+mesh"`, `"l2"`, or
  `"mesh"`. With `"auto"` (the default) the function tries FlyTable's
  `soma_xyz` first, falls back to
  [`fafbseg::flywire_nuclei()`](https://rdrr.io/pkg/fafbseg/man/flywire_nuclei.html)
  for any neuron without a recorded soma, and – when a `mesh` is
  available – finally falls back to a combined L2-attribute + neuropil
  signed-distance score (`"l2+mesh"`). Restricting `method` skips the
  cascade. `"l2"` uses only the L2 shape features (area, distance
  transform, roundness, size); `"mesh"` uses only the signed distance
  and errors if `mesh = NULL`.

- units:

  Units of the returned coordinates: `"nm"` (default) or `"raw"` voxel
  coordinates. FlyTable's `soma_xyz` is always stored as raw voxel
  coordinates and is converted to nm via
  [`aedes_raw2nm()`](aedes_voxdims.md) before being returned (unless
  `units = "raw"`).

- nuclei:

  How to handle root ids with more than one *distinct-position* nucleus
  in the nucleus segmentation. `"largest"` (the default) returns one row
  per input id, picking the nucleus with the largest `volume` (or the
  first row when no `volume` column is available). `"all"` returns every
  candidate row, so an ambiguous root id contributes more than one row.
  Either way, bookkeeping duplicates (rows with identical position for
  the same root id) are silently collapsed, and `n_nuclei` records how
  many distinct-position candidates were considered.

- mesh:

  A `mesh3d` of the neuropil for the mesh-based scoring methods.
  Defaults to [aedes_neuropil_mesh](aedes_neuropil_mesh.md). Pass `NULL`
  to disable mesh-based fallback in `"auto"`.

- chunksize:

  Number of neurons per batched L2-attribute fetch when the cascade
  reaches `"l2+mesh"` / `"l2"` / `"mesh"`. Larger values reduce CAVE
  round-trip overhead at the cost of larger responses. Default 20 trades
  off well in practice; pass `1L` to revert to per-neuron fetches.

- cl:

  Optional parallel cluster (or integer worker count) passed to
  [`pbapply::pblapply()`](https://peter.solymos.org/pbapply/reference/pbapply.html)
  for chunk processing. `NULL` (default) runs sequentially with a
  progress bar. Useful when scoring hundreds to thousands of neurons via
  L2.

- version, timestamp:

  Optional CAVE materialisation selectors passed through to
  [`aedes_meta()`](aedes_meta.md) and
  [`fafbseg::flywire_nuclei()`](https://rdrr.io/pkg/fafbseg/man/flywire_nuclei.html).
  Defaults to timestamp='now' if no user supplied selector.

## Value

A data.frame with columns `root_id`; `position` (a `"x,y,z"` string in
the requested `units`; convert back with
[`nat::xyzmatrix()`](https://rdrr.io/pkg/nat/man/xyzmatrix.html));
`source` (`"flytable"`, `"nucleus"`, `"l2+mesh"`, `"l2"`, `"mesh"`, or
`NA`); `n_nuclei` (the number of distinct-position nucleus candidates
for that root id, or `NA` when the soma came from elsewhere / was not
found); and `nucleus_id` (the `nuclei_v1_aedes` primary key, from
FlyTable when `source = "flytable"` or from the chosen nucleus row when
`source = "nucleus"`). L2-derived rows also include `soma_score`
(absolute, cross-neuron-comparable; squared Mahalanobis distance of the
chunk's shape features from the KC positive cloud, plus a KDE-based
penalty on signed neuropil distance – *lower = more soma-like*; see
[aedes_soma_l2_stats](aedes_soma_l2_stats.md)), `dist_npil_nm` (signed
distance to the neuropil mesh, in nm; positive inside, negative outside
– soma rows are in cortex so this is usually negative), and `l2_id` (the
selected L2 chunk). These columns are `NA` for non-L2 sources. With
`nuclei = "largest"` there is one row per input id in input order; with
`nuclei = "all"` rows are ordered by input id but ambiguous ids
contribute multiple rows (sorted by descending volume).

## See also

[`read_aedes_neurons()`](read_aedes_neurons.md)

## Examples

``` r
if (FALSE) { # \dontrun{
aedes_soma_position("class:DNa")
aedes_soma_position("class:DNa", units = "raw")
aedes_soma_position("648518347517945383", nuclei = "all")
aedes_soma_position(c("648518347528739642", "648518347497973071"),
                    method = "flytable")
} # }
```
