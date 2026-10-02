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
#'   for a checkpoint, a `log.parquet` with the synapses whose root ids changed
#'   since its `parent` snapshot. A checkpoint is read as its full `base`
#'   snapshot plus the logs of every checkpoint between them, so it is only
#'   used when all of those are present. Queries use DuckDB (from
#'   the suggested packages \pkg{duckdb}, \pkg{DBI} and \pkg{dbplyr}) and only
#'   read the parts of the parquet files that they need. DuckDB uses every
#'   core; set the `aedes.duckdb_threads` option before the first query to use
#'   fewer, e.g. on a shared machine.
#'
#'   When no `snapshot` is given, the newest one at or before the requested
#'   time is used: `timestamp` or the time of `version` when given, otherwise
#'   the `aedes.version` option (see [aedes_set_version()]). So by default
#'   (`"latest"`) this is the snapshot of the newest materialisation version,
#'   while for `"now"` it is the newest snapshot. [aedes_partner_summary()]
#'   answers queries for later times by fetching the edits made since the
#'   snapshot from CAVE (see its details).
#'
#'   The `aedes.version` option is only changed when you give `version` or
#'   `timestamp`, so that metadata and root ids from other aedes functions
#'   match the synapse data.
#'
#'   If there is no snapshot in `root`, you are asked whether to download one
#'   with [aedes_download_snapshot()] (in an interactive session) or get an
#'   error saying how to.
#'
#' @param snapshot The snapshot tag, or `"latest"` for the most recent
#'   snapshot in `root`. The default (`NULL`) chooses one to match `version`,
#'   `timestamp` or the `aedes.version` option.
#' @param version,timestamp A CAVE materialisation version or a timestamp
#'   (including `"now"`) to choose the snapshot for. Either one also sets the
#'   `aedes.version` option.
#' @param root The snapshot folder. Defaults to
#'   [aedes_snapshot_root()].
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
#' aedes_use_snapshot()
#' # answered locally at the time of the latest materialisation
#' aedes_partner_summary("class:DNa")
#' }
aedes_use_snapshot <- function(snapshot = NULL, version = NULL, timestamp = NULL,
                               root = aedes_snapshot_root(), set = TRUE) {
  explicit <- !is.null(version) || !is.null(timestamp)
  if (!is.null(snapshot) && explicit)
    stop("Give either a snapshot or a version/timestamp, not both", call. = FALSE)
  if (set) aedes_snapshot_check(root)
  if (is.null(snapshot)) {
    when <- partner_summary_local_time(version, timestamp)
    snapshot <- synsnap_at(root, when)
    if (is.null(snapshot)) {
      snapshot <- synsnap_tags(root)$tag[1]
      message("No synapse snapshot is as old as ", format_utc(when),
              ": queries for that time will use CAVE")
    }
  } else if (identical(snapshot, "latest")) snapshot <- synsnap_latest(root)
  m <- synsnap_meta(snapshot, root)
  root <- normalizePath(root, mustWork = TRUE)
  if (!set)
    return(list(tag = snapshot, timestamp = m$timestamp, root = root))
  message("Using synapse snapshot '", snapshot, "' (", format_utc(m$timestamp), ")")
  op <- options(aedes.synapse_snapshot_root = root,
                aedes.synapse_snapshot = snapshot)
  if (explicit) op <- c(op, options(aedes.version = if (is.null(timestamp))
    as.integer(version) else if (identical(timestamp, "now")) "now"
    else format_utc(with_aedes(fafbseg::flywire_timestamp(timestamp = timestamp)),
                    digits = 6)))
  invisible(op)
}

