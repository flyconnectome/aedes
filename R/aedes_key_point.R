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
#' @details A thin wrapper around [fafbseg::flywire_key_point()] evaluated in
#'   the aedes segmentation context via [with_aedes()].
#'
#' @param ids One or more aedes root ids (or anything accepted by
#'   [aedes_ids()]).
#' @param raw Whether to return points in raw (voxel) space (default) or nm.
#' @param reroot Whether to reroot the incoming neuron onto the furthest
#'   endpoint before simplifying.
#' @param ... Additional arguments passed to [pbapply::pbsapply()].
#' @return An N x 3 matrix of point locations (one row per input id).
#' @seealso [fafbseg::flywire_key_point()],
#'   [fafbseg::key_point_from_neuron()]
#' @export
#' @examples
#' \dontrun{
#' aedes_key_point('648518347569414567')
#' }
aedes_key_point <- function(ids, raw = TRUE, reroot = TRUE, ...) {
  ids <- aedes_ids(ids)
  with_aedes(fafbseg::flywire_key_point(ids, raw = raw, reroot = reroot, ...))
}
