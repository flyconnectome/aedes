#' Find Aedes root or supervoxel (leaf) IDs for XYZ locations
#'
#' @param method Lookup method: `"auto"` and `"spine"` use the Aedes transform
#'   service; `"cloudvolume"` delegates to [fafbseg::flywire_xyz2id()].
#' @inheritParams fafbseg::flywire_xyz2id
#' @param ... Additional arguments passed to backend helpers.
#'
#' @return A vector of segment IDs (`character` or `integer64`).
#' @details Method auto (which maps to spine) should be much faster for look ups
#' with many points, especially points in the same region of space.
#'
#' @export
#'
#' @examples
#' \dontrun{
#' aedes_xyz2id(c(24606, 12450, 5798), rawcoords = TRUE, root = FALSE)
#' }
aedes_xyz2id <- function(
    xyz,
    rawcoords = FALSE,
    voxdims = aedes_voxdims(),
    cloudvolume.url = NULL,
    root = TRUE,
    timestamp = NULL,
    version = NULL,
    stop_layer = NULL,
    integer64 = FALSE,
    method = c("auto", "cloudvolume", "spine"),
    ...) {
  method <- match.arg(method)

  if (isTRUE(is.numeric(xyz) && is.vector(xyz) && length(xyz) == 3)) {
    xyz <- matrix(xyz, ncol = 3)
  } else {
    xyz <- nat::xyzmatrix(xyz)
  }

  if (method == "cloudvolume") {
    return(with_aedes(fafbseg::flywire_xyz2id(
      xyz = xyz,
      rawcoords = rawcoords,
      voxdims = voxdims,
      cloudvolume.url = cloudvolume.url,
      root = root,
      timestamp = timestamp,
      version = version,
      stop_layer = stop_layer,
      integer64 = integer64,
      method = "cloudvolume",
      ...
    )))
  }

  xyz_raw <- if (isTRUE(rawcoords)) {
    xyz
  } else {
    scale(xyz, scale = voxdims, center = FALSE)
  }

  na_rows <- !stats::complete.cases(xyz_raw)
  n <- nrow(xyz_raw)
  zero_ids <- if (integer64) bit64::as.integer64(rep("0", n)) else rep("0", n)

  if (all(na_rows)) {
    return(zero_ids)
  }

  res <- aedes_supervoxels(xyz_raw[!na_rows, , drop = FALSE])
  if (!root) {
    looked_up <- fafbseg::flywire_ids(res, integer64 = integer64)
    out <- zero_ids
    out[!na_rows] <- looked_up
    return(out)
  }
  if (root) {
    res <- with_aedes(fafbseg::flywire_rootid(
      res,
      cloudvolume.url = cloudvolume.url,
      timestamp = timestamp,
      version = version,
      stop_layer = stop_layer,
      integer64 = integer64
    ))
    out <- zero_ids
    out[!na_rows] <- res
    return(out)
  }
}

#' @noRd
aedes_supervoxels <- function(
    x,
    mip = 0,
    format = "array_float_Nx3",
    dataset = "wclee_aedes_brain",
    base_url = "https://flyem.mrc-lmb.cam.ac.uk/transform-service/query/dataset") {
  pts <- nat::xyzmatrix(x)
  ptsb <- writeBin(as.vector(pts), con = raw(), size = 4)
  u <- glue::glue("{base_url}/{dataset}/s/{mip}/values_binary/format/{format}")

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
