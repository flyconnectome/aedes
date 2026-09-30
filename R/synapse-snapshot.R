#' Use a local snapshot of the Aedes synapse table
#'
#' Selects a downloaded snapshot of the Aedes synapse table so that
#' [aedes_partner_summary()] and [aedes_synapse_data()] can answer queries
#' locally, without contacting CAVE for synapses. Each snapshot records the
#' root id of both partners of every synapse at one moment in time.
#'
#' @details A snapshot folder contains `static.parquet` (one row per synapse,
#'   with its supervoxels, positions and size) and one sub-folder per snapshot
#'   tag. A tag folder has a `meta.json` with the snapshot `timestamp` and
#'   either the full root id table (`by_pre.parquet`, sorted by presynaptic
#'   root, plus an optional `by_post.parquet` sorted by postsynaptic root) or,
#'   for a delta snapshot, a `delta.parquet` with the rows that differ from its
#'   full `base` snapshot. Queries use DuckDB (from
#'   the suggested packages \pkg{duckdb}, \pkg{DBI} and \pkg{dbplyr}) and only
#'   read the parts of the parquet files that they need.
#'
#'   Selecting a snapshot with `set = TRUE` also sets the `aedes.version`
#'   option to the snapshot's timestamp (see [aedes_set_version()]), so that
#'   metadata and root ids from other aedes functions match the synapse data.
#'   [aedes_partner_summary()] can still answer queries for later times,
#'   including `timestamp = "now"`, by fetching the edits made since the
#'   snapshot from CAVE (see its details).
#'
#' @param snapshot The snapshot tag, or `"latest"` (the default) for the most
#'   recent snapshot in `root`.
#' @param root The snapshot folder. Defaults to the
#'   `aedes.synapse_snapshot_root` option.
#' @param set Whether to make this the default snapshot for the session.
#'
#' @return When `set = TRUE`, the previous option values (invisibly, suitable
#'   for passing to [options()]). Otherwise a list with the snapshot `tag`,
#'   `timestamp` and `root`.
#' @seealso [aedes_partner_summary()], [aedes_synapse_data()]
#' @export
#' @examples
#' \dontrun{
#' options(aedes.synapse_snapshot_root = "~/data/aedes/syn_snapshot")
#' aedes_synapse_snapshot()
#' # now answered locally at the snapshot time
#' aedes_partner_summary("cell_class:DNa")
#' }
aedes_synapse_snapshot <- function(snapshot = "latest",
                                   root = getOption("aedes.synapse_snapshot_root"),
                                   set = TRUE) {
  if (identical(snapshot, "latest"))
    snapshot <- synsnap_latest(root)
  m <- synsnap_meta(snapshot, root)
  root <- normalizePath(root, mustWork = TRUE)
  if (!set)
    return(list(tag = snapshot, timestamp = m$timestamp, root = root))
  invisible(options(
    aedes.synapse_snapshot_root = root,
    aedes.synapse_snapshot = snapshot,
    aedes.version = format(m$timestamp, "%Y-%m-%d %H:%M:%OS6 UTC", tz = "UTC")))
}

# the active snapshot: list(tag, timestamp, root) or NULL if none configured
aedes_synapse_snapshot_active <- function(snapshot = getOption("aedes.synapse_snapshot"),
                                          root = getOption("aedes.synapse_snapshot_root")) {
  if (is.null(root) || is.null(snapshot)) return(NULL)
  aedes_synapse_snapshot(snapshot, root = root, set = FALSE)
}

#' Lazy access to all synapses in a local snapshot
#'
#' Returns a lazy \pkg{dbplyr} table of every synapse in a local snapshot (see
#' [aedes_synapse_snapshot()]) for use with \pkg{dplyr} verbs. Nothing is read
#' until you [dplyr::collect()] the result.
#'
#' @details The table has columns `id`, `pre_root` and `post_root` (as
#'   `integer64`). With `static = TRUE` it also has the columns of
#'   `static.parquet`: `pre_sv`, `post_sv`, `pre_x`...`post_z` (raw voxel
#'   coordinates of the pre and postsynaptic points), `centroid_x`...
#'   `centroid_z` and `size`.
#'
#'   Rows are sorted by `pre_root`, so filtering on a few `pre_root` values
#'   lets DuckDB skip most of the file. Snapshots with a `by_post.parquet`
#'   also keep a copy sorted by `post_root`, which `side = "post"` reads. Use
#'   [bit64::as.integer64()] for root ids in filters.
#'
#' @param side `"post"` to read the copy sorted by `post_root` when the
#'   snapshot has one. `NULL` (the default) and `"pre"` read the copy sorted by
#'   `pre_root`.
#' @param static Whether to add supervoxel, position and size columns.
#' @inheritParams aedes_synapse_snapshot
#' @return A lazy `tbl`.
#' @seealso [aedes_synapse_snapshot()]
#' @export
#' @examples
#' \dontrun{
#' library(dplyr)
#' ids <- bit64::as.integer64(aedes_ids("cell_class:DNa"))
#' aedes_synapse_data("post") %>%
#'   filter(post_root %in% ids) %>%
#'   count(pre_root, sort = TRUE) %>%
#'   collect()
#' }
aedes_synapse_data <- function(side = NULL, static = FALSE,
                               snapshot = getOption("aedes.synapse_snapshot", "latest"),
                               root = getOption("aedes.synapse_snapshot_root")) {
  if (!is.null(side)) side <- match.arg(side, c("pre", "post"))
  if (identical(snapshot, "latest")) snapshot <- synsnap_latest(root)
  synsnap_tbl(snapshot, root, side = side, static = static)
}

# CAVE access for synsnap_query_at() (see R/synsnap-live.R)
aedes_synsnap_ctx <- function() {
  list(
    delta_roots = function(past, future) with_aedes(cave_delta_roots(past, future)),
    rootid = function(sv, timestamp) {
      ch <- split(sv, ceiling(seq_along(sv) / 1e5))
      r <- lapply(ch, function(s) with_aedes(fafbseg::flywire_rootid(
        as.character(s), timestamp = timestamp, integer64 = TRUE)))
      do.call(c, unname(r))
    },
    # leaves of a root id never change, so caching is safe
    leaves = function(root) with_aedes(fafbseg::flywire_leaves(
      as.character(root), integer64 = TRUE, cache = TRUE)),
    is_latest = function(roots, timestamp) with_aedes(fafbseg::flywire_islatest(
      as.character(roots), timestamp = timestamp)),
    latest_id = function(roots, timestamp) bit64::as.integer64(with_aedes(
      fafbseg::flywire_latestid(as.character(roots), timestamp = timestamp))),
    now = Sys.time)
}

# roots expired (old) and created (new) between two times. Unlike
# fafbseg:::cave_get_delta_roots this fails loudly, since an empty result would
# silently leave stale rows.
cave_delta_roots <- function(past, future) {
  fcc <- fafbseg::flywire_cave_client()
  res <- reticulate::py_call(fcc$chunkedgraph$get_delta_roots,
                             timestamp_past = fafbseg:::ts2pydatetime(past),
                             timestamp_future = fafbseg:::ts2pydatetime(future))
  pyslice <- fafbseg:::pyslice()$pyslice
  ids <- function(i) bit64::as.integer64(fafbseg:::pyids2bit64(
    reticulate::py_call(pyslice, res, i)))
  list(old = ids(0L), new = ids(1L))
}
