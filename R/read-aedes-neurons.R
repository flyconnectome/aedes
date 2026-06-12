
# ---------------------------------------------------------------------------
# Level 1: soma position lookup
# ---------------------------------------------------------------------------

#' Look up the soma position for one or more Aedes neurons
#'
#' Returns the recorded soma position (in nm) for each input root id, using
#' FlyTable annotations and/or the FlyWire nucleus segmentation.
#'
#' @param ids Root IDs or a FlyTable query string accepted by [aedes_ids()].
#' @param method One of `"auto"`, `"flytable"`, `"nucleus"`, `"l2+mesh"`,
#'   `"l2"`, or `"mesh"`. With `"auto"` (the default) the function tries
#'   FlyTable's `soma_xyz` first, falls back to [fafbseg::flywire_nuclei()]
#'   for any neuron without a recorded soma, and -- when a `mesh` is
#'   available -- finally falls back to a combined L2-attribute + neuropil
#'   signed-distance score (`"l2+mesh"`). Restricting `method` skips the
#'   cascade. `"l2"` uses only the L2 shape features (area, distance
#'   transform, roundness, size); `"mesh"` uses only the signed distance and
#'   errors if `mesh = NULL`.
#' @param mesh A `mesh3d` of the neuropil for the mesh-based scoring methods.
#'   Defaults to [aedes_neuropil_mesh]. Pass `NULL` to disable mesh-based
#'   fallback in `"auto"`.
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
#' @param chunksize Number of neurons per batched L2-attribute fetch when the
#'   cascade reaches `"l2+mesh"` / `"l2"` / `"mesh"`. Larger values reduce CAVE
#'   round-trip overhead at the cost of larger responses. Default 20 trades
#'   off well in practice; pass `1L` to revert to per-neuron fetches.
#' @param cl Optional parallel cluster (or integer worker count) passed to
#'   [pbapply::pblapply()] for chunk processing. `NULL` (default) runs
#'   sequentially with a progress bar. Useful when scoring hundreds to
#'   thousands of neurons via L2.
#' @param version,timestamp Optional CAVE materialisation selectors passed
#'   through to [aedes_meta()] and [fafbseg::flywire_nuclei()]. Defaults to
#'   timestamp='now' if no user supplied selector.
#'
#' @return A data.frame with columns `root_id`; `position` (a `"x,y,z"` string
#'   in the requested `units`; convert back with [nat::xyzmatrix()]); `source`
#'   (`"flytable"`, `"nucleus"`, `"l2+mesh"`, `"l2"`, `"mesh"`, or `NA`);
#'   `n_nuclei` (the number of distinct-position nucleus candidates for that
#'   root id, or `NA` when the soma came from elsewhere / was not found); and
#'   `nucleus_id` (the `nuclei_v1_aedes` primary key, from FlyTable when
#'   `source = "flytable"` or from the chosen nucleus row when
#'   `source = "nucleus"`). L2-derived rows also include
#'   `soma_score` (absolute, cross-neuron-comparable; squared Mahalanobis
#'   distance of the chunk's shape features from the KC positive cloud, plus
#'   a KDE-based penalty on signed neuropil distance --
#'   *lower = more soma-like*; see [aedes_soma_l2_stats]),
#'   `dist_npil_nm` (signed distance to the neuropil mesh, in nm; positive
#'   inside, negative outside -- soma rows are in cortex so this is usually
#'   negative), and `l2_id` (the selected L2 chunk).
#'   These columns are `NA` for non-L2 sources. With `nuclei = "largest"`
#'   there is one row per input id in input order; with `nuclei = "all"` rows
#'   are ordered by input id but ambiguous ids contribute multiple rows
#'   (sorted by descending volume).
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
                                method = c("auto", "flytable", "nucleus",
                                           "l2+mesh", "l2", "mesh"),
                                units = c("nm", "raw"),
                                nuclei = c("largest", "all"),
                                mesh = aedes::aedes_neuropil_mesh,
                                chunksize = 20L,
                                cl = NULL,
                                version = NULL,
                                timestamp = NULL) {
  method <- match.arg(method)
  units  <- match.arg(units)
  nuclei <- match.arg(nuclei)
  if (method %in% c("l2+mesh", "mesh") && is.null(mesh))
    stop("method = \"", method, "\" requires a non-NULL `mesh`.", call. = FALSE)
  vi <- aedes_get_version(which = 'now', version = version, timestamp = timestamp)

  # Accept a pre-fetched metadata data.frame (with root_id, ideally soma_xyz
  # too). Saves the flytable branch a redundant aedes_meta() call when the
  # caller -- typically aedes_soma_side() -- already has the frame in hand.
  if (is.data.frame(ids)) {
    if (!"root_id" %in% colnames(ids))
      stop("data.frame input must contain a `root_id` column.", call. = FALSE)
    root_ids <- as.character(ids$root_id)
    meta_in  <- ids
  } else {
    root_ids <- as.character(aedes_ids(ids, version = vi$version,
                                       timestamp = vi$timestamp))
    meta_in  <- NULL
  }

  empty_row <- function(ids) {
    data.frame(
      root_id    = ids,
      position   = NA_character_,
      source     = NA_character_,
      n_nuclei   = NA_integer_,
      nucleus_id = NA_integer_,
      soma_score = NA_real_,
      dist_npil_nm = NA_real_,
      l2_id = NA_character_,
      stringsAsFactors = FALSE
    )
  }

  # FlyTable soma_xyz (raw voxel coords) -> nm position string -------------
  flytable_rows <- NULL
  if (method %in% c("auto", "flytable")) {
    meta <- if (!is.null(meta_in)) meta_in
            else aedes_meta(root_ids, version = vi$version,
                            timestamp = vi$timestamp, unique = TRUE)
    if (!is.null(meta) && "soma_xyz" %in% colnames(meta)) {
      idx <- match(root_ids, as.character(meta$root_id))
      raw <- meta$soma_xyz[idx]
      ok  <- !is.na(raw) & nzchar(raw)
      if (any(ok)) {
        xyz <- aedes_raw2nm(nat::xyzmatrix(raw[ok]))
        good <- stats::complete.cases(xyz)
        rows <- which(ok)[good]
        nucleus_id <- if ("nucleus_id" %in% colnames(meta))
          as.integer(meta$nucleus_id[idx][rows])
        else
          rep(NA_integer_, length(rows))
        flytable_rows <- data.frame(
          root_id    = root_ids[rows],
          position   = nat::xyzmatrix2str(xyz[good, , drop = FALSE]),
          source     = "flytable",
          n_nuclei   = NA_integer_,
          nucleus_id = nucleus_id,
          soma_score = NA_real_,
          dist_npil_nm = NA_real_,
          l2_id = NA_character_,
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
      if (!is.null(nucleus_rows)) {
        nucleus_rows$soma_score <- NA_real_
        nucleus_rows$dist_npil_nm <- NA_real_
        nucleus_rows$l2_id <- NA_character_
      }
    }
  }

  nucleus_ids <- if (!is.null(nucleus_rows)) unique(nucleus_rows$root_id)
                 else character(0)

  # L2-attribute scoring (chunked, one batched CAVE call per chunk) --------
  need_ids <- setdiff(root_ids, c(flytable_ids, nucleus_ids))
  l2_rows <- NULL
  l2_method <- if (method == "auto" && !is.null(mesh)) "l2+mesh"
               else if (method %in% c("l2+mesh", "l2", "mesh")) method
               else NULL
  if (!is.null(l2_method) && length(need_ids)) {
    l2_rows <- .aedes_score_l2_many(need_ids, mesh = mesh, method = l2_method,
                                    chunksize = chunksize, cl = cl)
  }

  # Annotate flytable / nucleus rows with dist_npil_nm + soma_score + l2_id
  # (one batched xyz2id + l2attrs call covers both sources). Cheap and lets
  # users compare confidence across sources.
  if (!is.null(mesh)) {
    if (!is.null(flytable_rows))
      flytable_rows <- .aedes_annotate_known_soma(flytable_rows, mesh = mesh)
    if (!is.null(nucleus_rows))
      nucleus_rows  <- .aedes_annotate_known_soma(nucleus_rows,  mesh = mesh)
  }

  found_ids   <- c(flytable_ids, nucleus_ids,
                   if (!is.null(l2_rows)) l2_rows$root_id else character(0))
  missing_ids <- setdiff(root_ids, found_ids)
  missing_rows <- if (length(missing_ids)) empty_row(missing_ids) else NULL

  out <- do.call(rbind, Filter(Negate(is.null),
                               list(flytable_rows, nucleus_rows,
                                    l2_rows, missing_rows)))

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


#' Predict the L/R side of Aedes neurons
#'
#' @description Returns the logical side of each requested neuron. The side
#'   can come from the manual \code{side} annotation in the FlyTable
#'   metadata (when present) or be derived from the soma's position relative
#'   to the Aedes midline via \code{\link{aedes_point_side}}.
#'
#' @details Methods:
#'   \describe{
#'     \item{\code{auto}}{Try \code{manual} first, then fill any remaining
#'       \code{NA}s using \code{position}.}
#'     \item{\code{manual}}{Read the \code{side} column of
#'       \code{\link{aedes_meta}}. Values are uppercased; entries outside
#'       \code{"L"}, \code{"R"}, \code{"M"}, \code{"U"} become \code{NA}.}
#'     \item{\code{position}}{Classify each soma by its signed displacement
#'       from the Aedes midline via \code{\link{aedes_point_side}}.
#'       \code{threshold} is forwarded as-is; the default \code{0} means
#'       \code{position} never returns \code{"M"}. \code{"M"} is reserved
#'       for bilaterally symmetric / unpaired neurons annotated as such.}
#'   }
#'
#' @param ids Root IDs, a query string (see \code{\link{aedes_ids}}), or a
#'   pre-fetched metadata data.frame from \code{\link{aedes_meta}} (must
#'   contain a \code{root_id} column).
#' @param method One of \code{"auto"} (default), \code{"manual"},
#'   \code{"position"}. See Details.
#' @param threshold Absolute X displacement (nm) below which \code{position}
#'   reports a soma as midline (\code{"M"}). Default \code{0}. Ignored by
#'   \code{manual}.
#' @param mesh,chunksize,cl Forwarded to \code{\link{aedes_soma_position}}.
#' @param version,timestamp Optional CAVE materialisation selectors,
#'   forwarded to \code{\link{aedes_meta}} and
#'   \code{\link{aedes_soma_position}}.
#'
#' @return A character vector of \code{"L"}, \code{"R"}, \code{"M"},
#'   \code{"U"} or \code{NA}, one entry per input root id.
#' @seealso \code{\link{aedes_point_side}}, \code{\link{aedes_soma_position}},
#'   \code{\link{aedes_meta}}
#' @export
#' @examples
#' \dontrun{
#' aedes_soma_side("class:DNa")
#' aedes_soma_side("648518347465408914") # known L
#' aedes_soma_side("class:DNa", method = "position")
#' }
aedes_soma_side <- function(ids,
                            method = c("auto", "manual", "position"),
                            threshold = 0,
                            mesh = aedes::aedes_neuropil_mesh,
                            chunksize = 20L,
                            cl = NULL,
                            version = NULL,
                            timestamp = NULL) {
  method <- match.arg(method)
  vi <- aedes_get_version(which = 'now', version = version,
                          timestamp = timestamp)

  # Resolve a stable, input-ordered root_id vector. If the caller already
  # has a metadata data.frame, trust its order and root_id column;
  # otherwise fetch metadata once and reuse it for both `manual` (side
  # column) and the `position` fallback (passed through to
  # aedes_soma_position so it can skip its own aedes_meta call).
  if (is.data.frame(ids)) {
    if (!"root_id" %in% colnames(ids))
      stop("data.frame input must contain a `root_id` column.", call. = FALSE)
    root_ids <- as.character(ids$root_id)
    meta <- ids
  } else {
    meta <- aedes_meta(ids, version = vi$version, timestamp = vi$timestamp,
                       unique = TRUE)
    root_ids <- as.character(meta$root_id)
  }
  n <- length(root_ids)
  if (n == 0L) return(character(0))

  if (method == "manual") {
    if (!"side" %in% colnames(meta))
      stop("metadata lacks a `side` column for method=\"manual\".",
           call. = FALSE)
    idx <- match(root_ids, as.character(meta$root_id))
    s <- toupper(as.character(meta$side[idx]))
    s[!s %in% c("L", "R", "M", "U")] <- NA_character_
    return(s)
  }

  if (method == "position") {
    # Pass meta straight through so aedes_soma_position skips its own
    # aedes_ids + aedes_meta round-trips.
    sp <- aedes_soma_position(meta, units = "nm", nuclei = "largest",
                              mesh = mesh, chunksize = chunksize, cl = cl,
                              version = vi$version, timestamp = vi$timestamp)
    out <- rep(NA_character_, n)
    ok <- !is.na(sp$position) & nzchar(sp$position)
    if (any(ok)) {
      xyz <- nat::xyzmatrix(sp$position[ok])
      out[ok] <- aedes_point_side(xyz, units = "nm", threshold = threshold)
    }
    return(out)
  }

  # auto: manual -> position. Inline the `side` column read (rather than
  # recursing through method="manual") so a missing column simply yields
  # NAs to fall through to the position branch instead of erroring.
  res <- if ("side" %in% colnames(meta)) {
    idx <- match(root_ids, as.character(meta$root_id))
    s <- toupper(as.character(meta$side[idx]))
    s[!s %in% c("L", "R", "M", "U")] <- NA_character_
    s
  } else {
    rep(NA_character_, n)
  }
  miss <- is.na(res)
  if (any(miss)) {
    res[miss] <- aedes_soma_side(meta[miss, , drop = FALSE],
                                 method = "position",
                                 threshold = threshold,
                                 mesh = mesh, chunksize = chunksize, cl = cl,
                                 version = vi$version,
                                 timestamp = vi$timestamp)
  }
  res
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
#' @param method Reroot strategy passed through to [aedes_soma_position()].
#'   With `"auto"` (the default) each neuron is handled by the first source
#'   that succeeds in the cascade: FlyTable `soma_xyz` → FlyWire nucleus →
#'   `"l2+mesh"` (a combined L2-attribute + neuropil signed-distance score
#'   for any neuron that has no FlyTable or nucleus soma; only used if a
#'   `mesh` is available). Restrict to a single value to disable the cascade.
#'   `"none"` skips rerooting (equivalent to `reroot = FALSE`).
#' @param mesh A `mesh3d` for the neuropil. Defaults to the packaged
#'   [aedes_neuropil_mesh]. Pass `NULL` to disable mesh-based fallback in
#'   `"auto"`; `"l2+mesh"` and `"mesh"` error without a mesh.
#' @param chunksize,cl Forwarded to [aedes_soma_position()] -- batch size for
#'   L2 attribute fetches and optional parallel cluster for chunk processing.
#' @param OmitFailures Passed to [fafbseg::read_l2skel()].
#' @param previous Optional [nat::neuronlist()] from an earlier call. Neurons
#'   whose names match requested root ids are reused so only missing skeletons
#'   are read. `previous` is expected to be in nm coordinates.
#' @param version,timestamp Optional CAVE materialisation selectors.
#' @param ... Additional arguments passed to [fafbseg::read_l2skel()].
#'
#' @return A [nat::neuronlist()] of L2 skeletons. When rerooted, each neuron's
#'   `data` slot gains `soma_source` (`"flytable"`, `"nucleus"`, `"l2+mesh"`,
#'   `"l2"`, `"mesh"`, or `NA`), `n_nuclei` (count of distinct-position
#'   nucleus candidates considered, or `NA`), and `nucleus_id` (the
#'   `nuclei_v1_aedes` primary key of the chosen row, or `NA`). `n_nuclei > 1`
#'   indicates the chosen nucleus was one of several at distinct positions
#'   for that root id; see [aedes_soma_position()] for the full candidate
#'   list.
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
                                          "l2+mesh", "l2", "mesh", "none"),
                               mesh = aedes::aedes_neuropil_mesh,
                               chunksize = 20L,
                               cl = NULL,
                               OmitFailures = TRUE,
                               previous = NULL,
                               version = NULL,
                               timestamp = NULL,
                               ...) {
  units  <- match.arg(units)
  method <- match.arg(method)
  if (identical(method, "none")) reroot <- FALSE

  vi <- aedes_get_version(version = version, timestamp = timestamp)
  root_ids <- as.character(aedes_ids(ids, version = vi$version,
                                     timestamp = vi$timestamp))

  if (!is.null(previous) && !nat::is.neuronlist(previous))
    stop("`previous` must be a nat::neuronlist().", call. = FALSE)
  have_ids <- intersect(root_ids, names(previous))
  need_ids <- setdiff(root_ids, have_ids)

  fetched <- if (length(need_ids))
    with_aedes(fafbseg::read_l2skel(need_ids, OmitFailures = OmitFailures, ...))
    else nat::neuronlist()
  reused <- if (length(have_ids)) previous[have_ids] else nat::neuronlist()
  res <- c(reused, fetched)
  res <- res[intersect(root_ids, names(res))]

  if (isTRUE(reroot) && length(res)) {
    soma <- aedes_soma_position(
      names(res), method = method, mesh = mesh,
      chunksize = chunksize, cl = cl,
      version = vi$version, timestamp = vi$timestamp
    )
    # one row per id in input order; reroot each neuron to its soma point
    reroot_ids <- intersect(names(res), soma$root_id[!is.na(soma$position)])
    soma_points <- stats::setNames(soma$position, soma$root_id)
    for (id in reroot_ids) {
      pt <- as.numeric(nat::xyzmatrix(soma_points[[id]])[1, ])
      res[[id]] <- aedes_root_point(res[[id]], point = pt,
                                    method = "point", rval = "neuron")
    }

    # attach per-neuron provenance to the neuronlist data slot
    md <- res[, , drop = FALSE]
    ord <- match(rownames(md), soma$root_id)
    md$soma_source <- soma$source[ord]
    md$n_nuclei    <- soma$n_nuclei[ord]
    md$nucleus_id  <- soma$nucleus_id[ord]
    md$soma_score  <- soma$soma_score[ord]
    md$dist_npil_nm <- soma$dist_npil_nm[ord]
    md$l2_id <- soma$l2_id[ord]
    res[, ] <- md

    if (anyNA(md$soma_source))
      warning(sum(is.na(md$soma_source)), " of ", nrow(md),
              " neurons could not be rerooted; soma_source is NA for those.",
              call. = FALSE)
  }
  # record version info for future reference
  attr(res, 'vi')=vi
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
    filter(stats::complete.cases(nat::xyzmatrix(.data$position)) &
             !is.na(.data$root_id)) %>%
    arrange(.data$root_id, desc(.data$volume)) %>%
    distinct(.data$root_id, .data$position, .keep_all = TRUE) %>%
    add_count(.data$root_id, name = "n_nuclei") %>%
    select("root_id", "position", "source", "n_nuclei", "nucleus_id")

  if (!nrow(picked)) return(NULL)
  if (nuclei == "largest")
    picked <- distinct(picked, .data$root_id, .keep_all = TRUE)
  as.data.frame(picked)
}


# Score a single neuron's L2 chunks (already fetched as a `flywire_l2attributes`
# data.frame) and return them ordered by ASCENDING soma score
# (lower = more soma-like).
#
# `features` controls the combination of terms:
#   shape (always used when any of area/size/max_dt/mean_dt/roundness is
#          requested): squared Mahalanobis distance of (log_area, log_size,
#          log_max_dt, log_mean_dt, roundness) versus the KC positive
#          population stats stored in `aedes_soma_l2_stats`. Smaller = closer
#          to the KC soma cloud.
#   "mesh": empirical KDE prior on signed neuropil distance (um). Penalty is
#          `-2 * log(f_hat(d) / max(f_hat))` using the population density of
#          flywire_nuclei distances + a small uniform background; the floor
#          keeps real central-brain neurons (sitting 0-3 um inside the
#          neuropil) from being hard-rejected.
#
# `method = "l2"` skips the mesh term; `method = "mesh"` uses only the mesh
# penalty. Degenerate L2 chunks (pca_val_0 == 0) are filtered out.
# Pure scoring math: takes a flywire_l2attributes-shaped df, returns it with
# two new columns (`dist_npil`, `score`) computed positionally. No row
# filtering, no reordering -- callers that need that wrap this. Rows with
# `pca_val_0 == 0` or other degeneracies will produce NA scores, not be
# dropped.
#' @noRd
.aedes_compute_l2_score <- function(df, mesh = NULL,
                                    use_shape = TRUE, use_mesh = TRUE) {
  if (use_mesh && is.null(mesh))
    stop("mesh requested but no mesh supplied", call. = FALSE)
  model <- aedes::aedes_soma_l2_stats

  if (!is.null(mesh)) {
    xyz <- as.matrix(df[, c("rep_coord_nm_x", "rep_coord_nm_y",
                            "rep_coord_nm_z")])
    df$dist_npil <- nat::pointsinside(xyz, surf = mesh, rval = "dist")
  } else {
    df$dist_npil <- NA_real_
  }

  mahal_shape <- rep(0, nrow(df))
  if (use_shape) {
    feats <- data.frame(
      log_area_nm2   = log1p(pmax(df$area_nm2, 0)),
      log_size_nm3   = log1p(pmax(df$size_nm3, 0)),
      log_max_dt_nm  = log1p(pmax(df$max_dt_nm, 0)),
      log_mean_dt_nm = log1p(pmax(df$mean_dt_nm, 0)),
      roundness      = ifelse(df$pca_val_0 > 0,
                              df$pca_val_2 / df$pca_val_0, NA_real_)
    )
    mahal_shape <- stats::mahalanobis(
      as.matrix(feats[, model$feature_names, drop = FALSE]),
      center = model$positive_mean, cov = model$positive_cov
    )
    mahal_shape[!is.finite(mahal_shape)] <- NA_real_
  }

  dist_penalty <- rep(0, nrow(df))
  if (use_mesh) {
    dpd <- model$dist_npil_density
    d_um <- df$dist_npil / 1000
    f_hat <- stats::approx(dpd$x, dpd$y, xout = d_um, rule = 2,
                           yleft = dpd$uniform_density * dpd$uniform_eps,
                           yright = dpd$uniform_density * dpd$uniform_eps)$y
    out_of_support <- !is.finite(d_um) |
      d_um < dpd$support[1] | d_um > dpd$support[2]
    f_hat[out_of_support] <- dpd$uniform_density * dpd$uniform_eps
    dist_penalty <- -2 * log(pmax(f_hat, .Machine$double.xmin) / dpd$y_max)
  }

  w <- model$dist_penalty_weight %||% 1
  df$score <- mahal_shape + w * dist_penalty
  df
}

# Cascade-facing wrapper: filter degenerate L2 chunks, score, sort ascending.
#' @noRd
.aedes_score_l2_df <- function(df, mesh = NULL,
                               features = c("area", "size", "max_dt", "mean_dt",
                                            "roundness", "mesh")) {
  features <- match.arg(features, several.ok = TRUE)
  use_mesh  <- "mesh" %in% features
  use_shape <- any(c("area", "size", "max_dt", "mean_dt", "roundness")
                   %in% features)
  if (use_mesh && is.null(mesh))
    stop("`mesh` feature requested but no mesh supplied", call. = FALSE)
  if (is.null(df) || !nrow(df)) return(NULL)
  df <- df[!is.na(df$pca_val_0) & df$pca_val_0 > 0, , drop = FALSE]
  if (!nrow(df)) return(NULL)
  df <- .aedes_compute_l2_score(df, mesh = mesh,
                                use_shape = use_shape, use_mesh = use_mesh)
  df[order(df$score), , drop = FALSE]
}

`%||%` <- function(a, b) if (is.null(a)) b else a


# Single-neuron convenience: fetch + score in one go. Not used by the cascade
# (which batches via `.aedes_score_l2_many()`); handy for ad-hoc debugging.
#' @noRd
.aedes_score_l2 <- function(root_id, mesh = NULL,
                            features = c("area", "size", "max_dt", "mean_dt",
                                         "roundness", "mesh")) {
  features <- match.arg(features, several.ok = TRUE)
  df <- with_aedes(fafbseg::flywire_l2attributes(rootid = root_id))
  .aedes_score_l2_df(df, mesh = mesh, features = features)
}


# Score L2 chunks for many root ids and return one row per id (the top-scoring
# chunk's rep_coord_nm) in the shape `aedes_soma_position()` expects.
#
# Batches the L2 attribute fetch into `chunksize` neurons per CAVE call (one
# call instead of N) and runs chunks under `pbapply::pblapply` with optional
# parallelism via `cl` -- worthwhile for hundreds to thousands of neurons.
#' @noRd
.aedes_score_l2_many <- function(root_ids, mesh = NULL,
                                 method = c("l2+mesh", "l2", "mesh"),
                                 chunksize = 20L,
                                 cl = NULL) {
  method <- match.arg(method)
  if (!length(root_ids)) return(NULL)
  features <- switch(
    method,
    `l2+mesh` = c("area", "size", "max_dt", "mean_dt", "roundness", "mesh"),
    `l2`      = c("area", "size", "max_dt", "mean_dt", "roundness"),
    `mesh`    = "mesh"
  )

  chunksize <- max(1L, as.integer(chunksize))
  chunks <- nat.utils::make_chunks(root_ids, chunksize = chunksize)

  # progress + optional parallelism over chunks; skip pblapply for a single
  # chunk to avoid spurious progress bars for tiny jobs
  per_chunk <- if (length(chunks) > 1L)
                 pbapply::pblapply(
                   chunks, .aedes_score_l2_chunk,
                   mesh = mesh, features = features, method = method,
                   cl = cl
                 )
               else list(.aedes_score_l2_chunk(
                 chunks[[1]], mesh = mesh, features = features,
                 method = method
               ))
  do.call(rbind, Filter(Negate(is.null), per_chunk))
}


# Score one chunk of root ids using a single batched L2 attribute fetch.
#' @noRd
.aedes_score_l2_chunk <- function(root_ids, mesh = NULL, features, method) {
  l2ids_per_root <- lapply(root_ids, .aedes_l2ids_for_root)
  names(l2ids_per_root) <- root_ids

  good <- lengths(l2ids_per_root) > 0L
  if (!any(good)) return(NULL)

  all_l2 <- unique(unlist(lapply(l2ids_per_root[good], as.character),
                          use.names = FALSE))
  if (!length(all_l2)) return(NULL)

  attr_df <- tryCatch(
    with_aedes(fafbseg::flywire_l2attributes(
      l2ids = bit64::as.integer64(all_l2)
    )),
    error = function(e) {
      warning("flywire_l2attributes() failed for chunk: ",
              conditionMessage(e), call. = FALSE)
      NULL
    }
  )
  if (is.null(attr_df) || !nrow(attr_df)) return(NULL)

  attr_l2 <- as.character(attr_df$l2_id)
  rows <- lapply(root_ids, .aedes_score_l2_root_from_attr,
                 l2ids_per_root = l2ids_per_root,
                 attr_df = attr_df, attr_l2 = attr_l2,
                 mesh = mesh, features = features, method = method)
  do.call(rbind, Filter(Negate(is.null), rows))
}


# Fetch L2 ids for one root id. Kept separate for easier ad-hoc debugging.
#' @noRd
.aedes_l2ids_for_root <- function(root_id) {
  tryCatch(
    with_aedes(fafbseg::flywire_l2ids(root_id, integer64 = TRUE)),
    error = function(e) {
      warning("flywire_l2ids() failed for ", root_id, ": ",
              conditionMessage(e), call. = FALSE)
      NULL
    }
  )
}


# Score the rows belonging to one root id out of a chunk-wide L2 attribute table.
#' @noRd
.aedes_score_l2_root_from_attr <- function(root_id, l2ids_per_root,
                                           attr_df, attr_l2,
                                           mesh = NULL, features, method) {
  l2ids <- l2ids_per_root[[root_id]]
  if (is.null(l2ids) || !length(l2ids)) return(NULL)

  sub <- attr_df[attr_l2 %in% as.character(l2ids), , drop = FALSE]
  scored <- tryCatch(
    .aedes_score_l2_df(sub, mesh = mesh, features = features),
    error = function(e) {
      warning("L2 scoring failed for ", root_id, ": ",
              conditionMessage(e), call. = FALSE)
      NULL
    }
  )
  if (is.null(scored) || !nrow(scored)) return(NULL)

  .aedes_l2_soma_row(scored[1, ], root_id = root_id, source = method)
}


# Convert a top-scoring L2 attribute row into a soma-position row. Diagnostic
# columns (soma_score, dist_npil_nm, l2_id) are always populated; non-L2 rows
# get them set to NA by the caller (`aedes_soma_position()`).
#' @noRd
.aedes_l2_soma_row <- function(x, root_id, source) {
  pos <- nat::xyzmatrix2str(matrix(c(x$rep_coord_nm_x,
                                     x$rep_coord_nm_y,
                                     x$rep_coord_nm_z), ncol = 3))
  data.frame(
    root_id      = root_id,
    position     = pos,
    source       = source,
    n_nuclei     = NA_integer_,
    nucleus_id   = NA_integer_,
    soma_score   = x$score,
    dist_npil_nm = x$dist_npil,
    l2_id        = if ("l2_id" %in% names(x)) as.character(x$l2_id) else NA_character_,
    stringsAsFactors = FALSE
  )
}


# Annotate rows whose soma position is already known (from FlyTable or the
# nucleus table) with `dist_npil_nm`, `soma_score`, and `l2_id`.
#
# Two-pass design so the cheap part is always-on:
#   (1) dist_npil_nm: direct `nat::pointsinside()` on the recorded soma point
#       (the authoritative location, not an L2 rep_coord). Free, no network.
#   (2) soma_score + l2_id: one batched `aedes_xyz2id(stop_layer = 2L)` call
#       resolves all points to L2 ids; one (or few) batched
#       `flywire_l2attributes(l2ids = ...)` calls fetch attrs; then the pure
#       scoring helper produces a cross-source comparable score. Wrapped in
#       `tryCatch` so service failures or degenerate chunks leave score/l2_id
#       as NA without disturbing the dist_npil_nm column.
#
# `rows` is a data.frame with `position` (nm string), `soma_score`,
# `dist_npil_nm`, `l2_id` columns. Returns the same shape, columns updated.
#' @noRd
.aedes_annotate_known_soma <- function(rows, mesh,
                                       l2_chunksize = 5000L) {
  if (is.null(rows) || !nrow(rows) || is.null(mesh)) return(rows)
  xyz <- nat::xyzmatrix(rows$position)
  has_xyz <- stats::complete.cases(xyz)
  if (!any(has_xyz)) return(rows)

  # (1) dist_npil_nm -- direct, unconditional
  rows$dist_npil_nm[has_xyz] <- nat::pointsinside(
    xyz[has_xyz, , drop = FALSE], surf = mesh, rval = "dist"
  )

  # (2) l2_id + soma_score -- batched lookup, can fail gracefully
  tryCatch({
    l2ids <- aedes_xyz2id(xyz[has_xyz, , drop = FALSE],
                          rawcoords = FALSE, stop_layer = 2L,
                          integer64 = TRUE)
    l2_chr <- as.character(l2ids)
    ok <- !is.na(l2_chr) & l2_chr != "0"
    rows$l2_id[has_xyz][ok] <- l2_chr[ok]

    unique_l2 <- unique(l2_chr[ok])
    if (!length(unique_l2)) return(invisible(NULL))

    chunks <- nat.utils::make_chunks(unique_l2,
                                     chunksize = max(1L, as.integer(l2_chunksize)))
    attr_df <- do.call(rbind, lapply(chunks, function(ids) {
      with_aedes(fafbseg::flywire_l2attributes(
        l2ids = bit64::as.integer64(ids)
      ))
    }))
    if (is.null(attr_df) || !nrow(attr_df)) return(invisible(NULL))

    scored <- .aedes_compute_l2_score(attr_df, mesh = mesh,
                                      use_shape = TRUE, use_mesh = TRUE)
    score_lookup <- setNames(scored$score, as.character(scored$l2_id))
    rows$soma_score[has_xyz][ok] <- unname(score_lookup[l2_chr[ok]])
  }, error = function(e) {
    warning("L2 annotation of known soma points failed: ",
            conditionMessage(e), call. = FALSE)
  })

  rows
}
