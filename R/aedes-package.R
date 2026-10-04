#' @keywords internal
#' @section Package Options: \itemize{
#'
#'   \item{\code{aedes.version}} Default materialisation selector used by
#'   \code{\link{aedes_get_version}} (and, transitively, everything that pins a
#'   timestamp -- \code{\link{aedes_meta}}, \code{\link{aedes_add_neurons}},
#'   \code{\link{aedes_set_meta}}, \code{\link{aedes_set_group}}). Accepts
#'   \code{"now"} (set when the package loads, unless already set),
#'   \code{"latest"}, an integer materialisation version or an explicit
#'   timestamp. Set with \code{\link{aedes_set_version}} or
#'   \code{options(aedes.version = ...)}, e.g. in your \code{.Rprofile}.
#'
#'   \item{\code{aedes.initials}} Curator initials used to auto-fill the
#'   single-string \code{initials} column and, when
#'   \code{annotator = TRUE} / \code{proofreader = TRUE}, appended to the
#'   corresponding multi-select column. Consumed by
#'   \code{\link{aedes_add_neurons}}, \code{\link{aedes_set_meta}} and
#'   \code{\link{aedes_set_group}}. Set once per session with
#'   \code{options(aedes.initials = "XY")}.
#'
#'   }
#' @import fafbseg
#' @importFrom magrittr %>%
#' @importFrom rlang .data
#' @importFrom dplyr add_count arrange desc distinct filter mutate select
#' @importFrom stats setNames
"_PACKAGE"
