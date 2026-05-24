
# ---------------------------------------------------------------------------
# Level 1: soma position lookup
# ---------------------------------------------------------------------------

#' Look up the soma position for one or more Aedes neurons
#'
#' Returns the recorded soma position (in nm) for each input root id, using
#' FlyTable annotations and/or the FlyWire nucleus segmentation.
#'
#' @param ids Root IDs or a FlyTable query string accepted by [aedes_ids()].
#' @param method One of `"auto"`, `"flytable"`, `"nucleus"`. With `"auto"`
#'   (the default) the function first tries FlyTable's `soma_xyz` and then
#'   falls back to [fafbseg::flywire_nuclei()] for any neuron that lacked a
#'   recorded soma. Naming a single method restricts the lookup to that source.
#' @param units Units of the returned coordinates: `"nm"` (default) or `"raw"`
#'   voxel coordinates. FlyTable's `soma_xyz` is always stored as raw voxel
#'   coordinates and is converted to nm via [aedes_raw2nm()] before being
#'   returned (unless `units = "raw"`).
#' @param version,timestamp Optional CAVE materialisation selectors passed
#'   through to [aedes_meta()] and [fafbseg::flywire_nuclei()].
#'
#' @return A data.frame with one row per input id (in the same order), with
#'   columns `root_id`, `x`, `y`, `z` (in the requested `units`), and `source`
#'   (`"flytable"`, `"nucleus"`, or `NA`).
#' @seealso [read_aedes_neurons()]
#' @export
#' @examples
#' \dontrun{
#' aedes_soma_position("class:DNa")
#' aedes_soma_position("class:DNa", units = "raw")
#' aedes_soma_position(c("648518347528739642", "648518347497973071"),
#'                     method = "flytable")
#' }
aedes_soma_position <- function(ids,
                                method = c("auto", "flytable", "nucleus"),
                                units = c("nm", "raw"),
                                version = NULL,
                                timestamp = NULL) {
  method <- match.arg(method)
  units  <- match.arg(units)
  vi <- aedes_get_version(version = version, timestamp = timestamp)
  root_ids <- as.character(aedes_ids(ids, version = vi$version,
                                     timestamp = vi$timestamp))

  out <- data.frame(
    root_id = root_ids,
    x = NA_real_, y = NA_real_, z = NA_real_,
    source = NA_character_,
    stringsAsFactors = FALSE
  )

  # FlyTable soma_xyz ------------------------------------------------------
  if (method %in% c("auto", "flytable")) {
    meta <- aedes_meta(root_ids, version = vi$version,
                       timestamp = vi$timestamp, unique = TRUE)
    if (!is.null(meta) && "soma_xyz" %in% colnames(meta)) {
      idx <- match(root_ids, as.character(meta$root_id))
      raw <- meta$soma_xyz[idx]
      ok  <- !is.na(raw) & nzchar(raw)
      if (any(ok)) {
        xyz <- suppressWarnings(nat::xyzmatrix(raw[ok]))
        storage.mode(xyz) <- "numeric"
        xyz <- aedes_raw2nm(xyz)              # FlyTable soma_xyz is raw
        good <- stats::complete.cases(xyz)
        rows <- which(ok)[good]
        out[rows, c("x", "y", "z")] <- xyz[good, , drop = FALSE]
        out$source[rows] <- "flytable"
      }
    }
  }

  # flywire_nuclei fallback -----------------------------------------------
  need <- is.na(out$source)
  if (method %in% c("auto", "nucleus") && any(need)) {
    nuc <- tryCatch(
      with_aedes(fafbseg::flywire_nuclei(
        rootids = out$root_id[need], rawcoords = FALSE,
        version = vi$version, timestamp = vi$timestamp
      )),
      error = function(e) {
        warning("flywire_nuclei() failed: ", conditionMessage(e), call. = FALSE)
        NULL
      }
    )
    if (!is.null(nuc) && nrow(nuc)) {
      picked <- .aedes_dedup_nuclei(nuc)
      if (!is.null(picked)) {
        idx <- match(out$root_id, picked$root_id)
        hit <- need & !is.na(idx)
        if (any(hit)) {
          out[hit, c("x", "y", "z")] <- picked[idx[hit], c("x", "y", "z"),
                                               drop = FALSE]
          out$source[hit] <- "nucleus"
        }
      }
    }
  }

  # convert to raw if requested -------------------------------------------
  if (identical(units, "raw")) {
    has_xyz <- !is.na(out$source)
    if (any(has_xyz)) {
      raw <- aedes_nm2raw(as.matrix(out[has_xyz, c("x", "y", "z"), drop = FALSE]))
      out[has_xyz, c("x", "y", "z")] <- raw
    }
  }

  out
}


# ---------------------------------------------------------------------------
# Level 2: pick a root point on a skeleton
# ---------------------------------------------------------------------------

