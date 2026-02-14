#' Handle raw and nm calibrated Aedes coordinates
#'
#' @description `aedes_voxdims()` returns image voxel dimensions used to scale
#'   between raw and nm coordinates.
#'
#' @param url Optional Neuroglancer URL containing voxel size metadata.
#'   Defaults to the active Aedes sample URL.
#' @return For `aedes_voxdims()`, a numeric 3-vector.
#' @export
#'
#' @examples
#' \dontrun{
#' aedes_voxdims()
#' }
aedes_voxdims <- memoise::memoise(function(url = choose_aedes(set = FALSE)[["fafbseg.sampleurl"]]) {
  fafbseg::flywire_voxdims(url)
})

#' @param x 3D coordinates in any form compatible with [nat::xyzmatrix()].
#' @param vd Voxel dimensions in nm. Advanced use; normally detected automatically.
#' @return For `aedes_raw2nm()` and `aedes_nm2raw()`, an N x 3 numeric matrix.
#' @rdname aedes_voxdims
#' @export
#'
#' @examples
#' \dontrun{
#' aedes_raw2nm(c(159144, 22192, 3560))
#' aedes_nm2raw(c(2546304, 355072, 160200))
#' }
aedes_nm2raw <- function(x, vd = aedes_voxdims()) {
  xyz <- nat::xyzmatrix(x)
  xyz[, 1] <- xyz[, 1] / vd[1]
  xyz[, 2] <- xyz[, 2] / vd[2]
  xyz[, 3] <- xyz[, 3] / vd[3]
  xyz
}

#' @rdname aedes_voxdims
#' @export
aedes_raw2nm <- function(x, vd = aedes_voxdims()) {
  xyz <- nat::xyzmatrix(x)
  xyz[, 1] <- xyz[, 1] * vd[1]
  xyz[, 2] <- xyz[, 2] * vd[2]
  xyz[, 3] <- xyz[, 3] * vd[3]
  xyz
}
