#' Summarise the synaptic partners of one or more Aedes neurons
#'
#' Tabulates the up- or downstream partners of a set of query neurons at a
#' chosen CAVE materialisation, returning one row per partner with the number
#' of connecting synapses. This is a thin Aedes-aware wrapper around
#' [fafbseg::flywire_partner_summary()]: it resolves the input via
#' [aedes_ids()], points fafbseg at the Aedes segmentation, and updates root
#' ids to the requested `version`/`timestamp` before querying. When a local
#' synapse snapshot has been selected with [aedes_use_snapshot()] the
#' query is instead answered from that snapshot, updated to the requested time.
#'
#' @details With `method = "auto"` (the default) the local snapshot is used
#'   when one is selected, the requested time is not before the snapshot, and
#'   `...` contains nothing other than `remove_autapses`; otherwise CAVE is
#'   queried. `method = "local"` gives an error rather than falling back to
#'   CAVE.
#'
#'   The time of a local query is `timestamp` (or the time of `version`) when
#'   given, otherwise that of the `aedes.version` option (see
#'   [aedes_set_version()]), just as for CAVE queries. The query starts from
#'   the newest snapshot in the selected snapshot's folder at or before that
#'   time, which may be older or newer than the selected one.
#'
#'   Local queries after the snapshot time fetch only the changes made since
#'   then from CAVE and look up the new root ids of the affected synapses'
#'   supervoxels. These updates are kept for the rest of the R session, so the
#'   first query after a long gap may take a while (seconds to a few minutes)
#'   but later ones are quick. A query for `"now"` reuses the last update if it
#'   is less than `getOption("aedes.synapse_max_age", 60)` seconds old. Small
#'   queries may instead update just their own synapses when that is cheaper
#'   (tuned by the `aedes.synapse_head_ratio` and `aedes.synapse_head_min_sv`
#'   options).
#'
#'   The local and CAVE results should agree, apart from CAVE's default cleft
#'   score filtering and any root 0 (unassigned) partners, which the local
#'   method drops. The local result has `snapshot`, `timestamp` (the time it is
#'   valid for) and `method` attributes.
#'
#' @param rootids Query neurons in any form accepted by [aedes_ids()] (root
#'   ids or a FlyTable query string).
#' @param partners Whether to summarise `"outputs"` (downstream partners, the
#'   default) or `"inputs"` (upstream partners).
#' @param threshold Only return partners connected by more than `threshold`
#'   synapses (default `0`, i.e. all partners).
#' @param version,timestamp Optional CAVE materialisation selectors. When
#'   supplied, query ids are first updated to the corresponding version /
#'   timestamp with [fafbseg::flywire_latestid()], and the synapse query is
#'   run against that materialisation. Give at most one of the two.
#' @param synapse_table CAVE synapse table to query. Defaults to the
#'   `coconatfly.aedes.synapses` option (`"synapses_v2"`).
#' @param ... Additional arguments passed on to
#'   [fafbseg::flywire_partner_summary()]. Power-user options include
#'   `remove_autapses` (set `FALSE` to keep self-connections; see examples)
#'   and `cleft.threshold`. Only `remove_autapses` is supported by the local
#'   method.
#' @param method Whether to query CAVE (`"cave"`), a local synapse snapshot
#'   (`"local"`, see [aedes_use_snapshot()]) or choose automatically
#'   (`"auto"`, the default; see details).
#'
#' @return A `data.frame` with one row per partner neuron. `query` holds the
#'   query neuron root id and `weight` the synapse count; the partner root id
#'   is in `post_id` when `partners = "outputs"` and `pre_id` when
#'   `partners = "inputs"`. See [fafbseg::flywire_partner_summary()] for the
#'   full column description.
#'
#' @seealso [fafbseg::flywire_partner_summary()], [aedes_ids()],
#'   [aedes_use_snapshot()]
#' @export
#' @examples
#' \dontrun{
#' # downstream partners of a neuron, keeping only strong connections
#' aedes_partner_summary("720575940...", threshold = 4)
#'
#' # inputs instead of outputs
#' aedes_partner_summary("720575940...", partners = "inputs")
#'
#' # Power-user: query a specific CAVE materialisation rather than 'now'
#' aedes_partner_summary("720575940...", version = 1000)
#' aedes_partner_summary("720575940...", timestamp = "2024-01-01")
#'
#' # Power-user: include autapses (self-connections). MBON11 is strongly
#' # autaptic, so its own root id appears among its downstream partners when
#' # remove_autapses = FALSE (the fafbseg default drops these).
#' mbon11 <- aedes_ids("cell_type:MBON11")
#' aedes_partner_summary(mbon11, remove_autapses = FALSE)
#'
#' # answer from a local synapse snapshot
#' options(aedes.synapse_snapshot_root = "~/data/aedes/syn_snapshot")
#' aedes_use_snapshot()
#' aedes_partner_summary(mbon11, method = "local")
#' }
aedes_partner_summary <- function(rootids,
                                  partners = c("outputs", "inputs"),
                                  threshold = 0,
                                  version = NULL, timestamp = NULL,
                                  synapse_table = getOption("coconatfly.aedes.synapses", default = "synapses_v2"),
                                  method = c("auto", "cave", "local"),
                                  ...) {
  partners = match.arg(partners)
  method = match.arg(method)
  snap = if (method != "cave") aedes_snapshot_active()
  if (method == "local" && is.null(snap))
    stop("No local synapse snapshot selected. See ?aedes_use_snapshot")
  if (!is.null(snap)) {
    when = partner_summary_local_time(version, timestamp)
    if (identical(when, "now") || as.numeric(when) > as.numeric(snap$timestamp))
      aedes_snapshot_refresh(snap$root)
    # start from the newest snapshot at or before the query time: an older one
    # than selected for an earlier time, a newer one for a later time or now
    tag = synsnap_at(snap$root,
                     if (identical(when, "now")) aedes_synsnap_ctx()$now() else when)
    if (!is.null(tag) && !identical(tag, snap$tag))
      snap = aedes_use_snapshot(tag, root = snap$root, set = FALSE)
    why = partner_summary_local_problem(snap, when, ...)
    if (method == "local" && !is.null(why))
      stop("Cannot use the local synapse snapshot: ", why)
    if (is.null(why)) method = "local"
  }
  if (method == "local") {
    # plain ids are checked against the snapshot's root log, which is cheaper
    # than updating them through FlyTable/CAVE
    if (!all(fafbseg:::valid_id(rootids, na.ok = FALSE)))
      rootids = aedes_ids(rootids, timestamp = when)
    dots = list(...)
    remove_autapses = if (is.null(dots$remove_autapses)) TRUE else dots$remove_autapses
    return(synsnap_partner_summary(
      rootids, partners = partners, tag = snap$tag, root = snap$root,
      threshold = threshold, remove_autapses = remove_autapses,
      timestamp = when, ctx = aedes_synsnap_ctx(),
      max_age = getOption("aedes.synapse_max_age", 60),
      f = getOption("aedes.synapse_head_ratio", 0.3),
      min_sv = getOption("aedes.synapse_head_min_sv", 5e4)))
  }
  # resolve the aedes.version option here: fafbseg treats no version or
  # timestamp as a live query at the current time, and aedes_ids() would not
  # update the ids. "now" becomes one timestamp for both.
  if (is.null(version) && is.null(timestamp)) {
    which = getOption("aedes.version", "now")
    if (is.numeric(which) || identical(which, "latest"))
      version = aedes_get_version(version = which)$version
    else timestamp = aedes_get_version(timestamp = which)$timestamp
  }
  rootids = aedes_ids(rootids, version = version, timestamp = timestamp)
  withr::with_options(choose_aedes(set = FALSE), {
    if (!is.null(version)) {
      # TODO: use exported fafbseg::flywire_version when available
      version = fafbseg:::flywire_version(version)
      rootids = fafbseg::flywire_latestid(rootids, version = version)
    } else if (!is.null(timestamp)) {
      timestamp = fafbseg::flywire_timestamp(timestamp = timestamp)
      rootids = fafbseg::flywire_latestid(rootids, timestamp = timestamp)
    }
    fafbseg::flywire_partner_summary(
      rootids = rootids,
      partners = partners,
      threshold = threshold,
      version = version,
      timestamp = timestamp,
      synapse_table = synapse_table,
      method = "cave",
      ...
    )
  })
}

