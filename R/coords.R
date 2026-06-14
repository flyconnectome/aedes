#' Handle raw and nm calibrated Aedes coordinates
#'
#' @description `aedes_voxdims()` returns image voxel dimensions used to scale
#'   between raw and nm coordinates.
#'
#' @param url Optional Neuroglancer URL containing voxel size metadata.
#'   Defaults to the active Aedes sample URL.
#' @return For `aedes_voxdims()`, a numeric 3-vector.
#' @export
#' @importFrom memoise memoise
#'
#' @examples
#' \dontrun{
#' aedes_voxdims()
#' }
aedes_voxdims <- memoise(function(url = choose_aedes(set = FALSE)[["fafbseg.sampleurl"]]) {
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

.aedes_mirror_landmarks_url <- "https://spelunker.cave-explorer.org/#!middleauth+https://global.daf-apis.com/nglstate/api/v1/4693107724517376"
.aedes_symmetric_mirror_axis_size <- 734.144

#' Mirror Aedes neurons or points to the opposite side of the brain
#'
#' @description
#' `aedes_mirror()` mirrors objects supported by [nat::xform()], including
#' neurons, neuronlists, dotprops and coordinate matrices.
#'
#' @param x An object to mirror.
#' @param method Mirror method. `"tps"` uses the bundled
#'   `aedes_aedesSym_1000_tps.rds` registration to map into Aedes symmetric
#'   space, flip across the X axis, then map back to original Aedes space.
#'   `"landmarks"` uses paired landmarks in the original Aedes space.
#' @param units Coordinate units for `x` and the returned object.
#'   The symmetric registration is defined in microns; nm inputs are scaled
#'   before and after transformation.
#' @param subset Optional subset passed to [nat::xform()], for example when
#'   transforming selected elements of a neuronlist.
#' @param ... Additional arguments passed to [nat::xform()].
#' @param landmarks Optional landmark data with `pointA` and `pointB` entries.
#'   When `NULL`, landmarks are read from `url` using
#'   [fafbseg::ngl_annotations()].
#' @param raw Whether landmark coordinates are in raw voxel space. When
#'   `FALSE`, landmark coordinates are assumed to be in `units`.
#' @param url Neuroglancer URL containing paired mirror landmarks.
#' @param vd Optional voxel dimensions in nm. Advanced use; when `NULL` and
#'   `raw = TRUE`, these are detected automatically.
#'
#' @details
#' Mirroring requires the suggested `Morpho` package at runtime.
#'
#' @return A transformed object of the same kind as `x`.
#' @export
#'
#' @examples
#' \dontrun{
#' sk <- with_aedes(fafbseg::read_l2skel(aedes_ids("class:DNa")[1]))
#' sk.mirror <- aedes_mirror(sk, units = "nm")
#'
#' plot3d(sk, col = "grey")
#' plot3d(sk.mirror, col = "red", add = TRUE)
#'
#' dps <- with_aedes(fafbseg::read_l2dp(aedes_ids("class:DNa")))
#' dps.mirror <- aedes_mirror(dps, units = "microns")
#' }
aedes_mirror <- function(x,
                         method = c("tps", "landmarks", "symmetric"),
                         units = c("nm", "microns"),
                         subset = NULL,
                         landmarks = NULL,
                         raw = TRUE,
                         url = .aedes_mirror_landmarks_url,
                         vd = NULL,
                         ...) {
  method <- match.arg(method)
  if (method == "symmetric") {
    method <- "tps"
  }
  units <- match.arg(units)
  check_package_available("Morpho")

  switch(
    method,
    landmarks = {
      nat::xform(
        x,
        reg = .aedes_mirror_reg_landmarks(
          units = units,
          landmarks = landmarks,
          raw = raw,
          url = url,
          vd = vd
        ),
        subset = subset,
        ...
      )
    },
    tps = {
      x_um <- if (units == "nm") x / 1e3 else x
      reg <- .aedes_mirror_reg_symmetric()
      x_sym <- nat::xform(x_um, reg = reg, subset = subset, ...)
      x_sym_flipped <- nat::mirror(
        x_sym,
        mirrorAxisSize = .aedes_symmetric_mirror_axis_size,
        mirrorAxis = "X",
        transform = "flip"
      )
      x_mirrored_um <- nat::xform(
        x_sym_flipped,
        reg = nat::reglist(reg, swap = TRUE),
        subset = subset,
        ...
      )
      if (units == "nm") x_mirrored_um * 1e3 else x_mirrored_um
    }
  )
}

#' Predict the L/R side of points in Aedes space
#'
#' @description Applies the Aedes mirror transform to each input point and
#'   measures the signed displacement along the mirror (X) axis before and
#'   after transform. The sign indicates which side of the midline the point
#'   lies on.
#'
#' @details Points on the left have \code{dist = (mirror_x - x)/2 < 0}; points
#'   on the right have \code{dist > 0}. The sign convention was calibrated
#'   against root id \code{648518347465408914} (\code{soma_xyz = "33038,5956,3550"}
#'   in raw voxels, side = \code{"L"}). Points with \code{|dist| <= threshold}
#'   are reported as midline (\code{"M"}). With \code{threshold = 0} a point
#'   exactly on the midline is reported as \code{"R"}.
#'
#' @param xyz Point coordinates. Anything accepted by
#'   \code{\link[nat]{xyzmatrix}} (matrix, data.frame, neuron, neuronlist), a
#'   length-3 numeric vector for a single point, or a character vector of
#'   comma-separated \code{"x,y,z"} strings (the convention used by
#'   \code{\link{aedes_soma_position}}).
#' @param units Units of the input coordinates. One of \code{"nm"} (the
#'   default), \code{"raw"} (image voxels, scaled via \code{\link{aedes_raw2nm}})
#'   or \code{"microns"}.
#' @param threshold Distance from the midline (in nm) below which points are
#'   reported as \code{"M"}. Default 5000 nm (~5 \eqn{\mu}m, ~0.7% of the
#'   x (medio-lateral) extent of the Aedes symmetric brain). Set to 0 to
#'   force all values to \code{"L"} or \code{"R"}.
#' @param rval What to return. \code{"side"} (the default) gives a character
#'   vector of side labels (\code{"L"}, \code{"R"} or \code{"M"}).
#'   \code{"distance"} gives a signed distance from the midline in nm
#'   (always nm, regardless of \code{units}), negative on the left,
#'   positive on the right.
#' @param method Mirror method passed to \code{\link{aedes_mirror}}. Default
#'   \code{"tps"} uses the bundled symmetric registration and needs no
#'   network access.
#'
#' @return When \code{rval = "side"}, a character vector of \code{"L"},
#'   \code{"R"} or \code{"M"}, one per input point, or \code{NA} for points
#'   whose mirror image could not be computed. When \code{rval = "distance"},
#'   a numeric vector of signed distances from the midline in nm.
#' @seealso \code{\link{aedes_mirror}}, \code{\link{aedes_soma_side}}
#' @export
#' @examples
#' \dontrun{
#' # known left-side point (raw voxel coords)
#' aedes_point_side(c(33038, 5956, 3550), units = "raw")
#'
#' # signed distance from the midline (always in nm)
#' aedes_point_side(c(33038, 5956, 3550), units = "raw", rval = "distance")
#' }
aedes_point_side <- function(xyz,
                             units = c("nm", "raw", "microns"),
                             threshold = 5000,
                             rval = c("side", "distance"),
                             method = c("tps", "landmarks")) {
  units <- match.arg(units)
  rval <- match.arg(rval)
  method <- match.arg(method)
  stopifnot(is.numeric(threshold), length(threshold) == 1L,
            is.finite(threshold), threshold >= 0)

  xyz <- nat::xyzmatrix(xyz)
  if (nrow(xyz) == 0L)
    return(if (identical(rval, "side")) character(0) else numeric(0))

  # Convert to nm: aedes_mirror() operates in nm or microns; we standardise
  # on nm so that the returned distance has consistent units.
  if (identical(units, "raw")) {
    xyz <- aedes_raw2nm(xyz)
  } else if (identical(units, "microns")) {
    xyz <- xyz * 1e3
  }

  ok <- is.finite(rowSums(xyz))
  mxyz <- matrix(NA_real_, nrow = nrow(xyz), ncol = 3L)
  if (any(ok)) {
    mxyz[ok, ] <- nat::xyzmatrix(
      aedes_mirror(xyz[ok, , drop = FALSE], method = method, units = "nm")
    )
  }

  # |dx| is twice the distance from the midline (point and mirror sit at
  # +d and -d). Aedes mirrors across the X axis, hence column 1.
  dist <- unname((mxyz[, 1] - xyz[, 1]) / 2)
  dist[!is.finite(dist)] <- NA_real_

  if (identical(rval, "distance"))
    return(dist)

  # dist < 0 -> left; dist == 0 deliberately maps to "R"
  # (caller can use threshold > 0 to get "M").
  side <- ifelse(dist < 0, "L", "R")
  side[is.na(dist)] <- NA_character_
  if (threshold > 0)
    side[!is.na(dist) & abs(dist) < threshold] <- "M"

  side
}

check_package_available <- function(pkg) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    stop("Please install suggested package: ", pkg, call. = FALSE)
  }

  invisible(TRUE)
}

