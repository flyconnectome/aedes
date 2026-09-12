# aedes 0.4

This version includes substantial improvements to the functions for handling 
flytable metadata (especially `aedes_add_neurons()`), which should now provide 
an efficient approach to add newrows including automatic definition of key 
points on the neuron, soma location, side of brain etc.

* New `aedes_set_meta()` bulk-updates existing flytable rows. (#10)
* New `aedes_set_group()` sets group to lowest serial_id (but maintains selected
  serial number if joining an existing group in the table). (#10)
* `aedes_add_neurons()` enrichment: auto-fill `soma_xyz`/`nucleus_id`/`side`/`point_xyz`
  and require `superclass`/`status`/`initials` on new rows; also adds
  annotator/proofreader multi-select handling. (#10)
* `aedes_meta()` gains a `translate_ids` argument to ensure incoming ids match 
  the requested materialisation state so that rows are reliably selected. (#10)
* `aedes_add_neurons()` accepts a data.frame `ids` carrying a `root_id`
  column plus per-row metadata (one value per id, vs. the recycled scalars of
  `...`); a data.frame column naming an auto-fill field overrides the
  auto-fill and skips the corresponding soma/side service call. (#17)
* `aedes_meta()` / `aedes_ids()` default `expiry = 0` and document
  `expiry`/`refresh`, so metadata reads are fresh by default. Requires
  `fafbseg (>= 0.15.17)`. (#16)
* `aedes_add_neurons()`: robust handling of ids that collapse to one neuron
  after pinning — recycled scalars drop the duplicate with a warning, per-id
  values are a hard error. (#15)
* New `aedes_partner_summary()`, an Aedes-aware wrapper around
  `fafbseg::flywire_partner_summary()` (one row per synaptic partner). (#14)
* `aedes_key_point()` delegates to `fafbseg::flywire_key_point()` /
  `key_point_from_neuron()`, becoming a thin `with_aedes()` wrapper. (#13)
* `aedes_flytable_update()`: don't flag NA `root_id`s as duplicated. (#12)
* `aedes_flytable_update()`: only write columns that can change, treat NA
  `root_duplicated` as FALSE, and return the changed-rows data frame. (#11)
* New `aedes_soma_side()` / `aedes_point_side()`; predict the side of a point
  or soma. (#9)

Committed directly to `main`:

* `aedes_xyz2id()` now defaults to `mip = 1` (the LMB transform service
  dropped scale 0). (fbdbc71)
* Docs: clarify the three `aedes_main` editing functions (c25ff33); add a
  citation and Zenodo badge (d768f1c).

**Full diff**: <https://github.com/flyconnectome/aedes/compare/v0.3...v0.4>

# aedes v0.3

* New `aedes_add_neurons()` for upserting rows in the FlyTable `aedes_main`
  table. Pins a single materialisation timestamp on both the supplied ids
  and a fresh `aedes_meta(expiry=0)` read so the join-by-`root_id` is
  reliable, and computes `point_xyz` for new rows via `aedes_key_point()`.
  Avoids the heavy `aedes_flytable_update()` pass. (#8)
* New `aedes_key_point()` returns a "good" annotation point on a neuron:
  the principal branch point of its L2 skeleton, with the neuron
  optionally rerooted onto its furthest endpoint first. (#8)
* `aedes_sequential_update()` gains `version` and `timestamp` arguments so
  callers can pin all downstream service calls (`aedes_xyz2id()`,
  `fafbseg::flywire_updateids()`) to the same materialisation. Defaults
  to `timestamp = 'now'` when neither is supplied. (#8)
* `read_aedes_neurons()` wraps `fafbseg::read_l2skel()` and reroots each
  neuron via a per-neuron cascade: FlyTable `soma_xyz` → `flywire_nuclei()`
  → the packaged neuropil mesh (signed-distance fallback). Provenance
  recorded in a `soma_source` column. (#6)
* New `aedes_soma_position()` returns one-row-per-id soma positions,
  matching strictly by `root_id`; private helper silently collapses
  bookkeeping duplicates in the nucleus table and warns only when a
  `root_id` has genuinely distinct nuclei. (#6)
* New `aedes_neuropil_mesh` dataset: `mesh3d` of the Aedes brain neuropil
  (nm coordinates), shipped via `LazyData`. (#6)
* New `aedes_mirror()` and related transforms for mirroring points and
  objects through the Aedes brain. (#5)
* `aedes_chunkedgraph_edits()` fixes data-frame assembly for chunked
  responses that include empty batches or missing names, and adds
  incremental on-disk caching for operation fetches (Arrow plus a
  missing-op sidecar). (#4)
* `aedes_sequential_update()` no longer loses work when individual
  supervoxel lookups fail. (#3)

# aedes v0.2

* Fast supervoxel lookups via the MRC LMB transform service (`aedes_xyz2id()`
  with `method="auto"`), > 100x faster than cloudvolume for bulk queries.
* also features chunked requests with progress reporting and
  automatic retry at reduced chunk size on failure.
* `aedes_sequential_update()` now uses the fast transform service for
  supervoxel lookups.
* `aedes_meta()` now wraps `fafbseg::cam_meta()` for metadata queries, with
  improved documentation of version/timestamp handling.
* Refactored `aedes_cfmeta()` column renaming for robustness.
* Package hygiene: removed unused imports, added `glue`, `httr`, `nat.utils`,
  `pbapply` to Imports, pinned `fafbseg (>= 0.15.5)`.

# aedes v0.1

* Initial version on github with basic functions from 2025aedes 
aedes-dataset-funs.R
* also has docs at https://flyconnectome.github.io/aedes
