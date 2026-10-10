#' Side of the neck connective through which a neuron leaves the brain
#'
#' @description Finds where each neuron passes through the neck connective
#'   (the cut face of the volume at low z) and reports which side of the neck
#'   midline it is on. This is the side convention used for ascending neurons,
#'   whose somata lie outside the brain volume.
#'
#' @details The neck point is the median position of the neuron's L2 nodes
#'   lying within `slab` sections of its lowest z. Neurons whose lowest L2 node
#'   is deeper than `zmax` never reach the neck and get `NA`.
#'
#'   The neck midline is tilted in the x-y plane, so neither a fixed x cut nor
#'   [aedes_point_side()] (whose mirror registration does not cover the neck)
#'   works here. The line \eqn{x = 15456 + 0.328 y} (raw voxels) was fitted
#'   with logistic regression on 209 ascending neurons with recorded L/R sides
#'   in `aedes_main` (2026-10-07) and disagrees with 6 of them. Points with
#'   larger x than the line are on the left.
#'
#'   L2 coordinates are fetched with one bulk L2 cache request per neuron.
#'
#' @param ids Root ids or anything accepted by [aedes_ids()].
#' @param slab Thickness (in raw z sections) of the band above the neuron's
#'   lowest point used to define the neck point.
#' @param zmax Neurons whose lowest L2 node has raw z above this value are
#'   taken not to reach the neck.
#' @inheritParams read_aedes_neurons
#'
#' @return A data.frame with columns `root_id`, `neck_xyz` (raw voxel
#'   coordinates as an `"x,y,z"` string) and `side` (`"L"`, `"R"` or `NA`).
#' @seealso [aedes_add_ans()], [aedes_point_side()]
#' @export
#' @examples
#' \dontrun{
#' aedes_neck_side("648518347504136947")
#' }
aedes_neck_side <- function(ids, slab = 50, zmax = 700,
                            version = NULL, timestamp = NULL) {
  vi <- aedes_get_version(version = version, timestamp = timestamp)
  root_ids <- as.character(aedes_ids(ids, version = vi$version,
                                     timestamp = vi$timestamp))
  client <- aedes_cave_client()
  pts <- t(vapply(root_ids, function(id) {
    xyz <- .aedes_l2_xyz(id, client = client)
    .aedes_neck_point(nat::xyzmatrix(aedes_nm2raw(xyz)), slab = slab,
                      zmax = zmax)
  }, numeric(3)))
  ok <- stats::complete.cases(pts)
  neck <- rep(NA_character_, length(root_ids))
  neck[ok] <- nat::xyzmatrix2str(round(pts[ok, , drop = FALSE]))
  data.frame(root_id = root_ids, neck_xyz = neck,
             side = .aedes_neck_side_xy(pts[, 1], pts[, 2]),
             row.names = NULL)
}

#' Add ascending neurons to aedes_main with their neck side
#'
#' @description Wraps [aedes_add_neurons()] for ascending neurons: sets
#'   `superclass = "ascending_neuron"`, skips the soma lookup (AN somata are
#'   outside the brain) and fills `side` from [aedes_neck_side()].
#'
#' @details `proofreader` is set when `status` is `"adequate"`. Neurons that
#'   do not reach the neck are written with an empty `side`.
#'
#' @param ids Root ids or anything accepted by [aedes_ids()].
#' @param status FlyTable status, passed to [aedes_add_neurons()].
#' @param ... Additional columns passed to [aedes_add_neurons()].
#' @param dryrun If `TRUE` (the default), show what would be written.
#'
#' @return The result of [aedes_add_neurons()].
#' @seealso [aedes_neck_side()], [aedes_add_neurons()]
#' @export
#' @examples
#' \dontrun{
#' aedes_add_ans("648518347504136947", status = "adequate", dryrun = FALSE)
#' }
aedes_add_ans <- function(ids, status = c("adequate", "to_review",
                                          "needs_extending", "incomplete"),
                          ..., dryrun = TRUE) {
  status <- match.arg(status)
  ns <- aedes_neck_side(ids)
  aedes_add_neurons(ns$root_id, dryrun = dryrun, ...,
                    superclass = "ascending_neuron", status = status,
                    soma = FALSE, side = ns$side,
                    proofreader = identical(status, "adequate"))
}

# neck midline x = intercept + slope * y, raw voxels; fitted 2026-10-07 on
# 209 ascending neurons with recorded sides (see aedes_neck_side details)
.aedes_neck_midline <- c(intercept = 15456, slope = 0.328)

#' @noRd
.aedes_neck_side_xy <- function(x, y, midline = .aedes_neck_midline) {
  xmid <- midline[["intercept"]] + midline[["slope"]] * y
  side <- ifelse(x > xmid, "L", "R")
  side[!is.finite(x) | !is.finite(y)] <- NA_character_
  side
}

# median of the L2 nodes within `slab` sections of the lowest one, or NA when
# the neuron stops short of the neck. xyz in raw voxels.
#' @noRd
.aedes_neck_point <- function(xyz, slab = 50, zmax = 700) {
  if (!nrow(xyz)) return(rep(NA_real_, 3))
  zmin <- min(xyz[, 3])
  if (zmin > zmax) return(rep(NA_real_, 3))
  apply(xyz[xyz[, 3] <= zmin + slab, , drop = FALSE], 2, stats::median)
}

# L2 node positions (nm) for one root id in a single bulk L2 cache request;
# fafbseg::flywire_l2attributes() makes one request per node (~0.4 s each).
#' @noRd
.aedes_l2_xyz <- function(root_id, client = aedes_cave_client()) {
  check_package_available("reticulate")
  l2 <- with_aedes(fafbseg::flywire_l2ids(root_id, integer64 = TRUE))
  if (!length(l2)) return(matrix(numeric(0), ncol = 3))
  d <- client$l2cache$get_l2data(
    reticulate::r_to_py(as.character(l2))$copy(),
    attributes = list("rep_coord_nm"))
  xyz <- lapply(d, function(z) unlist(z$rep_coord_nm))
  xyz <- xyz[lengths(xyz) == 3L]
  matrix(unlist(xyz, use.names = FALSE), ncol = 3, byrow = TRUE)
}
