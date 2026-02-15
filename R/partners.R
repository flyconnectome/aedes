#' @noRd
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
