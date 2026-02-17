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
