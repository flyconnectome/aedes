#' Return metadata about Aedes neurons from FlyTable
#'
#' @param ids Root IDs (character/int64) or a query string like `"class:ALPN"`.
#' @param ignore.case For query strings, whether to ignore case.
#' @param fixed For query strings, whether to treat queries as fixed strings
#'   rather than regular expressions (default FALSE).
#' @param version Optional CAVE materialisation version.
#' @param timestamp Optional CAVE timestamp.
#' @param unique Whether to drop duplicate `root_id` rows (with duplicates
#'   attached as an attribute).
#' @param translate_ids Whether to bring explicitly supplied `ids` forward to
#'   the requested `version`/`timestamp` before matching (see Details).
#'   `NA` (the default) decides automatically.
#' @param ... Additional arguments passed to [fafbseg::cam_meta()] (e.g.
#'   cache controls such as `expiry`, `refresh`).
#' @return For `aedes_meta()`, a data.frame of metadata. For `aedes_ids()`, a
#'   vector of root IDs.
#'
#' @details When `version` or `timestamp` are specified, root ids in the
#'   returned data frame will be mapped to the corresponding timepoint using the
#'   `supervoxel_id` column. When no version/timestamp is specified then ids
#'   will be simply as returned by the flytable (which updates them every half
#'   hour). If you want to be sure that ids match the most up to date state of
#'   the segmentation possible then you can ask for `timestamp='now'`.
#'
#'   For a **query string** the match happens against that mapped table, so no
#'   further work is needed. For **explicit root `ids`** the join is by
#'   `root_id`, so ids that are stale relative to the requested timepoint would
#'   silently fail to match. `translate_ids` guards against this by bringing the
#'   supplied ids forward with [fafbseg::flywire_latestid()] first. The default
#'   (`NA`) turns this on only when it is both needed and meaningful: explicit
#'   ids are supplied *and* a `version`/`timestamp` is given. With no
#'   version/timestamp nothing is translated, since the flytable is simply at
#'   the state of its last half-hourly update.
#'
#' @export
#'
#' @examples
#' \dontrun{
#' aedes_meta("class:ALPN")
#' aedes_ids("class:ALPN")
#'
#' aedes_ids("class:ALPN", timestamp='now')
#' aedes_ids("class:ALPN", version='latest')
#' }
aedes_meta <- function(ids = NULL, ignore.case = FALSE, fixed = FALSE, version = NULL,
                       timestamp = NULL, unique = FALSE, translate_ids = NA, ...) {
  with_aedes(fafbseg::cam_meta(
    ids = ids,
    ignore.case = ignore.case,
    fixed = fixed,
    table = "aedes_main",
    version = version,
    timestamp = timestamp,
    unique = unique,
    translate_ids = translate_ids,
    ...
  ))
}

#' Set default version selection for Aedes helpers
#' @param which One of `"now"` or `"latest"` (or explicit selector).
#' @export
aedes_set_version <- function(which = c("now", "latest")) {
  if (is.character(which) && length(which) > 1)
    which = match.arg(which)
  options(aedes.version = which)
}

#' Resolve Aedes materialisation version and timestamp
#' @param which Version selector; defaults to `getOption("aedes.version")`.
#' @param version Optional explicit materialisation version.
#' @param timestamp Optional explicit timestamp.
#' @return A list with `version` and `timestamp`.
#' @export
aedes_get_version <- function(which = getOption("aedes.version", default = "latest"), version = NULL, timestamp = NULL) {
  if (is.null(which))
    which = getOption("aedes.version", default = "latest")
  if (!is.null(version)) {
    if (!is.null(timestamp)) {
      warning("ignoring timestamp since version was provided")
      timestamp = NULL
    }
  } else if (is.null(timestamp) && length(which) >= 1) {
    if (is.character(which) && length(which) > 1)
      which = match.arg(which, c("now", "latest"))
    if (which == "latest" || is.numeric(which))
      version = which
    else
      timestamp = which
  }
  with_aedes(list(
    # TODO: use exported fafbseg::flywire_version when available
    version = fafbseg:::flywire_version(version = version),
    timestamp = fafbseg::flywire_timestamp(timestamp = timestamp)
  ))
}

#' @rdname aedes_meta
#' @export
aedes_ids <- function(ids, ignore.case = FALSE, fixed = FALSE, unique = FALSE,
                      version = NULL, timestamp = NULL, ...) {
  vi = aedes_get_version(timestamp = timestamp, version = version)
  am = aedes_meta(ids, ignore.case = ignore.case, fixed = fixed, unique = unique,
                  version = vi$version, timestamp = vi$timestamp, ...)
  am$root_id
}

