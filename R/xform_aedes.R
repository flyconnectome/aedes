#' Move data between Aedes and Drosophila brain spaces
#'
#' @description
#' `xform_aedes()` maps neurons, dotprops, meshes or raw coordinates between the
#' *Aedes aegypti* whole-brain EM space and *Drosophila* brain spaces. One of
#' `sample` and `reference` must be `"aedes"`; the other may be `"FlyWire"` or
#' any template brain the natverse can bridge to, such as `"JRC2018F"`,
#' `"FCWB"` or `"JFRC2"`.
#'
#' @details
#' The Aedes end is handled by bundled thin-plate spline registrations built
#' from cognate neuron pairs — neurons of the same cell type identified in both
#' datasets — which were brought into a shared frame by a whole-brain affine,
#' warped pair by pair with Deformetrica, and combined into one dense spline.
#' See <https://github.com/flyconnectome/2025aedes> for the pipeline.
#'
#' Anything beyond FlyWire is reached by handing over to
#' [nat.templatebrains::xform_brain()] with FlyWire as the bridge, so
#' `"aedes"` to `"JRC2018F"` runs Aedes to FlyWire to JRC2018F, and
#' `"aedes"` to `"FCWB"` continues on through JFRC2013 and JFRC2.
#'
#' Which fly spaces are reachable depends on the bridging registrations
#' installed. With `nat.flybrains`, `nat.jrcbrains` and `elmr` present that
#' includes `"JRC2018F"`, `"JRC2018U"`, `"JRCFIB2018F"` (the hemibrain),
#' `"JFRC2013"`, `"JFRC2"` and `"FCWB"`. Those packages need only be installed,
#' not attached — `xform_aedes()` loads whichever are available before
#' bridging, because their registrations are only added to the graph when their
#' namespace loads. See [nat.templatebrains::bridging_graph()] for what is
#' actually reachable on a given machine.
#'
#' Each Aedes direction has its own registration rather than one being inverted
#' from the other: a thin-plate spline refitted the other way round is not the
#' inverse of the forward map, and round-tripping through
#' `nat::reglist(swap = TRUE)` costs several microns.
#'
#' Accuracy is limited by genuine anatomical divergence between the two species,
#' rather than by the spline. The underlying registration matches cognate
#' neurons to a mean nearest-neighbour distance of about 9 um, and an Aedes to
#' FlyWire round trip has a median error of 10 um, rising to 39 um at the 95th
#' percentile. Errors are much larger in the optic lobes, which are anchored by
#' very few cognate pairs, and bridging on to a further template brain adds that
#' registration's error on top. Treat the result as an informative prior on
#' where a neuron sits, not as ground truth.
#'
#' @param x An object to transform: anything accepted by [nat::xform()],
#'   including neurons, neuronlists, dotprops, meshes and coordinate matrices.
#' @param sample,reference Source and target space. Exactly one must be
#'   `"aedes"`. The other may be `"FlyWire"` (equivalently `"FAFB14.1"`) or any
#'   template brain reachable by [nat.templatebrains::xform_brain()].
#' @param units Units of the EM data, both incoming and returned — that is, of
#'   the Aedes end, and of the FlyWire end when FlyWire is the other space.
#'   Template brains such as JRC2018F are always in their own native units
#'   (microns), whatever `units` says, because that is what they are defined in.
#' @param subset Optional subset passed to [nat::xform()], for example to
#'   transform selected elements of a neuronlist.
#' @param via Optional intermediate space(s) passed to
#'   [nat.templatebrains::xform_brain()] when bridging beyond FlyWire.
#' @param ... Additional arguments passed to [nat::xform()].
#'
#' @return A transformed object of the same kind as `x`.
#' @seealso [aedes_mirror()] for mirroring within Aedes space;
#'   [nat.templatebrains::xform_brain()] for transforms among fly spaces.
#' @export
#'
#' @examples
#' \dontrun{
#' # A neuron in Aedes space, placed in the fly EM brain
#' sk <- read_aedes_neurons(aedes_ids("class:KC")[1], units = "nm")
#' sk.fly <- xform_aedes(sk, sample = "aedes", reference = "FlyWire")
#'
#' # Neither side is Aedes, so this is an error
#' xform_aedes(sk, sample = "FlyWire", reference = "JRC2018F")
#'
#' # LPsP is a central complex cell type identified in all three datasets, so
#' # it can be compared across two species in one space. Each dataset is
#' # fetched in its own coordinates and brought to JRC2018F: Aedes with this
#' # function, the two fly datasets with xform_brain().
#'
#' # Aedes -- LPsP is annotated in the `flywire_type` column
#' aed <- read_aedes_neurons(aedes_ids("flywire_type:LPsP"), units = "nm")
#' aed.jrc <- xform_aedes(aed, sample = "aedes", reference = "JRC2018F")
#'
#' # FlyWire -- read_l2skel() returns nm, and the bridge is defined in microns
#' fw <- fafbseg::read_l2skel(fafbseg::flywire_ids("type:LPsP"))
#' fw.jrc <- nat.templatebrains::xform_brain(
#'   fw / 1e3, sample = "FLYWIRE", reference = "JRC2018F"
#' )
#'
#' # hemibrain -- neuPrint returns raw 8 nm voxels, JRCFIB2018F is in microns
#' hb <- neuprintr::neuprint_read_neurons(
#'   neuprintr::neuprint_search("LPsP", field = "type")$bodyid
#' )
#' hb.jrc <- nat.templatebrains::xform_brain(
#'   hb * 8 / 1e3, sample = "JRCFIB2018F", reference = "JRC2018F"
#' )
#'
#' # all three in one plot, a colour per dataset
#' library(nat.ggplot)
#' gganat +
#'   geom_neuron(aed.jrc, cols = c("darkorange", "gold")) +
#'   geom_neuron(fw.jrc, cols = c("navy", "turquoise")) +
#'   geom_neuron(hb.jrc, cols = c("darkred", "salmon"))
#' }
xform_aedes <- function(x,
                        sample,
                        reference,
                        units = c("nm", "microns"),
                        subset = NULL,
                        via = NULL,
                        ...) {
  units <- match.arg(units)
  sample <- as.character(sample)
  reference <- as.character(reference)
  stopifnot(length(sample) == 1L, length(reference) == 1L)

  # This function only knows how to cross the Aedes/Drosophila gap, so one end
  # must be Aedes. Transforms between two fly spaces are xform_brain()'s job.
  if (.is_aedes_space(sample) == .is_aedes_space(reference)) {
    stop(
      "One of `sample` and `reference` must be \"aedes\", and the other a fly ",
      "space.\n  Got sample = \"", sample, "\", reference = \"", reference, "\".",
      if (.is_aedes_space(sample)) {
        "\n  Both are Aedes: to move within Aedes space see `aedes_mirror()`."
      } else {
        "\n  Neither is Aedes: to move between two fly spaces see `nat.templatebrains::xform_brain()`."
      },
      call. = FALSE
    )
  }
  check_package_available("Morpho")

  from_aedes <- .is_aedes_space(sample)
  fly <- if (from_aedes) reference else sample
  # FlyWire is the space our own registration lands in, so it needs no bridge;
  # everything else is handed to xform_brain() with FlyWire as the entry point.
  direct <- .is_flywire_space(fly)
  if (!direct) check_package_available("nat.templatebrains")

  if (from_aedes) {
    # nm -> microns: both the bundled registration and the natverse FlyWire
    # bridge are defined in microns (nm input silently falls outside it).
    x_um <- if (units == "nm") x / 1e3 else x
    fw <- nat::xform(x_um, reg = .aedes_flywire_reg("flywire"), subset = subset, ...)
    if (direct) {
      return(if (units == "nm") fw * 1e3 else fw)
    }
    # leaving EM space: the target template brain defines its own units, so we
    # hand over microns and do NOT convert the result back.
    .bridge(fw, sample = "FLYWIRE", reference = fly, via = via)
  } else {
    fw <- if (direct) {
      if (units == "nm") x / 1e3 else x
    } else {
      .bridge(x, sample = fly, reference = "FLYWIRE", via = via)
    }
    aed <- nat::xform(fw, reg = .aedes_flywire_reg("aedes"), subset = subset, ...)
    if (units == "nm") aed * 1e3 else aed
  }
}

