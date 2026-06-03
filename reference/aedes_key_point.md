# Find a good "key" point on a neuron to associate with annotations

The chosen point sits at the major branch point of the L2 skeleton of
each neuron. By default the L2 skeleton is rerooted onto the endpoint
furthest from the current root so that a simplified representation with
one branch point can be calculated; without this, the longest path from
the root may not contain a branch point at all. If no branch point can
be identified the original root point is used as a fallback.

## Usage

``` r
aedes_key_point(ids, raw = TRUE, reroot = TRUE, ...)
```

## Arguments

- ids:

  One or more aedes root ids (or anything accepted by
  [`aedes_ids()`](aedes_meta.md)).

- raw:

  Whether to return points in raw (voxel) space (default) or nm.

- reroot:

  Whether to reroot the incoming neuron onto the furthest endpoint
  before simplifying.

- ...:

  Additional arguments passed to
  [`pbapply::pbsapply()`](https://peter.solymos.org/pbapply/reference/pbapply.html).

## Value

An N x 3 matrix of point locations (one row per input id).

## Examples

``` r
if (FALSE) { # \dontrun{
aedes_key_point('648518347569414567')
} # }
```