# Offer to download a snapshot when `root` has none, or say how to get one
aedes_snapshot_check <- function(root) {
  if (dir.exists(root) && nrow(synsnap_tags(root))) return(invisible(TRUE))
  msg <- paste0("No local synapse snapshot in ", root, ".")
  if (rlang::is_interactive() &&
      isTRUE(ask_yes_no(paste(msg, "Download one now (about 2.3 GB)?")))) {
    aedes_download_snapshot(root = root, set = FALSE)
    return(invisible(TRUE))
  }
  stop(msg, " Download one with aedes_download_snapshot() (about 2.3 GB, ",
       "needs access to the aedes CAVE datastack) or see ",
       "vignette(\"synapse-snapshots\", package = \"aedes\")", call. = FALSE)
}

ask_yes_no <- function(msg) utils::askYesNo(msg)

format_utc <- function(x, digits = 0)
  if (identical(x, "now")) x else
    format(x, paste0("%Y-%m-%d %H:%M:%OS", if (digits) digits, " UTC"), tz = "UTC")

#' Folder for local Aedes synapse snapshots
#'
#' Returns the folder that the synapse snapshot functions use when no `root` is
#' given.
#'
#' @details The folder is the first of:
#'
#'   1. the `aedes.synapse_snapshot_root` option, if set;
#'   2. `~/projects/2025aedes/data/syn_snapshot`, if it holds a snapshot
#'   (`static.parquet`);
#'   3. `syn_snapshot` in the user data folder for the package (see
#'   [rappdirs::user_data_dir()]).
#'
#' @param create Whether to create the folder (and any missing parent folders)
#'   if it does not exist yet.
#' @return The path to the folder, with `~` expanded.
#' @seealso [aedes_use_snapshot()]
#' @export
#' @examples
#' aedes_snapshot_root()
aedes_snapshot_root <- function(create = FALSE) {
  root <- getOption("aedes.synapse_snapshot_root")
  if (is.null(root)) {
    proj <- "~/projects/2025aedes/data/syn_snapshot"
    root <- if (file.exists(file.path(proj, "static.parquet"))) proj
    else file.path(rappdirs::user_data_dir("rpkg-aedes"), "syn_snapshot")
  }
  root <- path.expand(root)
  if (create && !dir.exists(root) && !dir.create(root, recursive = TRUE))
    stop("Could not create synapse snapshot folder ", root, call. = FALSE)
  root
}