.is_aedes_space <- function(x) tolower(x) %in% c("aedes", "aedes_aegypti", "aedesf")

# Hand over to the natverse bridging graph, with FlyWire as the entry point.
#
# Bridging registrations ship in separate packages and only add themselves to
# the graph when their namespace loads, so a user who has not attached
# nat.jrcbrains gets "No path between FLYWIRE and FCWB" even though the
# registration is sitting on their disk. Load whatever is installed first --
# requireNamespace() is enough, the packages need not be attached -- and if
# there is still no path, say what actually governs that rather than repeating
# xform_brain()'s terse message.
.bridge <- function(x, sample, reference, via = NULL) {
  for (p in c("nat.flybrains", "nat.jrcbrains", "elmr")) {
    requireNamespace(p, quietly = TRUE)
  }
  tryCatch(
    nat.templatebrains::xform_brain(
      x,
      sample = sample, reference = reference, via = via
    ),
    error = function(e) {
      if (!grepl("No path", conditionMessage(e))) stop(e)
      stop(
        "No registration path between \"", sample, "\" and \"", reference, "\".\n",
        "  Which fly spaces are reachable depends on the bridging registrations ",
        "installed;\n  see nat.templatebrains::bridging_graph(). Between them ",
        "nat.flybrains,\n  nat.jrcbrains and elmr cover JRC2018F, JRCFIB2018F ",
        "(hemibrain), JFRC2,\n  JFRC2013, JRC2018U and FCWB.",
        call. = FALSE
      )
    }
  )
}

# FlyWire is FAFB v14.1. FAFB14 proper is a slightly different space and is left
# to the bridging graph rather than being silently treated as the same thing.
.is_flywire_space <- function(x) {
  tolower(x) %in% c("flywire", "flywire31", "fafb14.1", "fafb141")
}

# The bundled registrations carry PRECOMPUTED spline coefficients, but
# nat::xform() ignores those and re-solves the dense system from refmat/tarmat
# on every call -- 74 s vs 0.29 s for 2000 points here. Handing nat::xform() a
# function instead keeps its generic handling of neurons, neuronlists and meshes
# while going through Morpho::applyTransform(), which does use the coefficients.
.aedes_flywire_reg <- memoise::memoise(function(to = c("flywire", "aedes")) {
  to <- match.arg(to)
  f <- if (to == "flywire") {
    "aedes_flywire_3000_tps.rds"
  } else {
    "flywire_aedes_3000_tps.rds"
  }
  cf <- readRDS(system.file("extdata", f, package = "aedes", mustWork = TRUE))
  function(xyz, ...) Morpho::applyTransform(xyz, cf)
})
