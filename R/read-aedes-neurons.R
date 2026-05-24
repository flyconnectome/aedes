
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
#' @param nuclei How to handle root ids with more than one *distinct-position*
#'   nucleus in the nucleus segmentation. `"largest"` (the default) returns
#'   one row per input id, picking the nucleus with the largest `volume` (or
#'   the first row when no `volume` column is available). `"all"` returns
#'   every candidate row, so an ambiguous root id contributes more than one
#'   row. Either way, bookkeeping duplicates (rows with identical position
#'   for the same root id) are silently collapsed, and `n_nuclei` records how
#'   many distinct-position candidates were considered.
#' @param version,timestamp Optional CAVE materialisation selectors passed
#'   through to [aedes_meta()] and [fafbseg::flywire_nuclei()].
#'
#' @return A data.frame with columns `root_id`; `position` (a `"x,y,z"` string
#'   in the requested `units`; convert back with [nat::xyzmatrix()]); `source`
#'   (`"flytable"`, `"nucleus"`, or `NA`); `n_nuclei` (the number of
#'   distinct-position nucleus candidates for that root id, or `NA` when the
#'   soma came from FlyTable / was not found); and `nucleus_id` (the
#'   `nuclei_v1_aedes` primary key of the chosen row, or `NA` for FlyTable /
#'   not-found sources). With `nuclei = "largest"` there is one row per input
#'   id in input order; with `nuclei = "all"` rows are ordered by input id
#'   but ambiguous ids contribute multiple rows (sorted by descending volume).
#' @seealso [read_aedes_neurons()]
#' @export
#' @examples
#' \dontrun{
#' aedes_soma_position("class:DNa")
#' aedes_soma_position("class:DNa", units = "raw")
#' aedes_soma_position("648518347517945383", nuclei = "all")
#' aedes_soma_position(c("648518347528739642", "648518347497973071"),
#'                     method = "flytable")
#' }
aedes_soma_position <- function(ids,
                                method = c("auto", "flytable", "nucleus"),
                                units = c("nm", "raw"),
                                nuclei = c("largest", "all"),
                                version = NULL,
                                timestamp = NULL) {
  method <- match.arg(method)
  units  <- match.arg(units)
  nuclei <- match.arg(nuclei)
  vi <- aedes_get_version(version = version, timestamp = timestamp)
  root_ids <- as.character(aedes_ids(ids, version = vi$version,
                                     timestamp = vi$timestamp))

  empty_row <- function(ids) {
    data.frame(
      root_id    = ids,
      position   = NA_character_,
      source     = NA_character_,
      n_nuclei   = NA_integer_,
      nucleus_id = NA_integer_,
      stringsAsFactors = FALSE
    )
  }

  # FlyTable soma_xyz (raw voxel coords) -> nm position string -------------
  flytable_rows <- NULL
  if (method %in% c("auto", "flytable")) {
    meta <- aedes_meta(root_ids, version = vi$version,
                       timestamp = vi$timestamp, unique = TRUE)
    if (!is.null(meta) && "soma_xyz" %in% colnames(meta)) {
      idx <- match(root_ids, as.character(meta$root_id))
      raw <- meta$soma_xyz[idx]
      ok  <- !is.na(raw) & nzchar(raw)
      if (any(ok)) {
        xyz <- aedes_raw2nm(nat::xyzmatrix(raw[ok]))
        good <- stats::complete.cases(xyz)
        rows <- which(ok)[good]
        flytable_rows <- data.frame(
          root_id    = root_ids[rows],
          position   = nat::xyzmatrix2str(xyz[good, , drop = FALSE]),
          source     = "flytable",
          n_nuclei   = NA_integer_,
          nucleus_id = NA_integer_,
          stringsAsFactors = FALSE
        )
      }
    }
  }
  flytable_ids <- if (!is.null(flytable_rows)) flytable_rows$root_id
                  else character(0)

  # flywire_nuclei (positions already in nm) -------------------------------
  need_ids <- setdiff(root_ids, flytable_ids)
  nucleus_rows <- NULL
  if (method %in% c("auto", "nucleus") && length(need_ids)) {
    nuc <- tryCatch(
      with_aedes(fafbseg::flywire_nuclei(
        rootids = need_ids, rawcoords = FALSE,
        version = vi$version, timestamp = vi$timestamp
      )),
      error = function(e) {
        warning("flywire_nuclei() failed: ", conditionMessage(e), call. = FALSE)
        NULL
      }
    )
    if (!is.null(nuc) && nrow(nuc)) {
      nucleus_rows <- .aedes_dedup_nuclei(nuc, nuclei = nuclei)
      if (!is.null(nucleus_rows))
        nucleus_rows <- nucleus_rows[nucleus_rows$root_id %in% need_ids, ,
                                     drop = FALSE]
    }
  }

  found_ids <- c(flytable_ids,
                 if (!is.null(nucleus_rows)) unique(nucleus_rows$root_id)
                 else character(0))
  missing_ids <- setdiff(root_ids, found_ids)
  missing_rows <- if (length(missing_ids)) empty_row(missing_ids) else NULL

  out <- do.call(rbind, Filter(Negate(is.null),
                               list(flytable_rows, nucleus_rows, missing_rows)))

  # Order to match input. nuclei = "largest" gives one row per input id;
  # nuclei = "all" may give several -- sort by input order, candidate order
  # within an id is already largest-first.
  out$.ord <- match(out$root_id, root_ids)
  out <- out[order(out$.ord, seq_len(nrow(out))), ]
  out$.ord <- NULL
  rownames(out) <- NULL

  # units conversion (parse -> scale -> stringify) ------------------------
  if (identical(units, "raw")) {
    has_pos <- !is.na(out$position)
    if (any(has_pos))
      out$position[has_pos] <- nat::xyzmatrix2str(
        aedes_nm2raw(nat::xyzmatrix(out$position[has_pos]))
      )
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
#'   `data` slot gains `soma_source` (`"flytable"`, `"nucleus"`, `"mesh"`, or
#'   `NA`), `n_nuclei` (count of distinct-position nucleus candidates
#'   considered, or `NA`), and `nucleus_id` (the `nuclei_v1_aedes` primary key
#'   of the chosen row, or `NA`). `n_nuclei > 1` indicates the chosen nucleus
#'   was one of several at distinct positions for that root id; see
#'   [aedes_soma_position()] for the full candidate list.
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

    sources    <- rep(NA_character_, length(res))
    n_nuclei   <- rep(NA_integer_,   length(res))
    nucleus_id <- rep(NA_integer_,   length(res))
    for (i in seq_along(res)) {
      j <- match(names(res)[i], soma$root_id)
      pt <- if (!is.na(j) && !is.na(soma$position[j]))
              as.numeric(nat::xyzmatrix(soma$position[j])[1, ])
            else c(NA, NA, NA)
      src <- if (!is.na(j)) soma$source[j] else NA_character_
      have_point <- all(is.finite(pt))

      if (have_point) {
        res[[i]] <- aedes_root_point(res[[i]], point = pt,
                                     method = "point", rval = "neuron")
        sources[i]    <- src
        n_nuclei[i]   <- if (!is.na(j)) soma$n_nuclei[j]   else NA_integer_
        nucleus_id[i] <- if (!is.na(j)) soma$nucleus_id[j] else NA_integer_
      } else if (mesh_active) {
        res[[i]] <- aedes_root_point(res[[i]], mesh = mesh,
                                     method = "mesh", rval = "neuron")
        sources[i] <- "mesh"
      } # else: leave the neuron untouched
    }

    # 3. attach per-neuron provenance so it survives subsetting
    md <- res[, , drop = FALSE]
    ord <- match(rownames(md), names(res))
    md$soma_source <- sources[ord]
    md$n_nuclei    <- n_nuclei[ord]
    md$nucleus_id  <- nucleus_id[ord]
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


# Reduce a `flywire_nuclei()` result to one (`nuclei = "largest"`) or all
# (`nuclei = "all"`) candidate row(s) per root_id. The `position` column is
# stringified via [nat::xyzmatrix2str()] in nm coordinates and is also used
# to dedup bookkeeping duplicates (rows with identical position for the same
# root_id, e.g. 648518347517945383). Errors if any of the required columns
# are missing from the input.
.aedes_dedup_nuclei <- function(nuc, nuclei = c("largest", "all")) {
  nuclei <- match.arg(nuclei)
  required <- c("id", "pt_root_id", "pt_position", "volume")
  missing  <- setdiff(required, colnames(nuc))
  if (length(missing))
    stop("flywire_nuclei() result missing required column(s): ",
         paste(missing, collapse = ", "), call. = FALSE)
  if (!nrow(nuc)) return(NULL)

  picked <- nuc %>%
    mutate(
      root_id    = as.character(.data$pt_root_id),
      position   = nat::xyzmatrix2str(.data$pt_position),
      nucleus_id = as.integer(.data$id),
      source     = "nucleus"
    ) %>%
    filter(!is.na(.data$position) & !is.na(.data$root_id)) %>%
    arrange(.data$root_id, desc(.data$volume)) %>%
    distinct(.data$root_id, .data$position, .keep_all = TRUE) %>%
    add_count(.data$root_id, name = "n_nuclei") %>%
    select("root_id", "position", "source", "n_nuclei", "nucleus_id")

  if (!nrow(picked)) return(NULL)
  if (nuclei == "largest")
    picked <- distinct(picked, .data$root_id, .keep_all = TRUE)
  as.data.frame(picked)
}
