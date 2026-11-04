# aedes 0.5

This version adds local synapse snapshots: a downloadable copy of the full
synapse table that `aedes_partner_summary()` (and so coconatfly) can query much
faster than CAVE, at the latest materialisation or any later time including
now. See the new synapse snapshots vignette. Note also that the default
`aedes.version` is now `"now"`, and that `aedes_set_group(group = 0)` no longer
ungroups (use `group = NA`).

* New `aedes_synapse_data()`, a lazy DuckDB table of all synapses in a local
  snapshot, optionally with supervoxel, position and size details. (#27)
* `aedes_partner_summary()` gains `method = c("auto", "cave", "local")`; `auto`
  answers from a local snapshot when one is selected. (#27)
* Local partner queries work at any time after the snapshot, including
  `timestamp = "now"`, by bringing snapshot rows forward with CAVE edit
  history. Results match CAVE. (#29)
* New `aedes_use_snapshot()`, `aedes_update_snapshot()`,
  `aedes_build_snapshot()` and `aedes_snapshot_root()` to select, update, build
  and locate snapshots. `aedes_use_snapshot()` follows `aedes.version` when no
  tag is given. (#32, #33)
* New `aedes_download_snapshot()` and `aedes_publish_snapshot()`. The download
  address is worked out from CAVE, so no URL is needed. (#33, #34)
* Snapshots are stored as an append-only chain of checkpoints, kept up to date
  by a server cron job (`inst/scripts/synsnap-cron.sh`) that makes one
  checkpoint a day. New `aedes.duckdb_threads` option. (#30, #35, #36)
* New checkpoints are downloaded automatically, checking the server at most
  every `aedes.snapshot_check_hours` hours (default 6). (#36)
* `aedes_synapse_data(timestamp=)` brings a snapshot forward to the requested
  time in memory, without writing to disk. (#36, #38)
* Smaller snapshot files: one root id file, zstd level 19 parquet and no
  centroid columns (`static.parquet` 2.9 GB to 1.8 GB). (#28, #31)
* Fixes for empty integer64 lookups on older bit64 (#39) and downloads of
  manifests listing only full snapshots (#40).
* `aedes_predict_group()` takes the type-derived id from the whole `aedes_main`
  table, so a neuron's `pgroup` no longer depends on which other neurons are
  in the query. (#45)
* Documentation audit: corrected examples and descriptions, the synapse
  snapshot docs, and a new Axis conventions section in `aedes_neuropil_mesh`
  documenting the mirrored Aedes axes. (#44)
* `aedes_add_neurons(initials=)` sets the initials written to
  `annotator`/`proofreader`, and `initials` is no longer a required column
  (`aedes_main` has none). (#43)
* `aedes_set_meta()`, `aedes_set_group()` and `aedes_add_neurons()` never
  update rows marked `duplicate`, `bad_nucleus` or `not_a_neuron`: a neuron
  that also has a normal row is matched to that row, while one with only such
  rows is skipped with a message (and not re-added). These rows no longer count
  as group members either. (#42)
* `aedes_set_group(group = "<query>")` resolves the example neurons at the
  same pinned timestamp as the rest of the call, so recently edited examples
  are found. (#42)
* `aedes_add_neurons(soma=)` also accepts an `aedes_soma_position()` method
  name, e.g. `soma = "nucleus"` to fill soma/nucleus only from the nucleus
  table. (#42)
* New proofreading edit history vignette. Fixes wrong operation ids in the edit
  cache for multi-chunk fetches (existing caches should be rebuilt) and the
  last-edit search stopping at gaps in operation ids. (#41)
* `aedes.version` now defaults to `"now"` (set on load unless already set), and
  CAVE partner queries follow it. `aedes_ids()` / `aedes_meta()` return
  FlyTable ids as is unless `version`/`timestamp` is given. (#37)
* `cf_ids(aedes=)` reports explicit ids that are replaced by older roots to
  match a version or timestamp. (#37)
* New `aedes_predict_group()` returns a group id per neuron (from type, then
  group, then NBLAST cluster) for partner grouping in connectivity clustering.
  (#22)
* coconatfly metadata includes this as a `pgroup` column, so
  `cf_cosine_plot(group = "pgroup")` works directly; new connectivity
  clustering vignette comparing `group` and `pgroup`. (#25)
* `aedes_predict_group()` uses `nblast_group` clusters of the form `CNNNNN` or
  `NNNNN`. (#25, #26)
* `aedes_ids()` / `aedes_meta()` accept neuroglancer URLs and comma-separated
  id strings. Requires `fafbseg (>= 0.15.19)`. (#24)
* `aedes_add_neurons(side=)` also accepts a character side value, written
  directly instead of auto-filling. (#23)
* Valid superclasses in `aedes_add_neurons()` examples and error hints. (#21)
* Group ids: `NA` is the ungrouped sentinel. **Breaking**:
  `aedes_set_group(group = 0)` is now an error; use `group = NA`. Root ids are
  rejected as group ids by `aedes_set_group()` and `aedes_add_neurons()`, and
  ungrouped neurons no longer read back as group `0`. (#20)
* coconatfly adapter (`cf_meta()`/`cf_partners()`): ungrouped neurons now reach
  coconatfly as an `integer64` `NA` group, so `cf_cosine_plot(group="group")`
  drops them instead of collapsing every ungrouped partner into one spurious
  shared feature column. (#19)
* `aedes_add_neurons()` writes `root_id` and `supervoxel_id` for new rows, so
  re-adding a neuron updates its row rather than creating a duplicate. (#18)
* `aedes_add_neurons()` gains a `group` argument: `TRUE` groups the new neurons
  after insertion, or give an explicit group id. (#18)

Committed directly to `main`:

* `cf_ids(aedes=)` ignores leading/trailing commas in id lists. (bade4c7)
* Drop unused igraph from Imports. (a700e27)
* Synapse snapshot vignette polishing and pkgdown image fix (8c3fad7, f7006d6).

**Full diff**: <https://github.com/flyconnectome/aedes/compare/v0.4...v0.5>

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
