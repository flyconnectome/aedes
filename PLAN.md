# aedes package plan

## Goal
Create `aedes` as a thin wrapper around `fafbseg`, mirroring the `fancr` style for Aedes-specific dataset access and helpers.

## Current status
- Package renamed from `raedes` to `aedes`.
- Project path: `/Users/jefferis/dev/R/aedes`.
- RStudio project: `aedes.Rproj`.
- Package name in `DESCRIPTION` and tests now `aedes`.
- Roxygen-driven exports and docs are in place.

## Implemented so far
- Dataset switching/version API:
  - `choose_aedes()`
  - `with_aedes()`
  - `aedes_set_version()`
  - `aedes_get_version()`
- Coordinate helpers (fancr-style):
  - `aedes_voxdims()`
  - `aedes_nm2raw()`
  - `aedes_raw2nm()`
- CAVE helpers:
  - `aedes_cave_client()`
  - `aedes_cave_query()`
- coconat integration:
  - `register_aedes_coconat()` (explicit registration; no auto-registration side effect)
  - internal helper functions restored for registration/meta/partner flows
- Test coverage:
  - core API tests added in `tests/testthat/test-core-api.R`
  - conditional coconat/FlyTable query test added (skips cleanly without access)

## Current file structure
- `R/urls.R`
- `R/meta.R`
- `R/flytable.R`
- `R/coords.R`
- `R/cave.R`
- `R/coconat.R`
- `R/aedes-package.R`

## Upstream exports needed to eliminate `:::` calls
The following unexported functions are used via `:::` and should be exported
from their respective packages:

- **`valid_id()`** — used in `R/meta.R` to distinguish numeric root IDs from
  text queries. Candidate packages: `nat.utils` or `coconat` (general-purpose
  utility, not fafbseg-specific).
- **`flywire_version()`** — used in `R/meta.R` and `R/coconat.R` to resolve
  materialisation version specs (e.g. `"latest"` → integer). Export from
  `fafbseg`.
- **`flywire_expandurl()`** — used in `R/urls.R` to expand shortened
  Neuroglancer state URLs. Export from `fafbseg`.

## Next steps
1. Decide whether `aedes_meta()` should be exported in v0.1 (currently internal).
2. Add focused unit tests for:
   - `aedes_meta()` query parsing and duplicate handling
   - `aedes_cave_query()` argument passthrough behavior
3. Add a lightweight vignette/README examples for:
   - `choose_aedes()`/`with_aedes()`
   - `aedes_voxdims()` and coordinate conversion
   - `register_aedes_coconat()` usage
4. Run full package checks (`devtools::check()`) in a session with required access and resolve any environment-specific notes.

## Docs approach
Keep documentation minimal while API settles.
Rehydrate richer roxygen text selectively from:
`/Users/Shared/projects/2025aedes/R/funs/aedes-dataset-funs.R`
for functions that are confirmed as stable public API.
