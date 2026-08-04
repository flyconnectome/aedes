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
                       timestamp = NULL, unique = FALSE, ...) {
  with_aedes(fafbseg::cam_meta(
    ids = ids,
    ignore.case = ignore.case,
    fixed = fixed,
    table = "aedes_main",
    version = version,
    timestamp = timestamp,
    unique = unique,
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
#' @description Updates rows that already exist in the `aedes_main` FlyTable from
#'   a data.frame of per-row metadata. Update-only: every `root_id` must already
#'   be present (use [aedes_add_neurons()] to create rows).
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
#' @param ... reserved (used to reject a mistaken `dry_run` argument).
#'
#' @returns a data.frame of the rows written (or, on a dry run, that would be
#'   written), keyed by FlyTable `_id`.
#' @seealso [aedes_add_neurons()], [aedes_set_group()]
#' @export
aedes_set_meta <- function(ids = NULL, df = NULL, dryrun = TRUE,
                           update_roots = TRUE, ...) {
  .aedes_reject_dry_run(...)
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

  res <- .aedes_update_existing(df, dryrun = dryrun, am = am, ts = ts)
  res$updf
}
