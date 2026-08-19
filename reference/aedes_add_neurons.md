# Add new neurons (and update existing ones) in the aedes_main flytable

Brings the supplied `ids` to the current segmentation timestamp, reads
the `aedes_main` table fresh, and pins both sides to the same timestamp
via [`aedes_sequential_update()`](aedes_sequential_update.md) so that
join-by-`root_id` is reliable. Rows whose `root_id` is already present
are updated with any extra columns supplied via `...`; rows that are
absent are appended with a `point_xyz` computed by
[`aedes_key_point()`](aedes_key_point.md). `supervoxel_id` and
`serial_id` are left blank – a server-side process fills them in from
`point_xyz`.

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

  Root ids of neurons to add or update.

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
