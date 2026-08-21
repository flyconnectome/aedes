#' Summarise the synaptic partners of one or more Aedes neurons
#'
#' Tabulates the up- or downstream partners of a set of query neurons at a
#' chosen CAVE materialisation, returning one row per partner with the number
#' of connecting synapses. This is a thin Aedes-aware wrapper around
#' [fafbseg::flywire_partner_summary()]: it resolves the input via
#' [aedes_ids()], points fafbseg at the Aedes segmentation, and updates root
#' ids to the requested `version`/`timestamp` before querying.
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
#'   and `cleft.threshold`.
#'
#' @return A `data.frame` with one row per partner neuron. `query` holds the
#'   query neuron root id and `weight` the synapse count; the partner root id
#'   is in `post_id` when `partners = "outputs"` and `pre_id` when
#'   `partners = "inputs"`. See [fafbseg::flywire_partner_summary()] for the
#'   full column description.
#'
#' @seealso [fafbseg::flywire_partner_summary()], [aedes_ids()]
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
#' }
aedes_partner_summary <- function(rootids,
                                  partners = c("outputs", "inputs"),
                                  threshold = 0,
                                  version = NULL, timestamp = NULL,
                                  synapse_table = getOption("coconatfly.aedes.synapses", default = "synapses_v2"),
                                  ...) {
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
