# Changelog

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
