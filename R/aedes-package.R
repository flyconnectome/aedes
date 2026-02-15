#' @keywords internal
#' @import fafbseg
#' @importFrom magrittr %>%
#' @importFrom rlang .data
#' @importFrom memoise memoise
"_PACKAGE"

NULL

if (getRversion() >= "2.15.1") {
  utils::globalVariables(c(
    "_id", "class1", "class2", "good_status", "hemilineage", "n",
    "point_xyz", "root_duplicated", "root_id", "serial_id", "status",
    "subclass", "subsubclass", "superclass", "supervoxel_id", "type"
  ))
}
