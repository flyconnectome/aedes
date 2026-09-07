# Group aedes neurons together in FlyTable

Writes only the `group` column of the `aedes_main` FlyTable, assigning a
shared `group` id to a set of neurons – the convenient way to build
serial / cell-type groups and, via `join_existing`, to add neurons to a
group that already exists. For editing arbitrary metadata columns use
[`aedes_set_meta()`](aedes_set_meta.md); to add rows that are not yet
present use [`aedes_add_neurons()`](aedes_add_neurons.md).

## Usage

``` r
aedes_set_group(
  ids,
  group = NULL,
  join_existing = NA,
  dryrun = TRUE,
  annotator = TRUE,
  proofreader = FALSE,
  wipe = FALSE,
  ...
)
```

## Arguments

- ids:

  Neurons to group, in any form understood by
  [`aedes_ids()`](aedes_meta.md) (including a query string).

- group:

  Optional explicit target. An integer forces that group id; `0` or `NA`
  ungroups; a query / ids joins the group of those neuron(s)
  ("join-by-example"). When `NULL` (the default) the group id is derived
  (see Details).

- join_existing:

  Controls behaviour when selected neurons already belong to a group.
  `NA` (the default): refuse to guess – warn (dry run) or error (live)
  and explain how to proceed. `TRUE`: add them to the existing group
  (its id is kept even if a lower `serial_id` is now available; several
  existing groups are merged into the smallest, with a warning).
  `FALSE`: ignore existing membership and mint a fresh group from
  `min(serial_id)`.

- dryrun:

  logical: if `TRUE` (the default) return a preview without writing to
  FlyTable.

- annotator:

  Multi-select `annotator` column write policy for rows that actually
  change group. `TRUE` (the default) appends
  `getOption("aedes.initials")` to the existing cell; `FALSE` leaves the
  column alone; a character vector (or comma-joined string) appends
  those tokens explicitly.

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

A preview data.frame with one row per selected neuron: `root_id`,
`serial_id`, `group_old`, `group_new` and `changed`. Returned invisibly
on a live write.

## Details

By convention a group is identified by an integer equal to the smallest
`serial_id` among its founding members; `group = 0` (or `NA`) means
ungrouped. When the selected neurons are all currently ungrouped a fresh
group id is minted from `min(serial_id)`.

When some selected neurons already belong to a group, `join_existing`
decides what happens (see the argument). Reassigning neurons out of a
group whose other members were not supplied emits a warning, since it
splits that group. Only the `group` column is written, via the shared
update engine that also backs [`aedes_set_meta()`](aedes_set_meta.md);
the same pinned table snapshot is reused so the returned preview matches
what is written.

## See also

[`aedes_set_meta()`](aedes_set_meta.md) for arbitrary metadata updates;
[`aedes_add_neurons()`](aedes_add_neurons.md) to add rows that are not
yet present; [`aedes_meta()`](aedes_meta.md) to query the same table.

## Examples

``` r
if (FALSE) { # \dontrun{
options(aedes.initials = "GJ")

# Mint a fresh group from a set of ungrouped neurons: the resulting
# `group` id is min(serial_id) of the members.
ids <- c("648518347569414567", "648518347399768369")
aedes_set_group(ids)                       # dry run: preview only
aedes_set_group(ids, dryrun = FALSE)       # commit

# Add another neuron to an existing group. When some selected neurons
# are already grouped, join_existing is required (NA = refuse to guess).
aedes_set_group(c(ids, "648518347123456789"),
                join_existing = TRUE, dryrun = FALSE)

# Join by example: use the group of a reference neuron
aedes_set_group("648518347999999999",
                group = "648518347569414567", dryrun = FALSE)

# Ungroup: group=0 or group=NA
aedes_set_group(ids, group = 0, dryrun = FALSE)
} # }
```
