# Bulk-update metadata for existing aedes neurons in FlyTable

Update-only bulk edit of arbitrary metadata columns on rows that are
already present in the `aedes_main` FlyTable. Every `root_id` must
already be present, otherwise nothing is written – use
[`aedes_add_neurons()`](aedes_add_neurons.md) to create rows, and
[`aedes_set_group()`](aedes_set_group.md) when the only column you need
to touch is `group`.

## Usage

``` r
aedes_set_meta(
  ids = NULL,
  df = NULL,
  dryrun = TRUE,
  update_roots = TRUE,
  annotator = TRUE,
  proofreader = FALSE,
  wipe = FALSE,
  ...
)
```

## Arguments

- ids:

  root_ids in any form understood by [`aedes_ids()`](aedes_meta.md)
  (including a query string); or, when `df` is `NULL`, a data.frame of
  metadata that itself contains a `root_id` column.

- df:

  an optional data.frame of metadata, recycled to match `ids`. When
  supplied together with `ids`, a `root_id` column is prepended from
  `ids`.

- dryrun:

  logical: if `TRUE` (the default) return the update frame without
  writing to FlyTable.

- update_roots:

  whether to bring `root_id`s to the pinned timestamp with
  [`fafbseg::flywire_latestid()`](https://rdrr.io/pkg/fafbseg/man/flywire_latestid.html)
  before matching.

- annotator:

  Multi-select `annotator` column write policy. `TRUE` (the default)
  appends `getOption("aedes.initials")` to the existing cell; `FALSE`
  leaves the column alone; a character vector (or comma-joined string)
  appends those tokens explicitly.

- proofreader:

  Multi-select `proofreader` column write policy. Same accepted values
  as `annotator`; defaults to `FALSE`.

- wipe:

  If `TRUE`, replace the target multi-select column(s) with just the new
  tokens instead of merging with existing cell contents. Default `FALSE`
  (append).

- ...:

  reserved (used to reject a mistaken `dry_run` argument).

## Value

a data.frame of the rows written (or, on a dry run, that would be
written), keyed by FlyTable `_id`.

## Details

Rows with status `bad_nucleus`, `duplicate` or `not_a_neuron` are
dropped before updating; any remaining `root_id` not found in
`aedes_main` is an error (nothing is written). Writes go through the
shared update engine, which pins a single timestamp so join-by-`root_id`
is reliable.

## See also

[`aedes_add_neurons()`](aedes_add_neurons.md) to add rows that are not
yet present; [`aedes_set_group()`](aedes_set_group.md) for the dedicated
`group`-only path; [`aedes_meta()`](aedes_meta.md) to query the same
table.

## Examples

``` r
if (FALSE) { # \dontrun{
options(aedes.initials = "GJ")

# Update a handful of neurons: two columns, recycled across all ids.
ids <- c("648518347569414567", "648518347399768369")
aedes_set_meta(ids,
               data.frame(cell_type = c("KCa'b'", "KCg"),
                          status    = "adequate"))

# Or pass a single data.frame that already carries `root_id`
df <- data.frame(root_id   = ids,
                 cell_type = c("KCa'b'", "KCg"),
                 status    = "adequate",
                 stringsAsFactors = FALSE)
aedes_set_meta(df)                       # dry run (default)
aedes_set_meta(df, dryrun = FALSE)       # commit

# Query-string ids also work: update every ALPN with a note
aedes_set_meta("class:ALPN",
               data.frame(notes = "reviewed 2026-09"),
               dryrun = FALSE)
} # }
```