#' Bulk-update metadata for existing aedes neurons in FlyTable
#'
#' @description Update-only bulk edit of arbitrary metadata columns on rows
#'   that are already present in the `aedes_main` FlyTable. Every `root_id`
#'   must already be present, otherwise nothing is written -- use
#'   [aedes_add_neurons()] to create rows, and [aedes_set_group()] when the
#'   only column you need to touch is `group`.
#'
#' @details Rows with status `bad_nucleus`, `duplicate` or `not_a_neuron` are
#'   dropped before updating; any remaining `root_id` not found in `aedes_main`
#'   is an error (nothing is written). Writes go through the shared update engine,
#'   which pins a single timestamp so join-by-`root_id` is reliable.
#'
#' @param ids root_ids in any form understood by [aedes_ids()] (including a query
#'   string); or, when `df` is `NULL`, a data.frame of metadata that itself
#'   contains a `root_id` column.
#' @param df an optional data.frame of metadata, recycled to match `ids`. When
#'   supplied together with `ids`, a `root_id` column is prepended from `ids`.
#' @param dryrun logical: if `TRUE` (the default) return the update frame without
#'   writing to FlyTable.
#' @param update_roots whether to bring `root_id`s to the pinned timestamp with
#'   [fafbseg::flywire_latestid()] before matching.
#' @param annotator Multi-select `annotator` column write policy. `TRUE`
#'   (the default) appends `getOption("aedes.initials")` to the existing cell;
#'   `FALSE` leaves the column alone; a character vector (or comma-joined
#'   string) appends those tokens explicitly.
#' @param proofreader Multi-select `proofreader` column write policy. Same
#'   accepted values as `annotator`; defaults to `FALSE`.
#' @param wipe If `TRUE`, replace the target multi-select column(s) with just
#'   the new tokens instead of merging with existing cell contents. Default
#'   `FALSE` (append).
#' @param ... reserved (used to reject a mistaken `dry_run` argument).
#'
#' @returns a data.frame of the rows written (or, on a dry run, that would be
#'   written), keyed by FlyTable `_id`.
#' @seealso [aedes_add_neurons()] to add rows that are not yet present;
#'   [aedes_set_group()] for the dedicated `group`-only path;
#'   [aedes_meta()] to query the same table.
#' @export
#' @examples
#' \dontrun{
#' options(aedes.initials = "GJ")
#'
#' # Update a handful of neurons: two columns, recycled across all ids.
#' ids <- c("648518347569414567", "648518347399768369")
#' aedes_set_meta(ids,
#'                data.frame(cell_type = c("KCa'b'", "KCg"),
#'                           status    = "adequate"))
#'
#' # Or pass a single data.frame that already carries `root_id`
#' df <- data.frame(root_id   = ids,
#'                  cell_type = c("KCa'b'", "KCg"),
#'                  status    = "adequate",
#'                  stringsAsFactors = FALSE)
#' aedes_set_meta(df)                       # dry run (default)
#' aedes_set_meta(df, dryrun = FALSE)       # commit
#'
#' # Query-string ids also work: update every ALPN with a note
#' aedes_set_meta("class:ALPN",
#'                data.frame(notes = "reviewed 2026-09"),
#'                dryrun = FALSE)
#' }
aedes_set_meta <- function(ids = NULL, df = NULL, dryrun = TRUE,
                           update_roots = TRUE,
                           annotator = TRUE, proofreader = FALSE,
                           wipe = FALSE, ...) {
  .aedes_reject_dry_run(...)
  ann_toks <- .aedes_resolve_initials(annotator,  "annotator")
  prf_toks <- .aedes_resolve_initials(proofreader, "proofreader")
  if (is.null(df)) {
    if (!is.data.frame(ids))
      stop("`ids` must be a data.frame if you do not provide a `df` argument!")
    df <- ids
  } else if (!is.null(ids)) {
    ids <- setdiff(aedes_ids(ids), 0)
    df <- cbind(data.frame(root_id = ids, stringsAsFactors = FALSE), df)
  }
  if (!is.data.frame(df) || !"root_id" %in% names(df))
    stop("Provide metadata as a data.frame with a `root_id` column.")
  df$root_id <- as.character(df$root_id)

  # Pin one timestamp; reuse the fetched table for hygiene and the engine.
  pin <- .aedes_pin_meta(df$root_id)
  am <- pin$am
  ts <- pin$ts
  if (update_roots)
    df$root_id <- with_aedes(
      fafbseg::flywire_latestid(df$root_id, timestamp = ts$timestamp))

  # Status hygiene: never edit these rows via this path.
  status <- am$status[match(df$root_id, as.character(am$root_id))]
  bad <- status %in% c("bad_nucleus", "duplicate", "not_a_neuron")
  if (any(bad)) {
    message("Dropping ", sum(bad),
            " row(s) with status bad_nucleus/duplicate/not_a_neuron.")
    df <- df[!bad, , drop = FALSE]
  }

  # All-or-nothing: refuse to write if any id is absent from aedes_main.
  present <- df$root_id %in% as.character(am$root_id)
  if (!all(present)) {
    miss <- unique(df$root_id[!present])
    stop("These ids are not present in aedes_main: ",
         paste(utils::head(miss, 10L), collapse = ", "),
         if (length(miss) > 10L) sprintf(" (+%d more)", length(miss) - 10L), ".",
         call. = FALSE)
  }

  df <- .aedes_append_multiselect(
    df, am, list(annotator = ann_toks, proofreader = prf_toks), wipe = wipe)
  res <- .aedes_update_existing(df, dryrun = dryrun, am = am, ts = ts)
  res$updf
}
