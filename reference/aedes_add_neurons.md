# Add new neurons (and update existing ones) in the aedes_main flytable

Upserts rows in the `aedes_main` FlyTable: absent `root_id`s are
appended, present ones are updated with any extra columns supplied via
`...` or as columns of a data.frame `ids`. This is the entry point when
you have a set of neurons that may or may not already be tracked; for
pure metadata edits on rows that are already present use
[`aedes_set_meta()`](aedes_set_meta.md), and for group assignment use
[`aedes_set_group()`](aedes_set_group.md).

Newly appended rows get an auto-computed `point_xyz` (via
[`aedes_key_point()`](aedes_key_point.md)); `supervoxel_id` and
`serial_id` are left blank and filled in server-side from `point_xyz`.
The input `ids` and a fresh read of `aedes_main` are pinned to the same
segmentation timestamp so that join-by-`root_id` is reliable.

## Usage

``` r
aedes_add_neurons(
  ids,
  dryrun = TRUE,
  ...,
  soma = TRUE,
  side = TRUE,
  status = c("adequate", "to_review", "needs_extending", "incomplete", "missing soma"),
  required = c("superclass", "status", "initials"),
  initials = getOption("aedes.initials"),
  annotator = TRUE,
  proofreader = FALSE,
  wipe = FALSE
)
```

## Arguments

- ids:

  Root ids of neurons to add or update, or a data.frame carrying a
  `root_id` column plus any per-row metadata columns (see Details). Ids
  must be valid (non-`0`, non-`NA`) flywire ids; they are brought to the
  current root id before matching.

- dryrun:

  If `TRUE` (the default) no writes are performed; the function returns
  the data frames that would have been used.

- ...:

  Additional columns to set on each row (e.g. `cell_class = "KC"`).
  Recycled across all input ids. Values here always win over the
  auto-fill below.

- soma:

  If `TRUE` (the default), auto-fill `soma_xyz` and `nucleus_id` from
  [`aedes_soma_position()`](aedes_soma_position.md).

- side:

  If `TRUE` (the default), auto-fill `side` from
  [`aedes_point_side()`](aedes_point_side.md) applied to the soma; falls
  back to the L2 key point (with a warning) for ids where the soma
  cascade returns nothing.

- status:

  FlyTable status. A shortlist of the common values is exposed in the
  signature for tab-completion. Any other value is live-checked against
  the vocabulary already present in `aedes_main`; unknown values error.
  Must be supplied unless `"status"` is removed from `required`.

- required:

  Columns that must be supplied (via `...`, or via `status` /
  `initials`). Defaults to `c("superclass", "status", "initials")`. Set
  to `character(0)` to skip the check.

- initials:

  Curator initials for the single-string `initials` column. Defaults to
  `getOption("aedes.initials")`; set once per session with
  `options(aedes.initials = "XY")`. Passed through `...` semantics – an
  explicit `initials = ...` in `...` wins over the option.

- annotator:

  Multi-select `annotator` column write policy. `TRUE` (the default)
  appends `getOption("aedes.initials")` to the cell; `FALSE` leaves the
  column alone; a character vector (or comma-joined string) appends
  those tokens explicitly. On existing rows the tokens are merged with
  the current cell contents (unique, sorted).

- proofreader:

  Multi-select `proofreader` column write policy. Same accepted values
  as `annotator`; defaults to `FALSE` (leave the column alone).

- wipe:

  If `TRUE`, replace the target multi-select column(s) with just the new
  tokens instead of merging with existing cell contents. Default `FALSE`
  (append).

## Value

A list. With `dryrun = TRUE` it has elements `up` (rows that would be
updated) and/or `new` (rows that would be appended). With
`dryrun = FALSE` only `new` is returned (so the caller can see which
`point_xyz` values were chosen).

## Details

By default the function also auto-fills `soma_xyz`, `nucleus_id` and
`side` for each row via
[`aedes_soma_position()`](aedes_soma_position.md) and
[`aedes_point_side()`](aedes_point_side.md). When the soma cascade
returns no position for an id the fallback for `side` is
[`aedes_point_side()`](aedes_point_side.md) on the L2 key point, and a
warning naming the affected ids is issued.

Auto-fill columns (`soma_xyz`, `nucleus_id`, `side`, `point_xyz`) never
overwrite a non-NA value on an existing row. Values passed via `...`
always win over the auto-fill and always overwrite on existing rows.

`ids` may instead be a data.frame with a `root_id` column; its other
columns are folded in as per-row metadata, exactly as if passed via
`...` but with one value per id rather than a single recycled value. A
column supplied in both the data.frame and `...` is an error. A
data.frame column that names an auto-fill column (`soma_xyz`,
`nucleus_id`, `side`, `point_xyz`) simply overrides the auto-fill for
that column, the same way a `...` value would.

`ids` are efficiently mapped to the latest segmentation state (with
[`fafbseg::flywire_latestid()`](https://rdrr.io/pkg/fafbseg/man/flywire_latestid.html))
before use, so distinct inputs (e.g. historical versions of one
proofread neuron) can collapse onto the same root id. Such duplicates
are dropped with a warning when every annotation column supplied via
`...` is a single value recycled across all rows. However, if any `...`
column carries multiple values (a vector longer than one) the collision
is an error, since it may not be clear which value to keep – supply
duplicate-free `ids`, or one value per column. Note that invalid ids
(`0`, `NA` or malformed) are rejected up front.

## See also

[`aedes_set_meta()`](aedes_set_meta.md) for pure metadata updates on
rows already present in `aedes_main`;
[`aedes_set_group()`](aedes_set_group.md) for group assignment;
[`aedes_key_point()`](aedes_key_point.md),
[`aedes_soma_position()`](aedes_soma_position.md),
[`aedes_point_side()`](aedes_point_side.md) for the auto-fill helpers.

## Examples

``` r
if (FALSE) { # \dontrun{
# Set your curator initials once per session (used for the annotator column
# and the required `initials` column on new rows)
options(aedes.initials = "GJ")

# Dry run first: see the frames that would be written. Two new neurons,
# both to be added as KC superclass. status is required; the shortlist
# in the signature gives tab-completion.
aedes_add_neurons(
  c("648518347569414567", "648518347399768369"),
  superclass = "KC", status = "adequate")

# Commit for real
aedes_add_neurons(
  c("648518347569414567", "648518347399768369"),
  dryrun = FALSE, superclass = "KC", status = "adequate")

# Skip soma/side auto-fill (e.g. neurons with no soma in the volume)
aedes_add_neurons("648518347569414567",
                  superclass = "KC", status = "missing soma",
                  soma = FALSE, side = FALSE)

# Per-row metadata via a data.frame: one `class`/`cell_type` per id.
df <- data.frame(
  root_id   = c("648518347569414567", "648518347399768369"),
  class     = "KC",
  cell_type = c("KCa'b'", "KCg"),
  status    = "adequate",
  stringsAsFactors = FALSE)
aedes_add_neurons(df)
} # }
```
