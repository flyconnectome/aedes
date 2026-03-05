# Find Aedes root or supervoxel (leaf) IDs for XYZ locations

Find Aedes root or supervoxel (leaf) IDs for XYZ locations

## Usage

``` r
aedes_xyz2id(
  xyz,
  rawcoords = FALSE,
  voxdims = aedes_voxdims(),
  cloudvolume.url = NULL,
  root = TRUE,
  timestamp = NULL,
  version = NULL,
  stop_layer = NULL,
  integer64 = FALSE,
  method = c("auto", "cloudvolume", "spine"),
  ...
)
```

## Arguments

- xyz:

  One or more xyz locations as an Nx3 matrix or in any form compatible
  with [`xyzmatrix`](https://rdrr.io/pkg/fafbseg/man/xyzmatrix.html)
  including `neuron` or `mesh3d` surface objects.

- rawcoords:

  whether the input values are raw voxel indices or in nm

- voxdims:

  voxel dimensions in nm used to convert raw coordinates. The default
  value uses the
  [`flywire_voxdims`](https://rdrr.io/pkg/fafbseg/man/flywire_voxdims.html)
  function to identify the value for the current segmentation (usually
  with success).

- cloudvolume.url:

  URL for CloudVolume to fetch segmentation image data. The default
  value of NULL chooses the flywire production segmentation dataset.

- root:

  Whether to return the root id of the whole segment rather than the
  supervoxel id.

- timestamp:

  An optional timestamp as a string or POSIXct, interpreted as UTC when
  no timezone is specified.

- version:

  An optional CAVE materialisation version number. See details and
  examples.

- stop_layer:

  Which layer of the chunked graph to stop at. The default `NULL` is
  equivalent to layer 1 or the full root id. Coarser layer 2 IDs can be
  a useful intermediate for some operations.

- integer64:

  Whether to return ids as integer64 type (more compact but a little
  fragile) rather than character (default `FALSE`).

- method:

  Lookup method: `"auto"` and `"spine"` use the Aedes transform service;
  `"cloudvolume"` delegates to
  [`fafbseg::flywire_xyz2id()`](https://rdrr.io/pkg/fafbseg/man/flywire_xyz2id.html).

- ...:

  Additional arguments passed to backend helpers.

## Value

A vector of segment IDs (`character` or `integer64`).

## Details

Method auto (which maps to spine) should be much faster for look ups
with many points, especially points in the same region of space.

## Examples

``` r
if (FALSE) { # \dontrun{
aedes_xyz2id(c(24606, 12450, 5798), rawcoords = TRUE, root = FALSE)
} # }
```
