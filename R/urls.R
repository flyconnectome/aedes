#' @noRd
aedes_scene <- function() {
  u = "https://spelunker.cave-explorer.org/#!middleauth+https://global.daf-apis.com/nglstate/api/v1/6213916184018944"
  # TODO: use exported fafbseg::flywire_expandurl when available
  u2 = fafbseg:::flywire_expandurl(u)
  u2
}

#' Choose or temporarily use the Aedes autosegmentation
#'
#' @param set Whether to set Aedes as default for `fafbseg` flywire functions.
#' @param url Neuroglancer scene URL. Defaults to `aedes_scene()`.
#' @param datastack_name Optional CAVE datastack name; inferred from `url` if `NULL`.
#' @return A named list of option values (or previous options when `set=TRUE`).
#' @export
choose_aedes <- function(set = TRUE, url = NULL, datastack_name = NULL) {
  if (is.null(url))
    url <- aedes_scene()

  if (is.null(datastack_name)) {
    sc <- fafbseg::ngl_decode_scene(url)
    ll <- fafbseg::ngl_layers(sc, type == "segmentation")
    datastack_name <- basename(ll[[1]]$source$url)
  }

  fafbseg::choose_segmentation(
    url,
    set = set,
    moreoptions = list(fafbseg.cave.datastack_name = datastack_name)
  )
}

#' @param expr Expression to evaluate while Aedes is the active dataset.
#' @rdname choose_aedes
#' @export
with_aedes <- function(expr, url = NULL, datastack_name = NULL) {
  op <- choose_aedes(set = TRUE, url = url, datastack_name = datastack_name)
  on.exit(options(op))
  force(expr)
}
