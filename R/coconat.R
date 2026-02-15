#' Register Aedes dataset for coconatfly
#'
#' @description Register `aedes` dataset adapters for use with
#'   \href{https://natverse.org/coconatfly}{coconatfly}.
#'
#' @param showerror Logical; when `FALSE`, return invisibly if dependencies are missing.
#' @return Invisible `NULL`.
#' @export
#'
#' @examples
#' \dontrun{
#' register_aedes_coconat()
#' }
register_aedes_coconat <- function(showerror = TRUE) {
  if (!requireNamespace("coconatfly", quietly = !showerror)) {
    if (!showerror) return(invisible(NULL))
    stop("Package 'coconatfly' is required. Install with: devtools::install_github('natverse/coconatfly')")
  }
  if (!requireNamespace("coconat", quietly = !showerror)) {
    if (!showerror) return(invisible(NULL))
    stop("Package 'coconat' is required. Install with: devtools::install_github('natverse/coconat')")
  }

  coconat::register_dataset(
    name = "aedes",
    shortname = "ab",
    species = "Aedes aegypti",
    sex = "F",
    age = "mated adult",
    namespace = "coconatfly",
    description = paste(sep="\n",
      "A mated adult female Aedes aegypti prepared by Meg Younger's lab",
      "sectioned and imaged by Wei Lee's lab with David Hildebrand and segmented",
      "and registered segmented in collaboration with zetta.ai"),
    metafun = aedes_cfmeta,
    idfun = aedes_ids,
    partnerfun = aedes_cfpartners_now
  )

  invisible(NULL)
}

#' @noRd
aedes_cfmeta <- function(ids = NULL, ignore.case = FALSE, fixed = FALSE,
                         which = NULL,
                         version = NULL, timestamp = NULL,
                         unique = TRUE, ...) {
  vi = aedes_get_version(which, timestamp = timestamp, version = version)
  df = aedes_meta(ids, ignore.case = ignore.case, fixed = fixed, unique = unique,
                  version = vi$version, timestamp = vi$timestamp, ...)
  df %>%
    dplyr::select(-subsubclass) %>%
    dplyr::rename(id = root_id) %>%
    dplyr::rename(class1 = superclass, class2 = class, subsubclass = subclass) %>%
    dplyr::rename(class = class1, subclass = class2) %>%
    dplyr::rename(lineage = hemilineage) %>%
    dplyr::mutate(instance = dplyr::case_when(
      is.na(instance) ~ paste0(type, "_", ifelse(is.na(side), "", side)),
      TRUE ~ instance
    ))
}

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

#' @noRd
aedes_cfpartners <- function(ids, partners = c("outputs", "inputs"),
                             threshold = 1, version = "latest", ...) {
  partners = match.arg(partners)
  aedes_partner_summary(ids, partners = partners, threshold = threshold - 1L, version = version, ...)
}

#' @noRd
aedes_cfpartners_now <- function(ids, partners = c("outputs", "inputs"),
                                 threshold = 1, ...) {
  vi = aedes_get_version()
  partners = match.arg(partners)
  aedes_partner_summary(ids, partners = partners, threshold = threshold - 1L,
                        version = vi$version, timestamp = vi$timestamp, ...)
}
