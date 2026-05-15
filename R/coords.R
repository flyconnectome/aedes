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
#' @param subset Optional subset passed to [nat::xform()] for the landmarks
#'   method. The TPS method currently mirrors the whole object.
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
#' @return A transformed object of the same kind as `x`.
#' @export
#'
#' @examples
#' \dontrun{
#' sk <- with_aedes(fafbseg::read_l2skel(aedes_ids("class:DNa")[1]))
#' sk.tps.mirror <- aedes_mirror(sk / 1000)
#' sk.landmark.mirror <- aedes_mirror(sk / 1000, method = "landmarks")
#'
#' dps <- with_aedes(fafbseg::read_l2dp(aedes_ids("class:DNa")))
#' dps.tps.mirror <- aedes_mirror(dps)
#' dps.landmark.mirror <- aedes_mirror(dps, method = "landmarks")
#' }
aedes_mirror <- function(x,
                         method = c("tps", "landmarks", "symmetric"),
                         units = c("microns", "nm"),
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

  switch(
    method,
    landmarks = nat::xform(
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
    ),
    tps = {
      if (!is.null(subset)) {
        stop("`subset` is not currently supported for method = \"tps\".",
             call. = FALSE)
      }

      x_um <- if (units == "nm") x / 1e3 else x
      reg <- .aedes_mirror_reg_symmetric()
      x_sym <- nat::xform(x_um, reg = reg, ...)
      x_sym_flipped <- nat::mirror(
        x_sym,
        mirrorAxisSize = .aedes_symmetric_mirror_axis_size,
        mirrorAxis = "X",
        transform = "flip"
      )
      x_mirrored_um <- nat::xform(x_sym_flipped, reg = nat::reglist(reg, swap = TRUE), ...)
      if (units == "nm") x_mirrored_um * 1e3 else x_mirrored_um
    }
  )
}

.aedes_mirror_reg_landmarks <- memoise::memoise(function(units = c("microns", "nm"),
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