.aedes_mirror_reg_landmarks <- memoise::memoise(function(units = c("nm", "microns"),
                                                         landmarks = NULL,
                                                         raw = TRUE,
                                                         url = .aedes_mirror_landmarks_url,
                                                         vd = NULL) {
  units <- match.arg(units)

  if (is.null(landmarks)) {
    landmarks <- fafbseg::ngl_annotations(url, types = "line")
  }

  if (!all(c("pointA", "pointB") %in% names(landmarks))) {
    stop("`landmarks` must contain `pointA` and `pointB` entries.", call. = FALSE)
  }

  pts_a <- nat::xyzmatrix(landmarks$pointA)
  pts_b <- nat::xyzmatrix(landmarks$pointB)

  if (nrow(pts_a) != nrow(pts_b)) {
    stop("`pointA` and `pointB` must contain the same number of landmarks.",
         call. = FALSE)
  }

  if (raw) {
    if (is.null(vd)) {
      vd <- aedes_voxdims()
    }
    pts_a <- aedes_raw2nm(pts_a, vd = vd)
    pts_b <- aedes_raw2nm(pts_b, vd = vd)
    if (units == "microns") {
      pts_a <- pts_a / 1e3
      pts_b <- pts_b / 1e3
    }
  }

  nat::tpsreg(rbind(pts_a, pts_b), rbind(pts_b, pts_a))
})

.aedes_mirror_reg_symmetric <- memoise::memoise(function() {
  readRDS(system.file(
    "extdata",
    "aedes_aedesSym_1000_tps.rds",
    package = "aedes",
    mustWork = TRUE
  ))
})
