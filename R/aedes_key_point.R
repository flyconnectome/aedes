#' Find a good "key" point on a neuron to associate with annotations
#'
#' @description The chosen point sits at the major branch point of the L2
#'   skeleton of each neuron. By default the L2 skeleton is rerooted onto the
#'   endpoint furthest from the current root so that a simplified
#'   representation with one branch point can be calculated; without this, the
#'   longest path from the root may not contain a branch point at all. If no
#'   branch point can be identified the original root point is used as a
#'   fallback.
#'
#' @param ids One or more aedes root ids (or anything accepted by
#'   [aedes_ids()]).
#' @param raw Whether to return points in raw (voxel) space (default) or nm.
#' @param reroot Whether to reroot the incoming neuron onto the furthest
#'   endpoint before simplifying.
#' @param ... Additional arguments passed to [pbapply::pbsapply()].
#' @return An N x 3 matrix of point locations (one row per input id).
#' @export
#' @examples
#' \dontrun{
#' aedes_key_point('648518347569414567')
#' }
aedes_key_point <- function(ids, raw = TRUE, reroot = TRUE, ...) {
  ids <- aedes_ids(ids)
  with_aedes(flywire_key_point(ids, raw = raw, reroot = reroot, ...))
}

#' Dataset-agnostic key-point lookup for flywire-style segmentations
#'
#' Reads an L2 skeleton via [fafbseg::read_l2skel()] for each root id, then
#' calls `key_point_from_neuron()`. Assumes the ambient cave/segmentation
#' context is already configured (e.g. wrap with [with_aedes()]). Intended to
#' move to fafbseg once stable.
#'
#' @inheritParams aedes_key_point
#' @return An N x 3 matrix of point locations.
#' @noRd
flywire_key_point <- function(ids, raw = TRUE, reroot = TRUE, ...) {
  if (length(ids) > 1) {
    res <- pbapply::pbsapply(ids, flywire_key_point, raw = raw, reroot = reroot, ...)
    return(t(res))
  }
  tryCatch({
    n <- fafbseg::read_l2skel(ids)[[1]]
    nmpt <- key_point_from_neuron(n, reroot = reroot)
    if (raw) fafbseg::flywire_nm2raw(nmpt) else nmpt
  }, error = function(e) {
    warning("Unable to extract key point for id: ", ids, ": ", conditionMessage(e))
    cbind(NA, NA, NA)
  })
}

#' Pick the principal branch point of a neuron
#'
#' Pure helper operating on an in-memory `neuron`. Reroots onto the endpoint
#' furthest from the current root (so the longest path through the neuron
#' passes through at least one branch point), simplifies to a single branch
#' point, and returns the xyz of that branch point in nm. Falls back to the
#' original root point with a warning if no branch point can be found.
#'
#' @param n A `neuron` (typically an L2 skeleton).
#' @param reroot Whether to reroot onto the furthest endpoint first.
#' @return A length-3 nm xyz vector.
#' @noRd
key_point_from_neuron <- function(n, reroot = TRUE) {
  if (reroot) {
    eps <- nat::endpoints(n)
    ng <- nat::as.ngraph(n, weights = TRUE)
    # there should only be one rootpoint but just occasionally ...
    epdists <- igraph::distances(ng, v = nat::rootpoints(n)[1], to = eps)
    n <- nat::reroot(n, eps[which.max(epdists)])
  }
  n1 <- nat::simplify_neuron(n, n = 1)
  bp1 <- nat::branchpoints(n1)
  if (length(bp1) < 1) {
    warning("Unable to extract key point, falling back to root!")
    bp1 <- 1L
  }
  nat::xyzmatrix(n1)[bp1[1], ]
}
