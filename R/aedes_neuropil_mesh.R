#' Mesh of the Aedes neuropil
#'
#' A `mesh3d` (rgl) object covering the Aedes brain neuropil, in nm
#' coordinates. Constructed by Dana Sherman from the synapse cloud.
#' See `data-raw/aedes_neuropil_mesh.R` for the regeneration script.
#'
#' @section Axis conventions: The Aedes volume was accidentally mirrored
#'   during acquisition, so its axes do not follow the usual conventions
#'   (e.g. those of FAFB/FlyWire). In raw and nm coordinates alike, +x points
#'   towards the animal's left, +y ventral and +z anterior. This is a
#'   mirror-handed frame, so renderings of the data are mirror images of the
#'   real brain, and the `side` column in [aedes_meta()] has left at high x.
#'
#'   View presets that assume FAFB axes therefore give misleading names: for
#'   example `nat::nview3d("posterior")` gives a frontal view of Aedes (z
#'   increasing towards the viewer) and `nat::nview3d("frontal")` a posterior
#'   one.
#'
#' @name aedes_neuropil_mesh
#' @docType data
#' @examples
#' \dontrun{
#' library(nat)
#' wire3d(aedes_neuropil_mesh, col='grey')
#' nview3d('posterior')  # a frontal view, see Axis conventions
#' # negative implies outside the mesh
#' pointsinside(matrix(c(2e5, 3e5, 1e5), ncol = 3),
#'              surf = aedes_neuropil_mesh, rval = "dist")
#' }
"aedes_neuropil_mesh"