# The time a local query should use: an explicit timestamp or version, else
# the aedes.version option ("latest" meaning the time of the newest version).
# "now" is kept as is, since updates to now are cached differently.
partner_summary_local_time <- function(version = NULL, timestamp = NULL) {
  if (is.null(version) && is.null(timestamp)) {
    which = getOption("aedes.version", "now")
    if (is.numeric(which) || identical(which, "latest")) version = which
    else timestamp = which
  }
  if (identical(timestamp, "now")) return("now")
  if (!is.null(timestamp))
    return(with_aedes(fafbseg::flywire_timestamp(timestamp = timestamp)))
  aedes_version_timestamp(version)
}

aedes_version_timestamp <- function(version = "latest") {
  v = aedes_get_version(version = version)$version
  with_aedes(fafbseg::flywire_timestamp(version = v))
}

# NULL if a partner query can be answered from snapshot `snap` at `when`,
# otherwise a string saying why not
partner_summary_local_problem <- function(snap, when, ...) {
  dots = list(...)
  bad = setdiff(names(dots), "remove_autapses")
  if (length(bad))
    return(paste("argument(s)", paste(bad, collapse = ", "),
                 "are only supported for CAVE queries"))
  if (!identical(when, "now") && as.numeric(when) < as.numeric(snap$timestamp) - 1)
    return(sprintf("requested time %s is before snapshot '%s' time %s",
                   format(when, tz = "UTC", usetz = TRUE), snap$tag,
                   format(snap$timestamp, tz = "UTC", usetz = TRUE)))
  NULL
}