#' Bring a local Aedes synapse snapshot up to date
#'
#' Saves a new snapshot of the Aedes synapse table at a later time, by applying
#' the edits made since an existing snapshot. Queries at or near the new
#' snapshot time are then fast, since they need few or no CAVE lookups.
#'
#' @details Only synapses on neurons that were edited since `from` are looked
#'   up in CAVE, so updating a day-old snapshot typically takes seconds to
#'   minutes. The new snapshot is saved as a checkpoint: a small `log.parquet`
#'   of the synapses whose root ids changed since `from` (typically about 1 MB
#'   per day of edits). Reading a checkpoint combines the logs back to the last
#'   full snapshot, which stays fast for months of edits; use `rebase = TRUE`
#'   to also save a full snapshot (about 0.6 GB) that later checkpoints start
#'   from.
#'
#'   A `timestamp` given as a time is rounded down to a whole millisecond (the
#'   precision of CAVE edit times).
#'
#' @param timestamp The time for the new snapshot: `"now"` (the default),
#'   `"latest"` for the time of the newest CAVE materialisation version, a
#'   POSIXct or a string accepted by [as.POSIXct()].
#' @param from The snapshot to start from, or `"latest"` (the default) for the
#'   most recent snapshot in `root` at or before `timestamp`.
#' @param tag The name of the new snapshot. Defaults to the timestamp, e.g.
#'   `"20261001T120000"`.
#' @param rebase Whether to also save the new snapshot as a full snapshot.
#' @inheritParams aedes_use_snapshot
#' @return The result of [aedes_use_snapshot()] for the new snapshot.
#' @seealso [aedes_use_snapshot()]
#' @export
#' @examples
#' \dontrun{
#' options(aedes.synapse_snapshot_root = "~/data/aedes/syn_snapshot")
#' aedes_update_snapshot()
#' aedes_partner_summary("class:DNa", timestamp = "now")
#' }
aedes_update_snapshot <- function(timestamp = "now", from = "latest",
                                  tag = NULL, root = aedes_snapshot_root(),
                                  rebase = FALSE, set = TRUE) {
  ctx <- aedes_synsnap_ctx()
  what <- if (identical(timestamp, "now")) "now"
  else if (identical(timestamp, "latest")) "latest materialisation"
  timestamp <- if (identical(timestamp, "now")) ctx$now()
  else if (identical(timestamp, "latest")) aedes_version_timestamp("latest")
  else as.POSIXct(timestamp, tz = "UTC")
  if (identical(from, "latest")) {
    from <- synsnap_at(root, timestamp)
    if (is.null(from))
      stop("No synapse snapshot in ", root, " is as old as ",
           format_utc(timestamp), call. = FALSE)
  }
  ft <- synsnap_meta(from, root)$timestamp
  if (is.null(tag) && abs(as.numeric(timestamp) - as.numeric(ft)) <= 1 && !rebase) {
    message("Synapse snapshot '", from, "' is already at ", format_utc(timestamp))
    tag <- from
  } else {
    if (is.null(tag))
      tag <- format(timestamp, "%Y%m%dT%H%M%S", tz = "UTC")
    message("Updating synapse snapshot '", from, "' (", format_utc(ft), ") to ",
            format_utc(timestamp), if (!is.null(what)) paste0(" (", what, ")"))
    # a version time is kept exactly; others are rounded down to the ms
    synsnap_update(from, tag, if (identical(what, "latest materialisation"))
      synsnap_format_time(timestamp) else timestamp,
      root = root, ctx = ctx, kind = "local")
    if (rebase)
      synsnap_rebase(tag, root)
  }
  res <- aedes_use_snapshot(tag, root = root, set = set)
  if (set && identical(what, "now") &&
      !identical(getOption("aedes.version", "latest"), "now"))
    message("Partner queries follow the aedes.version option; ",
            "use aedes_set_version(\"now\") to query this snapshot by default")
  res
}

# the active snapshot: list(tag, timestamp, root) or NULL if none configured
aedes_snapshot_active <- function(snapshot = getOption("aedes.synapse_snapshot"),
                                  root = getOption("aedes.synapse_snapshot_root")) {
  if (is.null(root) || is.null(snapshot)) return(NULL)
  aedes_use_snapshot(snapshot, root = root, set = FALSE)
}

#' Lazy access to all synapses in a local snapshot
#'
#' Returns a lazy \pkg{dbplyr} table of every synapse in a local snapshot (see
#' [aedes_use_snapshot()]) for use with \pkg{dplyr} verbs. Nothing is read
#' until you [dplyr::collect()] the result.
#'
#' @details The table has columns `id`, `pre_root` and `post_root` (as
#'   `integer64`). With `details = TRUE` it also has `pre_sv`, `post_sv`,
#'   `pre_x`...`post_z` (raw voxel coordinates of the pre and postsynaptic
#'   points) and `size`, from `static.parquet`. Use the
#'   midpoint of the pre and post points where you need one location per
#'   synapse.
#'
#'   Rows are sorted by `pre_root`, so filtering on a few `pre_root` values
#'   lets DuckDB skip most of the file. Snapshots with a `by_post.parquet`
#'   also keep a copy sorted by `post_root`, which `side = "post"` reads. Use
#'   [bit64::as.integer64()] for root ids in filters.
#'
#' @param side `"post"` to read the copy sorted by `post_root` when the
#'   snapshot has one. `NULL` (the default) and `"pre"` read the copy sorted by
#'   `pre_root`.
#' @param details Whether to add supervoxel, position and size columns.
#' @param snapshot The snapshot tag, or `"latest"` for the most recent
#'   snapshot in `root`. Defaults to the one chosen by [aedes_use_snapshot()].
#' @inheritParams aedes_use_snapshot
#' @return A lazy `tbl`.
#' @seealso [aedes_use_snapshot()]
#' @export
#' @examples
#' \dontrun{
#' library(dplyr)
#' ids <- aedes_ids("class:DNa")
#' aedes_synapse_data("post") %>%
#'   filter(post_root %in% ids) %>%
#'   count(pre_root, sort = TRUE) %>%
#'   collect()
#' }
aedes_synapse_data <- function(side = NULL, details = FALSE,
                               snapshot = getOption("aedes.synapse_snapshot", "latest"),
                               root = aedes_snapshot_root()) {
  if (!is.null(side)) side <- match.arg(side, c("pre", "post"))
  if (identical(snapshot, "latest")) snapshot <- synsnap_latest(root)
  synsnap_tbl(snapshot, root, side = side, static = details)
}

