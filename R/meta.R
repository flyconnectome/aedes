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
#' @return For `aedes_meta()`, a data.frame of metadata. For `aedes_ids()`, a
#'   vector of root IDs.
#'
#' @details When `version` or `timestamp` are specified, ids in the returned
#'   data frame will be updated.
#'
#' @export
#'
#' @examples
#' \dontrun{
#' aedes_meta("class:ALPN")
#' aedes_ids("class:ALPN")
#' }
aedes_meta <- function(ids = NULL, ignore.case = FALSE, fixed = FALSE, version = NULL,
                       timestamp = NULL, unique = FALSE) {

  if (is.character(ids) && length(ids) == 1 && !fafbseg:::valid_id(ids) && !grepl(":", ids))
    ids = paste0("type:", ids)
  if (is.character(ids) && length(ids) == 1 && !fafbseg:::valid_id(ids) && substr(ids, 1, 1) == "/")
    ids = substr(ids, 2, nchar(ids))
  aedes_main = fafbseg::flytable_query("select * from aedes_main WHERE status NOT IN ('duplicate', 'bad_nucleus')")
  if (is.character(ids) && length(ids) == 1 && grepl(":", ids)) {
    ul = unlist(strsplit(ids, ":", fixed = TRUE))
    if (length(ul) != 2)
      stop("Unable to parse aedes id specification!")
    target = ul[1]
    if (!target %in% colnames(aedes_main))
      stop("Unknown field in flywire id specification!")
    query = ul[2]
    if (!fixed && substr(query, 1, 1) != "^") {
      query = paste0("^", query, "$")
    }
    df = dplyr::filter(aedes_main, grepl(query, .data[[target]], ignore.case = ignore.case, fixed = fixed))
  } else if (is.null(ids)) {
    df = aedes_main
  } else {
    ids <- fafbseg::flywire_ids(ids, integer64 = FALSE, unique = TRUE)
    df = data.frame(root_id = ids)
    if (!is.null(version) || !is.null(timestamp))
      aedes_main$root_id = with_aedes(fafbseg::flywire_updateids(aedes_main$root_id, svids = aedes_main$supervoxel_id, version = version, timestamp = timestamp))
    df = dplyr::left_join(df, aedes_main, by = "root_id")
  }

  if (isTRUE(unique)) {
    dups = duplicated(df$root_id)
    ndups = sum(dups)
    if (ndups > 0) {
      dupids = unique(df$root_id[dups])
      duprows = df[df$root_id %in% dupids, , drop = FALSE]
      duprows = duprows[order(duprows$root_id), , drop = FALSE]
      df = df[!dups, , drop = FALSE]
      attr(df, "duprows") = duprows
      warning("Dropping ", sum(dups), " rows containing duplicate root_ids!\n",
              "You can inspect all ", nrow(duprows), " rows with duplicate ids by doing:\n",
              "attr(df, 'duprows')\n", "on your returned data frame (replacing df as appropriate).")
    }
  }

  if (!is.null(version) || !is.null(timestamp)) {
    df$root_id = with_aedes(fafbseg::flywire_updateids(df$root_id, svids = df$supervoxel_id, version = version, timestamp = timestamp))
  }
  df
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
  } else if (is.null(timestamp) & length(which) >= 1) {
    if (is.character(which) && length(which) > 1)
      which = match.arg(which, c("now", "latest"))
    if (which == "latest" || is.numeric(which))
      version = which
    else
      timestamp = which
  }
  with_aedes(list(
    version = fafbseg:::flywire_version(version = version),
    timestamp = fafbseg::flywire_timestamp(timestamp = timestamp)
  ))
}

#' @rdname aedes_meta
#' @export
aedes_ids <- function(ids, ignore.case = FALSE, fixed = FALSE, unique = FALSE,
                      version = NULL, timestamp = NULL) {
  vi = aedes_get_version("now", timestamp = timestamp, version = version)
  am = aedes_meta(ids, ignore.case = ignore.case, fixed = fixed, unique = unique,
                  version = vi$version, timestamp = vi$timestamp)
  am$root_id
}
