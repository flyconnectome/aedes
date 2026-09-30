#' Summarise the synaptic partners of one or more Aedes neurons
#'
#' Tabulates the up- or downstream partners of a set of query neurons at a
#' chosen CAVE materialisation, returning one row per partner with the number
#' of connecting synapses. This is a thin Aedes-aware wrapper around
#' [fafbseg::flywire_partner_summary()]: it resolves the input via
#' [aedes_ids()], points fafbseg at the Aedes segmentation, and updates root
#' ids to the requested `version`/`timestamp` before querying. When a local
#' synapse snapshot has been selected with [aedes_synapse_snapshot()] the
#' query is instead answered from that snapshot, at the snapshot's time.
#'
#' @details With `method = "auto"` (the default) the local snapshot is used
#'   when one is selected, no `version` is given, `timestamp` is missing or
#'   matches the snapshot time, and `...` contains nothing other than
#'   `remove_autapses`; otherwise CAVE is queried. Note that without a
#'   `timestamp` a local query gives partners at the snapshot time, while a
#'   CAVE query gives them now. `method = "local"` gives an error rather than
#'   falling back to CAVE. The local and CAVE results should agree, apart from
#'   CAVE's default cleft score filtering and any root 0 (unassigned) partners,
#'   which the local method drops. The local result has `snapshot` and
#'   `timestamp` attributes.
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
#'   (`"local"`, see [aedes_synapse_snapshot()]) or choose automatically
#'   (`"auto"`, the default; see details).
#'
#' @return A `data.frame` with one row per partner neuron. `query` holds the
#'   query neuron root id and `weight` the synapse count; the partner root id
#'   is in `post_id` when `partners = "outputs"` and `pre_id` when
#'   `partners = "inputs"`. See [fafbseg::flywire_partner_summary()] for the
#'   full column description.
#'
#' @seealso [fafbseg::flywire_partner_summary()], [aedes_ids()],
#'   [aedes_synapse_snapshot()]
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
#' aedes_synapse_snapshot()
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
  snap = if (method != "cave") aedes_synapse_snapshot_active()
  if (method == "local" && is.null(snap))
    stop("No local synapse snapshot selected. See ?aedes_synapse_snapshot")
  if (!is.null(snap)) {
    why = partner_summary_local_problem(snap, version, timestamp, ...)
    if (method == "local" && !is.null(why))
      stop("Cannot use the local synapse snapshot: ", why)
    if (is.null(why)) method = "local"
  }
  if (method == "local") {
    rootids = aedes_ids(rootids, timestamp = snap$timestamp)
    rootids = with_aedes(fafbseg::flywire_latestid(rootids, timestamp = snap$timestamp))
    dots = list(...)
    remove_autapses = if (is.null(dots$remove_autapses)) TRUE else dots$remove_autapses
    return(synsnap_partner_summary(rootids, partners = partners,
                                   tag = snap$tag, root = snap$root,
                                   threshold = threshold,
                                   remove_autapses = remove_autapses))
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

# NULL if a partner query can be answered from snapshot `snap`, otherwise a
# string saying why not
partner_summary_local_problem <- function(snap, version = NULL, timestamp = NULL,
                                          ...) {
  dots = list(...)
  bad = setdiff(names(dots), "remove_autapses")
  if (length(bad))
    return(paste("argument(s)", paste(bad, collapse = ", "),
                 "are only supported for CAVE queries"))
  if (!is.null(version))
    return("a materialisation version was requested; use timestamp instead")
  if (is.null(timestamp)) return(NULL)
  ts = with_aedes(fafbseg::flywire_timestamp(timestamp = timestamp))
  if (abs(as.numeric(ts) - as.numeric(snap$timestamp)) > 1)
    return(sprintf("requested time %s differs from snapshot '%s' time %s",
                   format(ts, tz = "UTC", usetz = TRUE), snap$tag,
                   format(snap$timestamp, tz = "UTC", usetz = TRUE)))
  NULL
}