# CAVE access for synsnap_query_at() (see R/synsnap-live.R)
aedes_synsnap_ctx <- function() {
  list(
    delta_roots = function(past, future) with_aedes(cave_delta_roots(past, future)),
    rootid = function(sv, timestamp) with_aedes(cave_rootid_parallel(sv, timestamp)),
    # leaves of a root id never change, so caching is safe
    leaves = function(root) with_aedes(fafbseg::flywire_leaves(
      as.character(root), integer64 = TRUE, cache = TRUE)),
    is_latest = function(roots, timestamp) with_aedes(fafbseg::flywire_islatest(
      as.character(roots), timestamp = timestamp)),
    latest_id = function(roots, timestamp) bit64::as.integer64(with_aedes(
      fafbseg::flywire_latestid(as.character(roots), timestamp = timestamp))),
    now = Sys.time)
}

# Root ids at `timestamp` for supervoxels, looked up in chunks by a python
# thread pool (the chunkedgraph requests release the GIL, so `threads` chunks
# are in flight at once).
cave_rootid_parallel <- function(sv, timestamp,
                                 threads = getOption("aedes.rootid_threads", 4L),
                                 chunksize = 1e5) {
  if (!length(sv)) return(bit64::integer64())
  fcc <- fafbseg::flywire_cave_client()
  res <- reticulate::py_call(py_parallel_roots(), fcc$chunkedgraph,
                             fafbseg:::rids2pyint(bit64::as.integer64(sv)),
                             fafbseg:::ts2pydatetime(timestamp),
                             as.integer(chunksize), as.integer(threads))
  fafbseg:::pyids2bit64(res, as_character = FALSE)
}

py_parallel_roots <- memoise::memoise(function() {
  reticulate::py_run_string("
def parallel_roots(cg, ids, timestamp, chunksize, threads):
    import numpy as np
    from concurrent.futures import ThreadPoolExecutor
    chunks = [ids[i:i + chunksize] for i in range(0, len(ids), chunksize)]
    def f(c):
        return np.asarray(cg.get_roots(c, timestamp=timestamp), dtype=np.int64)
    with ThreadPoolExecutor(max_workers=threads) as ex:
        return np.concatenate(list(ex.map(f, chunks)))
", local = TRUE, convert = FALSE)$parallel_roots
})

# roots expired (old) and created (new) between two times. Unlike
# fafbseg:::cave_get_delta_roots this fails loudly, since an empty result would
# silently leave stale rows. CAVE counts edits at or after `past` and before
# `future`, but a root lookup at `future` already sees an edit made exactly
# then, so the window is extended by 1 ms (edit times are whole ms).
cave_delta_roots <- function(past, future) {
  fcc <- fafbseg::flywire_cave_client()
  res <- reticulate::py_call(fcc$chunkedgraph$get_delta_roots,
                             timestamp_past = fafbseg:::ts2pydatetime(past),
                             timestamp_future = fafbseg:::ts2pydatetime(future + 0.001))
  pyslice <- fafbseg:::pyslice()$pyslice
  ids <- function(i) bit64::as.integer64(fafbseg:::pyids2bit64(
    reticulate::py_call(pyslice, res, i)))
  list(old = ids(0L), new = ids(1L))
}
