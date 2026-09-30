# Summarise the synaptic partners of one or more Aedes neurons

Tabulates the up- or downstream partners of a set of query neurons at a
chosen CAVE materialisation, returning one row per partner with the
number of connecting synapses. This is a thin Aedes-aware wrapper around
[`fafbseg::flywire_partner_summary()`](https://rdrr.io/pkg/fafbseg/man/flywire_partners.html):
it resolves the input via [`aedes_ids()`](aedes_meta.md), points fafbseg
at the Aedes segmentation, and updates root ids to the requested
`version`/`timestamp` before querying. When a local synapse snapshot has
been selected with
[`aedes_synapse_snapshot()`](aedes_synapse_snapshot.md) the query is
instead answered from that snapshot, at the snapshot's time.

## Usage

``` r
aedes_partner_summary(
  rootids,
  partners = c("outputs", "inputs"),
  threshold = 0,
  version = NULL,
  timestamp = NULL,
  synapse_table = getOption("coconatfly.aedes.synapses", default = "synapses_v2"),
  method = c("auto", "cave", "local"),
  ...
)
```

## Arguments

- rootids:

  Query neurons in any form accepted by [`aedes_ids()`](aedes_meta.md)
  (root ids or a FlyTable query string).

- partners:

  Whether to summarise `"outputs"` (downstream partners, the default) or
  `"inputs"` (upstream partners).

- threshold:

  Only return partners connected by more than `threshold` synapses
  (default `0`, i.e. all partners).

- version, timestamp:

  Optional CAVE materialisation selectors. When supplied, query ids are
  first updated to the corresponding version / timestamp with
  [`fafbseg::flywire_latestid()`](https://rdrr.io/pkg/fafbseg/man/flywire_latestid.html),
  and the synapse query is run against that materialisation. Give at
  most one of the two.

- synapse_table:

  CAVE synapse table to query. Defaults to the
  `coconatfly.aedes.synapses` option (`"synapses_v2"`).

- method:

  Whether to query CAVE (`"cave"`), a local synapse snapshot (`"local"`,
  see [`aedes_synapse_snapshot()`](aedes_synapse_snapshot.md)) or choose
  automatically (`"auto"`, the default; see details).

- ...:

  Additional arguments passed on to
  [`fafbseg::flywire_partner_summary()`](https://rdrr.io/pkg/fafbseg/man/flywire_partners.html).
  Power-user options include `remove_autapses` (set `FALSE` to keep
  self-connections; see examples) and `cleft.threshold`. Only
  `remove_autapses` is supported by the local method.

## Value

A `data.frame` with one row per partner neuron. `query` holds the query
neuron root id and `weight` the synapse count; the partner root id is in
`post_id` when `partners = "outputs"` and `pre_id` when
`partners = "inputs"`. See
[`fafbseg::flywire_partner_summary()`](https://rdrr.io/pkg/fafbseg/man/flywire_partners.html)
for the full column description.

## Details

With `method = "auto"` (the default) the local snapshot is used when one
is selected, no `version` is given, `timestamp` is missing or matches
the snapshot time, and `...` contains nothing other than
`remove_autapses`; otherwise CAVE is queried. Note that without a
`timestamp` a local query gives partners at the snapshot time, while a
CAVE query gives them now. `method = "local"` gives an error rather than
falling back to CAVE. The local and CAVE results should agree, apart
from CAVE's default cleft score filtering and any root 0 (unassigned)
partners, which the local method drops. The local result has `snapshot`
and `timestamp` attributes.

## See also

[`fafbseg::flywire_partner_summary()`](https://rdrr.io/pkg/fafbseg/man/flywire_partners.html),
[`aedes_ids()`](aedes_meta.md),
[`aedes_synapse_snapshot()`](aedes_synapse_snapshot.md)

## Examples

``` r
if (FALSE) { # \dontrun{
# downstream partners of a neuron, keeping only strong connections
aedes_partner_summary("720575940...", threshold = 4)

# inputs instead of outputs
aedes_partner_summary("720575940...", partners = "inputs")

# Power-user: query a specific CAVE materialisation rather than 'now'
aedes_partner_summary("720575940...", version = 1000)
aedes_partner_summary("720575940...", timestamp = "2024-01-01")

# Power-user: include autapses (self-connections). MBON11 is strongly
# autaptic, so its own root id appears among its downstream partners when
# remove_autapses = FALSE (the fafbseg default drops these).
mbon11 <- aedes_ids("cell_type:MBON11")
aedes_partner_summary(mbon11, remove_autapses = FALSE)

# answer from a local synapse snapshot
options(aedes.synapse_snapshot_root = "~/data/aedes/syn_snapshot")
aedes_synapse_snapshot()
aedes_partner_summary(mbon11, method = "local")
} # }
```
