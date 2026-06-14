# Predict the L/R side of points in Aedes space

Applies the Aedes mirror transform to each input point and measures the
signed displacement along the mirror (X) axis before and after
transform. The sign indicates which side of the midline the point lies
on.

## Usage

``` r
aedes_point_side(
  xyz,
  units = c("nm", "raw", "microns"),
  threshold = 5000,
  rval = c("side", "distance"),
  method = c("tps", "landmarks")
)
```

## Arguments

- xyz:

  Point coordinates. Anything accepted by
  [`xyzmatrix`](https://rdrr.io/pkg/nat/man/xyzmatrix.html) (matrix,
  data.frame, neuron, neuronlist), a length-3 numeric vector for a
  single point, or a character vector of comma-separated `"x,y,z"`
  strings (the convention used by
  [`aedes_soma_position`](aedes_soma_position.md)).

- units:

  Units of the input coordinates. One of `"nm"` (the default), `"raw"`
  (image voxels, scaled via [`aedes_raw2nm`](aedes_voxdims.md)) or
  `"microns"`.

- threshold:

  Distance from the midline (in nm) below which points are reported as
  `"M"`. Default 5000 nm (~5 \\\mu\\m, ~0.7% of the x (medio-lateral)
  extent of the Aedes symmetric brain). Set to 0 to force all values to
  `"L"` or `"R"`.

- rval:

  What to return. `"side"` (the default) gives a character vector of
  side labels (`"L"`, `"R"` or `"M"`). `"distance"` gives a signed
  distance from the midline in nm (always nm, regardless of `units`),
  negative on the left, positive on the right.

- method:

  Mirror method passed to [`aedes_mirror`](aedes_mirror.md). Default
  `"tps"` uses the bundled symmetric registration and needs no network
  access.

## Value

When `rval = "side"`, a character vector of `"L"`, `"R"` or `"M"`, one
per input point, or `NA` for points whose mirror image could not be
computed. When `rval = "distance"`, a numeric vector of signed distances
from the midline in nm.

## Details

Points on the left have `dist = (mirror_x - x)/2 < 0`; points on the
right have `dist > 0`. The sign convention was calibrated against root
id `648518347465408914` (`soma_xyz = "33038,5956,3550"` in raw voxels,
side = `"L"`). Points with `|dist| <= threshold` are reported as midline
(`"M"`). With `threshold = 0` a point exactly on the midline is reported
as `"R"`.

## See also

[`aedes_mirror`](aedes_mirror.md),
[`aedes_soma_side`](aedes_soma_side.md)

## Examples

``` r
if (FALSE) { # \dontrun{
# known left-side point (raw voxel coords)
aedes_point_side(c(33038, 5956, 3550), units = "raw")

# signed distance from the midline (always in nm)
aedes_point_side(c(33038, 5956, 3550), units = "raw", rval = "distance")
} # }
```