# Find the index of the chosen root vertex for a single neuron.
#
# `point`   xyz of a target location (nm); the nearest skeleton node is used.
# `mesh`    a `mesh3d` of the neuropil; the endpoint with the smallest signed
#           distance (most outside the neuropil) is used.
# `method`  "auto" tries `point` first, then `mesh`; "point" or "mesh" force one.
# `offset`  threshold added to the signed distance before scoring; see
#           `segment_exterior_score()` / `find_root_l2skel()` in 2025aedes.
# Returns either the chosen index, the xyz of that node, or a rerooted neuron.
#' @noRd
aedes_root_point <- function(x, point = NULL,
                             method = c("auto", "point", "mesh"),
                             mesh = NULL, offset = 0,
                             rval = c("idx", "point", "neuron")) {
  method <- match.arg(method)
  rval   <- match.arg(rval)
  if (nat::is.neuronlist(x))
    stop("`aedes_root_point()` operates on a single neuron; use ",
         "`read_aedes_neurons()` or iterate yourself.", call. = FALSE)
  if (!nat::is.neuron(x))
    stop("`x` must be a `neuron`.", call. = FALSE)

  use_point <- !is.null(point) && all(is.finite(point)) &&
    method %in% c("auto", "point")
  use_mesh  <- !is.null(mesh) && method %in% c("auto", "mesh") &&
    (!use_point || method == "mesh")

  idx <- NA_integer_
  if (use_point) {
    xyz <- nat::xyzmatrix(x)
    d2  <- (xyz[, 1] - point[[1]])^2 +
           (xyz[, 2] - point[[2]])^2 +
           (xyz[, 3] - point[[3]])^2
    idx <- which.min(d2)
  } else if (use_mesh) {
    eps  <- nat::endpoints(x)
    xyz  <- nat::xyzmatrix(x)[eps, , drop = FALSE]
    dist <- nat::pointsinside(xyz, surf = mesh, rval = "dist") + offset
    idx  <- eps[which.min(dist)]   # most negative = furthest outside neuropil
  } else if (method == "auto" && is.null(mesh)) {
    return(switch(rval, idx = NA_integer_, point = rep(NA_real_, 3), neuron = x))
  } else {
    stop("no usable root source for method='", method, "'", call. = FALSE)
  }

  switch(rval,
         idx = idx,
         point = nat::xyzmatrix(x)[idx, ],
         neuron = nat::reroot(x, idx = idx))
}


# ---------------------------------------------------------------------------
# Level 3: read + (optionally) reroot
# ---------------------------------------------------------------------------

#' Read Aedes L2 skeletons
#'
#' Thin Aedes-aware wrapper around [fafbseg::read_l2skel()]. Optionally reroots
#' each skeleton to its soma, cascading through a configurable set of methods.
#'
#' @param ids Root IDs or a FlyTable query string compatible with [aedes_ids()].
#' @param units Units of the returned skeletons (default `"nm"`).
#' @param reroot Whether to reroot the returned neurons.
#' @param method Reroot strategy. With `"auto"` (the default) each neuron is
#'   handled by the first source that succeeds: FlyTable `soma_xyz` →
#'   FlyWire nucleus → neuropil mesh. Restricting to a single source disables
#'   the cascade. Use `"none"` to read without rerooting (equivalent to
#'   `reroot = FALSE`).
#' @param mesh A `mesh3d` for the neuropil. Defaults to the
#'   packaged [aedes_neuropil_mesh]. Pass `NULL` to disable the mesh fallback.
#' @param OmitFailures Passed to [fafbseg::read_l2skel()].
#' @param version,timestamp Optional CAVE materialisation selectors.
#' @param ... Additional arguments passed to [fafbseg::read_l2skel()].
#'
#' @return A [nat::neuronlist()] of L2 skeletons. When rerooted, each neuron's
#'   `data` slot gains a `soma_source` column (one of `"flytable"`,
#'   `"nucleus"`, `"mesh"`, or `NA`).
#' @seealso [aedes_soma_position()], [aedes_neuropil_mesh]
#' @export
#' @examples
#' \dontrun{
#' dns <- read_aedes_neurons("class:DNa")
#' dns <- read_aedes_neurons("class:DNa", method = "flytable") # no fallback
#' dns <- read_aedes_neurons("class:DNa", reroot = FALSE)
#' }
read_aedes_neurons <- function(ids,
                               units = c("nm", "raw", "microns"),
                               reroot = TRUE,
                               method = c("auto", "flytable", "nucleus",
                                          "mesh", "none"),
                               mesh = aedes::aedes_neuropil_mesh,
                               OmitFailures = TRUE,
                               version = NULL,
                               timestamp = NULL,
                               ...) {
  units  <- match.arg(units)
  method <- match.arg(method)
  if (identical(method, "none")) reroot <- FALSE

  vi <- aedes_get_version(version = version, timestamp = timestamp)
  root_ids <- as.character(aedes_ids(ids, version = vi$version,
                                     timestamp = vi$timestamp))

  res <- with_aedes(fafbseg::read_l2skel(
    root_ids, OmitFailures = OmitFailures, ...
  ))

  if (isTRUE(reroot) && length(res)) {
    # 1. resolve point-based sources (flytable / nucleus) up front
    point_method <- switch(method,
                           flytable = "flytable",
                           nucleus  = "nucleus",
                           mesh     = NULL,
                           "auto")
    if (!is.null(point_method)) {
      soma <- aedes_soma_position(
        names(res), method = point_method,
        version = vi$version, timestamp = vi$timestamp
      )
    } else {
      soma <- data.frame(root_id = names(res),
                         x = NA_real_, y = NA_real_, z = NA_real_,
                         source = NA_character_, stringsAsFactors = FALSE)
    }

    # 2. decide whether mesh fallback is in play
    mesh_active <- !is.null(mesh) && method %in% c("auto", "mesh")

    sources <- rep(NA_character_, length(res))
    for (i in seq_along(res)) {
      j <- match(names(res)[i], soma$root_id)
      pt <- if (!is.na(j)) unlist(soma[j, c("x", "y", "z")]) else c(NA, NA, NA)
      src <- if (!is.na(j)) soma$source[j] else NA_character_
      have_point <- all(is.finite(pt))

      if (have_point) {
        res[[i]] <- aedes_root_point(res[[i]], point = pt,
                                     method = "point", rval = "neuron")
        sources[i] <- src
      } else if (mesh_active) {
        res[[i]] <- aedes_root_point(res[[i]], mesh = mesh,
                                     method = "mesh", rval = "neuron")
        sources[i] <- "mesh"
      } # else: leave the neuron untouched
    }

    # 3. attach per-neuron soma_source so it survives subsetting
    md <- res[, , drop = FALSE]
    md$soma_source <- sources[match(rownames(md), names(res))]
    res[, ] <- md

    if (anyNA(sources))
      warning(sum(is.na(sources)), " of ", length(sources),
              " neurons could not be rerooted; soma_source is NA for those.",
              call. = FALSE)
  }

  switch(units,
         nm = res,
         raw = res * c(1 / aedes_voxdims(), 1),
         microns = res / 1000)
}


