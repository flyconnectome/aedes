# Handle raw and nm calibrated Aedes coordinates

`aedes_voxdims()` returns image voxel dimensions used to scale between
raw and nm coordinates.

## Usage

``` r
aedes_voxdims(url = choose_aedes(set = FALSE)[["fafbseg.sampleurl"]])

aedes_nm2raw(x, vd = aedes_voxdims())

aedes_raw2nm(x, vd = aedes_voxdims())
```

## Arguments

- url:

  Optional Neuroglancer URL containing voxel size metadata. Defaults to
  the active Aedes sample URL.

- x:

  3D coordinates in any form compatible with
  [`nat::xyzmatrix()`](https://rdrr.io/pkg/nat/man/xyzmatrix.html).

- vd:

  Voxel dimensions in nm. Advanced use; normally detected automatically.

## Value

For `aedes_voxdims()`, a numeric 3-vector.

For `aedes_raw2nm()` and `aedes_nm2raw()`, an N x 3 numeric matrix.

## Examples

``` r
if (FALSE) { # \dontrun{
aedes_voxdims()
} # }
if (FALSE) { # \dontrun{
aedes_raw2nm(c(159144, 22192, 3560))
aedes_nm2raw(c(2546304, 355072, 160200))
} # }
```
