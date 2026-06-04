# Changelog

## aedes v0.3

- New [`aedes_add_neurons()`](../reference/aedes_add_neurons.md) for
  upserting rows in the FlyTable `aedes_main` table. Pins a single
  materialisation timestamp on both the supplied ids and a fresh
  `aedes_meta(expiry=0)` read so the join-by-`root_id` is reliable, and
  computes `point_xyz` for new rows via
  [`aedes_key_point()`](../reference/aedes_key_point.md). Avoids the
  heavy
  [`aedes_flytable_update()`](../reference/aedes_flytable_update.md)
  pass. ([\#8](https://github.com/flyconnectome/aedes/issues/8))
- New [`aedes_key_point()`](../reference/aedes_key_point.md) returns a
  “good” annotation point on a neuron: the principal branch point of its
  L2 skeleton, with the neuron optionally rerooted onto its furthest
  endpoint first.
  ([\#8](https://github.com/flyconnectome/aedes/issues/8))
- [`aedes_sequential_update()`](../reference/aedes_sequential_update.md)
  gains `version` and `timestamp` arguments so callers can pin all
  downstream service calls
  ([`aedes_xyz2id()`](../reference/aedes_xyz2id.md),
  [`fafbseg::flywire_updateids()`](https://rdrr.io/pkg/fafbseg/man/flywire_updateids.html))
  to the same materialisation. Defaults to `timestamp = 'now'` when
  neither is supplied.
  ([\#8](https://github.com/flyconnectome/aedes/issues/8))
- [`read_aedes_neurons()`](../reference/read_aedes_neurons.md) wraps
  [`fafbseg::read_l2skel()`](https://rdrr.io/pkg/fafbseg/man/read_l2skel.html)
  and reroots each neuron via a per-neuron cascade: FlyTable `soma_xyz`
  →
  [`flywire_nuclei()`](https://rdrr.io/pkg/fafbseg/man/flywire_nuclei.html)
  → the packaged neuropil mesh (signed-distance fallback). Provenance
  recorded in a `soma_source` column.
  ([\#6](https://github.com/flyconnectome/aedes/issues/6))
- New [`aedes_soma_position()`](../reference/aedes_soma_position.md)
  returns one-row-per-id soma positions, matching strictly by `root_id`;
  private helper silently collapses bookkeeping duplicates in the
  nucleus table and warns only when a `root_id` has genuinely distinct
  nuclei. ([\#6](https://github.com/flyconnectome/aedes/issues/6))
- New `aedes_neuropil_mesh` dataset: `mesh3d` of the Aedes brain
  neuropil (nm coordinates), shipped via `LazyData`.
  ([\#6](https://github.com/flyconnectome/aedes/issues/6))
- New [`aedes_mirror()`](../reference/aedes_mirror.md) and related
  transforms for mirroring points and objects through the Aedes brain.
  ([\#5](https://github.com/flyconnectome/aedes/issues/5))
- `aedes_chunkedgraph_edits()` fixes data-frame assembly for chunked
  responses that include empty batches or missing names, and adds
  incremental on-disk caching for operation fetches (Arrow plus a
  missing-op sidecar).
  ([\#4](https://github.com/flyconnectome/aedes/issues/4))
- [`aedes_sequential_update()`](../reference/aedes_sequential_update.md)
  no longer loses work when individual supervoxel lookups fail.
  ([\#3](https://github.com/flyconnectome/aedes/issues/3))

## aedes v0.2

- Fast supervoxel lookups via the MRC LMB transform service
  ([`aedes_xyz2id()`](../reference/aedes_xyz2id.md) with
  `method="auto"`), \> 100x faster than cloudvolume for bulk queries.
- also features chunked requests with progress reporting and automatic
  retry at reduced chunk size on failure.
- [`aedes_sequential_update()`](../reference/aedes_sequential_update.md)
  now uses the fast transform service for supervoxel lookups.
- [`aedes_meta()`](../reference/aedes_meta.md) now wraps
  [`fafbseg::cam_meta()`](https://rdrr.io/pkg/fafbseg/man/cam_meta.html)
  for metadata queries, with improved documentation of version/timestamp
  handling.
- Refactored `aedes_cfmeta()` column renaming for robustness.
- Package hygiene: removed unused imports, added `glue`, `httr`,
  `nat.utils`, `pbapply` to Imports, pinned `fafbseg (>= 0.15.5)`.

## aedes v0.1

- Initial version on github with basic functions from 2025aedes
  aedes-dataset-funs.R
- also has docs at <https://flyconnectome.github.io/aedes>
