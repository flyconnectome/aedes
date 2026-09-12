# Changelog

## aedes 0.4

This version includes substantial improvements to the functions for
handling flytable metadata (especially
[`aedes_add_neurons()`](../reference/aedes_add_neurons.md)), which
should now provide an efficient approach to add newrows including
automatic definition of key points on the neuron, soma location, side of
brain etc.

- New [`aedes_set_meta()`](../reference/aedes_set_meta.md) bulk-updates
  existing flytable rows.
  ([\#10](https://github.com/flyconnectome/aedes/issues/10))
- New [`aedes_set_group()`](../reference/aedes_set_group.md) sets group
  to lowest serial_id (but maintains selected serial number if joining
  an existing group in the table).
  ([\#10](https://github.com/flyconnectome/aedes/issues/10))
- [`aedes_add_neurons()`](../reference/aedes_add_neurons.md) enrichment:
  auto-fill `soma_xyz`/`nucleus_id`/`side`/`point_xyz` and require
  `superclass`/`status`/`initials` on new rows; also adds
  annotator/proofreader multi-select handling.
  ([\#10](https://github.com/flyconnectome/aedes/issues/10))
- [`aedes_meta()`](../reference/aedes_meta.md) gains a `translate_ids`
  argument to ensure incoming ids match the requested materialisation
  state so that rows are reliably selected.
  ([\#10](https://github.com/flyconnectome/aedes/issues/10))
- [`aedes_add_neurons()`](../reference/aedes_add_neurons.md) accepts a
  data.frame `ids` carrying a `root_id` column plus per-row metadata
  (one value per id, vs. the recycled scalars of `...`); a data.frame
  column naming an auto-fill field overrides the auto-fill and skips the
  corresponding soma/side service call.
  ([\#17](https://github.com/flyconnectome/aedes/issues/17))
- [`aedes_meta()`](../reference/aedes_meta.md) /
  [`aedes_ids()`](../reference/aedes_meta.md) default `expiry = 0` and
  document `expiry`/`refresh`, so metadata reads are fresh by default.
  Requires `fafbseg (>= 0.15.17)`.
  ([\#16](https://github.com/flyconnectome/aedes/issues/16))
- [`aedes_add_neurons()`](../reference/aedes_add_neurons.md): robust
  handling of ids that collapse to one neuron after pinning — recycled
  scalars drop the duplicate with a warning, per-id values are a hard
  error. ([\#15](https://github.com/flyconnectome/aedes/issues/15))
- New
  [`aedes_partner_summary()`](../reference/aedes_partner_summary.md), an
  Aedes-aware wrapper around
  [`fafbseg::flywire_partner_summary()`](https://rdrr.io/pkg/fafbseg/man/flywire_partners.html)
  (one row per synaptic partner).
  ([\#14](https://github.com/flyconnectome/aedes/issues/14))
- [`aedes_key_point()`](../reference/aedes_key_point.md) delegates to
  [`fafbseg::flywire_key_point()`](https://rdrr.io/pkg/fafbseg/man/key_point_from_neuron.html)
  /
  [`key_point_from_neuron()`](https://rdrr.io/pkg/fafbseg/man/key_point_from_neuron.html),
  becoming a thin [`with_aedes()`](../reference/choose_aedes.md)
  wrapper. ([\#13](https://github.com/flyconnectome/aedes/issues/13))
- [`aedes_flytable_update()`](../reference/aedes_flytable_update.md):
  don’t flag NA `root_id`s as duplicated.
  ([\#12](https://github.com/flyconnectome/aedes/issues/12))
- [`aedes_flytable_update()`](../reference/aedes_flytable_update.md):
  only write columns that can change, treat NA `root_duplicated` as
  FALSE, and return the changed-rows data frame.
  ([\#11](https://github.com/flyconnectome/aedes/issues/11))
- New [`aedes_soma_side()`](../reference/aedes_soma_side.md) /
  [`aedes_point_side()`](../reference/aedes_point_side.md); predict the
  side of a point or soma.
  ([\#9](https://github.com/flyconnectome/aedes/issues/9))

Committed directly to `main`:

- [`aedes_xyz2id()`](../reference/aedes_xyz2id.md) now defaults to
  `mip = 1` (the LMB transform service dropped scale 0). (fbdbc71)
- Docs: clarify the three `aedes_main` editing functions (c25ff33); add
  a citation and Zenodo badge (d768f1c).

**Full diff**:
<https://github.com/flyconnectome/aedes/compare/v0.3...v0.4>

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
