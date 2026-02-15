#' Register Aedes dataset for coconatfly
#'
#' @description Register `aedes` dataset adapters for use with
#'   \href{https://natverse.org/coconatfly}{coconatfly}.
#'
#' @param showerror Logical; when `FALSE`, return invisibly if dependencies are missing.
#' @return Invisible `NULL`.
#'
#' @details
#' The aedes dataset is continually evolving. You three two main choices for how
#' to handle this.
#'
#' 1. use a specific numeric version (aka materialisation) of the segmentation.
#' 2. use the latest materialisation version (`version='latest'`)
#' 3. map ids to the current time (`version='now'`)
#'
#' Option 2 is the default since this can make queries somewhat faster and
#' stable but note that 'latest' can be several days old.
#' @export
#'
#' @examples
#' \dontrun{
#' register_aedes_coconat()
#' cf_meta(cf_ids(aedes="/class:MBON.*"))
#' aedes_set_version('now')
#' cf_meta(cf_ids(aedes="/class:MBON.*"))
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
    idfun = aedes_cfids,
    partnerfun = aedes_cfpartners
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
    dplyr::select(-dplyr::any_of("subsubclass")) %>%
    dplyr::rename(id = "root_id", lineage = "hemilineage") %>%
    dplyr::mutate(subsubclass = .data$subclass, subclass = .data$class, class = .data$superclass) %>%
    dplyr::select(-dplyr::any_of("superclass")) %>%
    dplyr::mutate(instance = dplyr::case_when(
      is.na(.data$instance) ~ paste0(.data$type, "_", ifelse(is.na(.data$side), "", .data$side)),
      TRUE ~ .data$instance
    ))
}

aedes_cfids <- function(ids = NULL, ignore.case = FALSE, fixed = FALSE,
                         which = NULL,
                         version = NULL, timestamp = NULL,
                         unique = FALSE, ...) {
  vi = aedes_get_version(which, timestamp = timestamp, version = version)
  ii = aedes_ids(ids, ignore.case = ignore.case, fixed = fixed, unique = unique,
                  version = vi$version, timestamp = vi$timestamp, ...)
  ii
}

#' @noRd
aedes_cfpartners <- function(ids, partners = c("outputs", "inputs"),
                                 threshold = 1, ...) {
  vi = aedes_get_version()
  partners = match.arg(partners)
  aedes_partner_summary(ids, partners = partners, threshold = threshold - 1L,
                        version = vi$version, timestamp = vi$timestamp, ...)
}