# Collapse a `flywire_nuclei()` result to one row per root_id. When a root_id
# has >1 nucleus, picks the largest by `volume` if that column is present, or
# the first row otherwise. Always warns if any duplicates were found.
#
# Returns a data.frame(root_id, x, y, z) in nm, or NULL if the input lacks the
# expected columns / has no valid rows.
#' @noRd
.aedes_dedup_nuclei <- function(nuc) {
  pos_col  <- grep("position$", colnames(nuc), value = TRUE)[1]
  root_col <- intersect(c("pt_root_id", "root_id"), colnames(nuc))[1]
  if (is.na(pos_col) || is.na(root_col)) return(NULL)

  nuc_ids <- as.character(nuc[[root_col]])
  nuc_xyz <- suppressWarnings(nat::xyzmatrix(nuc[[pos_col]]))
  storage.mode(nuc_xyz) <- "numeric"
  valid <- stats::complete.cases(nuc_xyz)
  if (!any(valid)) return(NULL)
  nuc_ids <- nuc_ids[valid]
  nuc_xyz <- nuc_xyz[valid, , drop = FALSE]
  vol <- if ("volume" %in% colnames(nuc)) nuc[["volume"]][valid] else NULL

  # Order by root_id then descending volume so the largest-volume nucleus per
  # root_id comes first.
  ord <- if (!is.null(vol)) order(nuc_ids, -vol) else seq_along(nuc_ids)
  nuc_ids <- nuc_ids[ord]
  nuc_xyz <- nuc_xyz[ord, , drop = FALSE]

  # Silently collapse rows that share the same (root_id, x, y, z): these are
  # bookkeeping duplicates of the same nucleus, not a real choice to make.
  pos_keys <- paste(nuc_ids, nuc_xyz[, 1], nuc_xyz[, 2], nuc_xyz[, 3], sep = "|")
  pos_dups <- duplicated(pos_keys)
  nuc_ids <- nuc_ids[!pos_dups]
  nuc_xyz <- nuc_xyz[!pos_dups, , drop = FALSE]

  # Only warn for genuine duplicates: same root_id, different positions.
  dup_ids <- unique(nuc_ids[duplicated(nuc_ids)])
  if (length(dup_ids)) {
    warning(length(dup_ids), " root id(s) have >1 nucleus at distinct ",
            "positions; ",
            if (!is.null(vol)) "picking the largest by volume: "
            else "picking the first match: ",
            paste(utils::head(dup_ids, 5), collapse = ", "),
            if (length(dup_ids) > 5) ", ...",
            call. = FALSE)
  }

  keep <- !duplicated(nuc_ids)
  data.frame(root_id = nuc_ids[keep],
             x = nuc_xyz[keep, 1],
             y = nuc_xyz[keep, 2],
             z = nuc_xyz[keep, 3],
             stringsAsFactors = FALSE)
}
