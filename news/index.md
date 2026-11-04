# Changelog

## aedes 0.5

This version adds local synapse snapshots: a downloadable copy of the
full synapse table that
[`aedes_partner_summary()`](../reference/aedes_partner_summary.md) (and
so coconatfly) can query much faster than CAVE, at the latest
materialisation or any later time including now. See the new synapse
snapshots vignette. Note also that the default `aedes.version` is now
`"now"`, and that `aedes_set_group(group = 0)` no longer ungroups (use
`group = NA`).

- New [`aedes_synapse_data()`](../reference/aedes_synapse_data.md), a
  lazy DuckDB table of all synapses in a local snapshot, optionally with
  supervoxel, position and size details.
  ([\#27](https://github.com/flyconnectome/aedes/issues/27))
- [`aedes_partner_summary()`](../reference/aedes_partner_summary.md)
  gains `method = c("auto", "cave", "local")`; `auto` answers from a
  local snapshot when one is selected.
  ([\#27](https://github.com/flyconnectome/aedes/issues/27))
- Local partner queries work at any time after the snapshot, including
  `timestamp = "now"`, by bringing snapshot rows forward with CAVE edit
  history. Results match CAVE.
  ([\#29](https://github.com/flyconnectome/aedes/issues/29))
- New [`aedes_use_snapshot()`](../reference/aedes_use_snapshot.md),
  [`aedes_update_snapshot()`](../reference/aedes_update_snapshot.md),
  [`aedes_build_snapshot()`](../reference/aedes_build_snapshot.md) and
  [`aedes_snapshot_root()`](../reference/aedes_snapshot_root.md) to
  select, update, build and locate snapshots.
  [`aedes_use_snapshot()`](../reference/aedes_use_snapshot.md) follows
  `aedes.version` when no tag is given.
  ([\#32](https://github.com/flyconnectome/aedes/issues/32),
  [\#33](https://github.com/flyconnectome/aedes/issues/33))
- New
  [`aedes_download_snapshot()`](../reference/aedes_download_snapshot.md)
  and
  [`aedes_publish_snapshot()`](../reference/aedes_download_snapshot.md).
  The download address is worked out from CAVE, so no URL is needed.
  ([\#33](https://github.com/flyconnectome/aedes/issues/33),
  [\#34](https://github.com/flyconnectome/aedes/issues/34))
- Snapshots are stored as an append-only chain of checkpoints, kept up
  to date by a server cron job (`inst/scripts/synsnap-cron.sh`) that
  makes one checkpoint a day. New `aedes.duckdb_threads` option.
  ([\#30](https://github.com/flyconnectome/aedes/issues/30),
  [\#35](https://github.com/flyconnectome/aedes/issues/35),
  [\#36](https://github.com/flyconnectome/aedes/issues/36))
- New checkpoints are downloaded automatically, checking the server at
  most every `aedes.snapshot_check_hours` hours (default 6).
  ([\#36](https://github.com/flyconnectome/aedes/issues/36))
- `aedes_synapse_data(timestamp=)` brings a snapshot forward to the
  requested time in memory, without writing to disk.
  ([\#36](https://github.com/flyconnectome/aedes/issues/36),
  [\#38](https://github.com/flyconnectome/aedes/issues/38))
- Smaller snapshot files: one root id file, zstd level 19 parquet and no
  centroid columns (`static.parquet` 2.9 GB to 1.8 GB).
  ([\#28](https://github.com/flyconnectome/aedes/issues/28),
  [\#31](https://github.com/flyconnectome/aedes/issues/31))
- Fixes for empty integer64 lookups on older bit64
  ([\#39](https://github.com/flyconnectome/aedes/issues/39)) and
  downloads of manifests listing only full snapshots
  ([\#40](https://github.com/flyconnectome/aedes/issues/40)).
- [`aedes_predict_group()`](../reference/aedes_predict_group.md) takes
  the type-derived id from the whole `aedes_main` table, so a neuron’s
  `pgroup` no longer depends on which other neurons are in the query.
  ([\#45](https://github.com/flyconnectome/aedes/issues/45))
- Documentation audit: corrected examples and descriptions, the synapse
  snapshot docs, and a new Axis conventions section in
  `aedes_neuropil_mesh` documenting the mirrored Aedes axes.
  ([\#44](https://github.com/flyconnectome/aedes/issues/44))
- `aedes_add_neurons(initials=)` sets the initials written to
  `annotator`/`proofreader`, and `initials` is no longer a required
  column (`aedes_main` has none).
  ([\#43](https://github.com/flyconnectome/aedes/issues/43))
- [`aedes_set_meta()`](../reference/aedes_set_meta.md),
  [`aedes_set_group()`](../reference/aedes_set_group.md) and
  [`aedes_add_neurons()`](../reference/aedes_add_neurons.md) never
  update rows marked `duplicate`, `bad_nucleus` or `not_a_neuron`: a
  neuron that also has a normal row is matched to that row, while one
  with only such rows is skipped with a message (and not re-added).
  These rows no longer count as group members either.
  ([\#42](https://github.com/flyconnectome/aedes/issues/42))
- `aedes_set_group(group = "<query>")` resolves the example neurons at
  the same pinned timestamp as the rest of the call, so recently edited
  examples are found.
  ([\#42](https://github.com/flyconnectome/aedes/issues/42))
- `aedes_add_neurons(soma=)` also accepts an
  [`aedes_soma_position()`](../reference/aedes_soma_position.md) method
  name, e.g. `soma = "nucleus"` to fill soma/nucleus only from the
  nucleus table.
  ([\#42](https://github.com/flyconnectome/aedes/issues/42))
- New proofreading edit history vignette. Fixes wrong operation ids in
  the edit cache for multi-chunk fetches (existing caches should be
  rebuilt) and the last-edit search stopping at gaps in operation ids.
  ([\#41](https://github.com/flyconnectome/aedes/issues/41))
- `aedes.version` now defaults to `"now"` (set on load unless already
  set), and CAVE partner queries follow it.
  [`aedes_ids()`](../reference/aedes_meta.md) /
  [`aedes_meta()`](../reference/aedes_meta.md) return FlyTable ids as is
  unless `version`/`timestamp` is given.
  ([\#37](https://github.com/flyconnectome/aedes/issues/37))
- `cf_ids(aedes=)` reports explicit ids that are replaced by older roots
  to match a version or timestamp.
  ([\#37](https://github.com/flyconnectome/aedes/issues/37))
- New [`aedes_predict_group()`](../reference/aedes_predict_group.md)
  returns a group id per neuron (from type, then group, then NBLAST
  cluster) for partner grouping in connectivity clustering.
  ([\#22](https://github.com/flyconnectome/aedes/issues/22))
- coconatfly metadata includes this as a `pgroup` column, so
  `cf_cosine_plot(group = "pgroup")` works directly; new connectivity
  clustering vignette comparing `group` and `pgroup`.
  ([\#25](https://github.com/flyconnectome/aedes/issues/25))
- [`aedes_predict_group()`](../reference/aedes_predict_group.md) uses
  `nblast_group` clusters of the form `CNNNNN` or `NNNNN`.
  ([\#25](https://github.com/flyconnectome/aedes/issues/25),
  [\#26](https://github.com/flyconnectome/aedes/issues/26))
- [`aedes_ids()`](../reference/aedes_meta.md) /
  [`aedes_meta()`](../reference/aedes_meta.md) accept neuroglancer URLs
  and comma-separated id strings. Requires `fafbseg (>= 0.15.19)`.
  ([\#24](https://github.com/flyconnectome/aedes/issues/24))
- `aedes_add_neurons(side=)` also accepts a character side value,
  written directly instead of auto-filling.
  ([\#23](https://github.com/flyconnectome/aedes/issues/23))
- Valid superclasses in
  [`aedes_add_neurons()`](../reference/aedes_add_neurons.md) examples
  and error hints.
  ([\#21](https://github.com/flyconnectome/aedes/issues/21))
- Group ids: `NA` is the ungrouped sentinel. **Breaking**:
  `aedes_set_group(group = 0)` is now an error; use `group = NA`. Root
  ids are rejected as group ids by
  [`aedes_set_group()`](../reference/aedes_set_group.md) and
  [`aedes_add_neurons()`](../reference/aedes_add_neurons.md), and
  ungrouped neurons no longer read back as group `0`.
  ([\#20](https://github.com/flyconnectome/aedes/issues/20))
- coconatfly adapter
  ([`cf_meta()`](https://natverse.org/coconatfly/reference/cf_meta.html)/[`cf_partners()`](https://natverse.org/coconatfly/reference/cf_partners.html)):
  ungrouped neurons now reach coconatfly as an `integer64` `NA` group,
  so `cf_cosine_plot(group="group")` drops them instead of collapsing
  every ungrouped partner into one spurious shared feature column.
  ([\#19](https://github.com/flyconnectome/aedes/issues/19))
- [`aedes_add_neurons()`](../reference/aedes_add_neurons.md) writes
  `root_id` and `supervoxel_id` for new rows, so re-adding a neuron
  updates its row rather than creating a duplicate.
  ([\#18](https://github.com/flyconnectome/aedes/issues/18))
- [`aedes_add_neurons()`](../reference/aedes_add_neurons.md) gains a
  `group` argument: `TRUE` groups the new neurons after insertion, or
  give an explicit group id.
  ([\#18](https://github.com/flyconnectome/aedes/issues/18))

Committed directly to `main`:

- `cf_ids(aedes=)` ignores leading/trailing commas in id lists.
  (bade4c7)
- Drop unused igraph from Imports. (a700e27)
- Synapse snapshot vignette polishing and pkgdown image fix (8c3fad7,
  f7006d6).

**Full diff**:
<https://github.com/flyconnectome/aedes/compare/v0.4...v0.5>

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
