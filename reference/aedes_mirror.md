# Mirror Aedes neurons or points to the opposite side of the brain

`aedes_mirror()` mirrors objects supported by
[`nat::xform()`](https://rdrr.io/pkg/nat/man/xform.html), including
neurons, neuronlists, dotprops and coordinate matrices.

## Usage

``` r
aedes_mirror(
  x,
  method = c("tps", "landmarks", "symmetric"),
  units = c("microns", "nm"),
  subset = NULL,
  landmarks = NULL,
  raw = TRUE,
  url = .aedes_mirror_landmarks_url,
  vd = NULL,
  ...
)
```

## Arguments

- x:

  An object to mirror.

- method:

  Mirror method. `"tps"` uses the bundled `aedes_aedesSym_1000_tps.rds`
  registration to map into Aedes symmetric space, flip across the X
  axis, then map back to original Aedes space. `"landmarks"` uses paired
  landmarks in the original Aedes space.

- units:

  Coordinate units for `x` and the returned object. The symmetric
  registration is defined in microns; nm inputs are scaled before and
  after transformation.

- subset:

  Optional subset passed to
  [`nat::xform()`](https://rdrr.io/pkg/nat/man/xform.html) for the
  landmarks method. The TPS method currently mirrors the whole object.

- landmarks:

  Optional landmark data with `pointA` and `pointB` entries. When
  `NULL`, landmarks are read from `url` using
  [`fafbseg::ngl_annotations()`](https://rdrr.io/pkg/fafbseg/man/ngl_annotations.html).

- raw:

  Whether landmark coordinates are in raw voxel space. When `FALSE`,
  landmark coordinates are assumed to be in `units`.

- url:

  Neuroglancer URL containing paired mirror landmarks.

- vd:

  Optional voxel dimensions in nm. Advanced use; when `NULL` and
  `raw = TRUE`, these are detected automatically.

- ...:

  Additional arguments passed to
  [`nat::xform()`](https://rdrr.io/pkg/nat/man/xform.html).

## Value

A transformed object of the same kind as `x`.

## Details

TPS mirroring requires the suggested `Morpho` package at runtime.

## Examples

``` r
if (FALSE) { # \dontrun{
sk <- with_aedes(fafbseg::read_l2skel(aedes_ids("class:DNa")[1]))
sk.tps.mirror <- aedes_mirror(sk / 1000)
sk.landmark.mirror <- aedes_mirror(sk / 1000, method = "landmarks")

dps <- with_aedes(fafbseg::read_l2dp(aedes_ids("class:DNa")))
dps.tps.mirror <- aedes_mirror(dps)
dps.landmark.mirror <- aedes_mirror(dps, method = "landmarks")
} # }
```
