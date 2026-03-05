#' Query Aedes supervoxel IDs from point coordinates
#'
#' @param x 3D coordinates in any form compatible with [nat::xyzmatrix()].
#' @param rawcoords Whether `x` is already in raw voxel coordinates (`TRUE`) or
#'   in nm coordinates (`FALSE`).
#' @param voxdims Voxel dimensions in nm used to convert nm coordinates to raw
#'   voxel coordinates when `rawcoords = FALSE`.
#' @param mip MIP scale (`s` in the transform-service URL).
#' @param format Response/input format suffix for the transform-service URL.
#' @param dataset Transform-service dataset name.
#' @param base_url Transform-service base URL.
#'
#' @return A character vector of supervoxel IDs (`uint64`) of length `nrow(x)`.
#' @export
#'
#' @examples
#' \dontrun{
#' aedes_supervoxels(c(159144, 22192, 3560))
#' }
aedes_supervoxels <- function(
    x,
    rawcoords = TRUE,
    voxdims = aedes_voxdims(),
    mip = 0,
    format = "array_float_Nx3",
    dataset = "wclee_aedes_brain",
    base_url = "https://flyem.mrc-lmb.cam.ac.uk/transform-service/query/dataset") {
  xyz <- nat::xyzmatrix(x)
  pts <- if (isTRUE(rawcoords)) {
    xyz
  } else {
    scale(xyz, center = FALSE, scale = voxdims)
  }
  ptsb <- writeBin(as.vector(pts), con = raw(), size = 4)
  u <- sprintf("%s/%s/s/%d/values_binary/format/%s", base_url, dataset, mip, format)

  res <- httr::POST(u, body = ptsb, encode = "raw")
  httr::stop_for_status(res)
  arr <- httr::content(res, as = "raw")
  bytes <- readBin(
    arr,
    what = numeric(),
    n = length(arr) / 8,
    size = 8,
    endian = "little"
  )
  class(bytes) <- "integer64"
  as.character(bytes)
}
