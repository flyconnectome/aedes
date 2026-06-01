# Mesh of the Aedes neuropil

A `mesh3d` (rgl) object covering the Aedes brain neuropil, in nm
coordinates. Constructed by Dana Sherman from the synapse cloud. See
`data-raw/aedes_neuropil_mesh.R` for the regeneration script.

## Usage

``` r
aedes_neuropil_mesh
```

## Format

An object of class `mesh3d` (inherits from `shape3d`) of length 6.

## Examples

``` r
if (FALSE) { # \dontrun{
library(nat)
wire3d(aedes_neuropil_mesh, col='grey')
# negative implies outside the mesh
pointsinside(matrix(c(2e5, 3e5, 1e5), ncol = 3),
             surf = aedes_neuropil_mesh, rval = "dist")
} # }
```
