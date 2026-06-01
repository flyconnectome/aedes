# Read Aedes L2 skeletons

Thin Aedes-aware wrapper around
[`fafbseg::read_l2skel()`](https://rdrr.io/pkg/fafbseg/man/read_l2skel.html).
Optionally reroots each skeleton to its soma, cascading through a
configurable set of methods.

## Usage

``` r
read_aedes_neurons(
  ids,
  units = c("nm", "raw", "microns"),
  reroot = TRUE,
  method = c("auto", "flytable", "nucleus", "l2+mesh", "l2", "mesh", "none"),
  mesh = aedes::aedes_neuropil_mesh,
  chunksize = 20L,
  cl = NULL,
  OmitFailures = TRUE,
  previous = NULL,
  version = NULL,
  timestamp = NULL,
  ...
)
```

## Arguments

- ids:

  Root IDs or a FlyTable query string compatible with
  [`aedes_ids()`](aedes_meta.md).

- units:

  Units of the returned skeletons (default `"nm"`).

- reroot:

  Whether to reroot the returned neurons.

- method:

  Reroot strategy passed through to
  [`aedes_soma_position()`](aedes_soma_position.md). With `"auto"` (the
  default) each neuron is handled by the first source that succeeds in
  the cascade: FlyTable `soma_xyz` → FlyWire nucleus → `"l2+mesh"` (a
  combined L2-attribute + neuropil signed-distance score for any neuron
  that has no FlyTable or nucleus soma; only used if a `mesh` is
  available). Restrict to a single value to disable the cascade.
  `"none"` skips rerooting (equivalent to `reroot = FALSE`).

- mesh:

  A `mesh3d` for the neuropil. Defaults to the packaged
  [aedes_neuropil_mesh](aedes_neuropil_mesh.md). Pass `NULL` to disable
  mesh-based fallback in `"auto"`; `"l2+mesh"` and `"mesh"` error
  without a mesh.

- chunksize, cl:

  Forwarded to [`aedes_soma_position()`](aedes_soma_position.md) – batch
  size for L2 attribute fetches and optional parallel cluster for chunk
  processing.

- OmitFailures:

  Passed to
  [`fafbseg::read_l2skel()`](https://rdrr.io/pkg/fafbseg/man/read_l2skel.html).

- previous:

  Optional
  [`nat::neuronlist()`](https://rdrr.io/pkg/nat/man/neuronlist.html)
  from an earlier call. Neurons whose names match requested root ids are
  reused so only missing skeletons are read. `previous` is expected to
  be in nm coordinates.

- version, timestamp:

  Optional CAVE materialisation selectors.

- ...:

  Additional arguments passed to
  [`fafbseg::read_l2skel()`](https://rdrr.io/pkg/fafbseg/man/read_l2skel.html).

## Value

A [`nat::neuronlist()`](https://rdrr.io/pkg/nat/man/neuronlist.html) of
L2 skeletons. When rerooted, each neuron's `data` slot gains
`soma_source` (`"flytable"`, `"nucleus"`, `"l2+mesh"`, `"l2"`, `"mesh"`,
or `NA`), `n_nuclei` (count of distinct-position nucleus candidates
considered, or `NA`), and `nucleus_id` (the `nuclei_v1_aedes` primary
key of the chosen row, or `NA`). `n_nuclei > 1` indicates the chosen
nucleus was one of several at distinct positions for that root id; see
[`aedes_soma_position()`](aedes_soma_position.md) for the full candidate
list.

## See also

[`aedes_soma_position()`](aedes_soma_position.md),
[aedes_neuropil_mesh](aedes_neuropil_mesh.md)

## Examples

``` r
if (FALSE) { # \dontrun{
dns <- read_aedes_neurons("class:DNa")
dns <- read_aedes_neurons("class:DNa", method = "flytable") # no fallback
dns <- read_aedes_neurons("class:DNa", reroot = FALSE)
} # }
```
