#' Add new neurons (and update existing ones) in the aedes_main flytable
#'
#' @description Brings the supplied `ids` to the current segmentation timestamp,
#'   reads the `aedes_main` table fresh, and pins both sides to the same
#'   timestamp via [aedes_sequential_update()] so that join-by-`root_id` is
#'   reliable. Rows whose `root_id` is already present are updated with any
#'   extra columns supplied via `...`; rows that are absent are appended with a
#'   `point_xyz` computed by [aedes_key_point()]. `supervoxel_id` and
#'   `serial_id` are left blank — a server-side process fills them in from
#'   `point_xyz`.
#'
#' @param ids Root ids of neurons to add or update.
#' @param dryrun If `TRUE` (the default) no writes are performed; the function
#'   returns the data frames that would have been used.
#' @param ... Additional columns to set on each row (e.g. `cell_class = "KC"`).
#'   Recycled across all input ids.
#' @return A list. With `dryrun = TRUE` it has elements `up` (rows that would
#'   be updated) and/or `new` (rows that would be appended). With
#'   `dryrun = FALSE` only `new` is returned (so the caller can see which
#'   `point_xyz` values were chosen).
#' @export
aedes_add_neurons <- function(ids, dryrun = TRUE, ...) {
  fids <- fafbseg::flywire_ids(ids, unique = TRUE)
  fids <- setdiff(fids, 0)

  # pin a single timestamp for both the supplied ids and the flytable rows
  ts <- aedes_get_version(timestamp = "now")
  ids <- with_aedes(fafbseg::flywire_latestid(fids, timestamp = ts$timestamp))

  # read aedes_main fresh, then bring its root_ids to the same timestamp
  am <- aedes_meta(expiry = 0)
  am <- aedes_sequential_update(am, version = ts$version, timestamp = ts$timestamp)

  indf <- data.frame(root_id = ids, ..., stringsAsFactors = FALSE)
  iidf <- am[am$root_id %in% ids, , drop = FALSE]

  rlist <- list()
  newdf <- NULL
  if (nrow(iidf) > 0) {
    updf <- dplyr::left_join(iidf[, c("_id", "root_id")], indf, by = "root_id")
    if (any(duplicated(updf[["_id"]])))
      stop("Duplicate rows to update!")
    if (length(ids) < nrow(iidf))
      stop("Too few ids!")
    if (!dryrun)
      fafbseg::flytable_update_rows(updf, table = "aedes_main", append_allowed = FALSE)
    else
      rlist[["up"]] <- updf
    if (length(ids) > nrow(iidf))
      newdf <- indf[!indf$root_id %in% updf$root_id, , drop = FALSE]
  } else {
    newdf <- indf
  }
  if (!isTRUE(nrow(newdf) > 0))
    return(rlist)

  pts <- aedes_key_point(newdf$root_id)
  newdf$point_xyz <- nat::xyzmatrix2str(pts)
  rlist[["new"]] <- newdf
  if (!dryrun)
    fafbseg::flytable_append_rows(newdf[-1], table = "aedes_main")
  rlist
}
