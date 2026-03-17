#' Find Aedes root or supervoxel (leaf) IDs for XYZ locations
#'
#' @param method Lookup method: `"auto"` and `"spine"` use the Aedes transform
#'   service; `"cloudvolume"` delegates to [fafbseg::flywire_xyz2id()].
#' @inheritParams fafbseg::flywire_xyz2id
#' @param ... Additional arguments passed to backend helpers.
#'
#' @return A vector of segment IDs (`character` or `integer64`).
#' @details Method auto (which maps to spine) should be much faster for look ups
#' with many points, especially points in the same region of space.
#'
#' @export
#'
#' @examples
#' \dontrun{
#' aedes_xyz2id(c(24606, 12450, 5798), rawcoords = TRUE, root = FALSE)
#' }
aedes_xyz2id <- function(
    xyz,
    rawcoords = FALSE,
    voxdims = aedes_voxdims(),
    cloudvolume.url = NULL,
    root = TRUE,
    timestamp = NULL,
    version = NULL,
    stop_layer = NULL,
    integer64 = FALSE,
    method = c("auto", "cloudvolume", "spine"),
    ...) {
  method <- match.arg(method)

  if (isTRUE(is.numeric(xyz) && is.vector(xyz) && length(xyz) == 3)) {
    xyz <- matrix(xyz, ncol = 3)
  } else {
    xyz <- nat::xyzmatrix(xyz)
  }

  if (method == "cloudvolume") {
    return(with_aedes(fafbseg::flywire_xyz2id(
      xyz = xyz,
      rawcoords = rawcoords,
      voxdims = voxdims,
      cloudvolume.url = cloudvolume.url,
      root = root,
      timestamp = timestamp,
      version = version,
      stop_layer = stop_layer,
      integer64 = integer64,
      method = "cloudvolume",
      ...
    )))
  }

  xyz_raw <- if (isTRUE(rawcoords)) {
    xyz
  } else {
    scale(xyz, scale = voxdims, center = FALSE)
  }

  na_rows <- !stats::complete.cases(xyz_raw)
  n <- nrow(xyz_raw)
  zero_ids <- rep(flywire_ids(0L, integer64 = integer64), n)

  if (all(na_rows)) {
    return(zero_ids)
  }

  res <- aedes_supervoxels(xyz_raw[!na_rows, , drop = FALSE], ...)
  if (!root) {
    looked_up <- fafbseg::flywire_ids(res, integer64 = integer64)
    out <- zero_ids
    out[!na_rows] <- looked_up
    return(out)
  }
  if (root) {
    res <- with_aedes(fafbseg::flywire_rootid(
      res,
      cloudvolume.url = cloudvolume.url,
      timestamp = timestamp,
      version = version,
      stop_layer = stop_layer,
      integer64 = integer64
    ))
    out <- zero_ids
    out[!na_rows] <- res
    return(out)
  }
}

#' @noRd
aedes_supervoxels <- function(
    x,
    chunksize = 2000L,
    mip = 0,
    format = "array_float_Nx3",
    dataset = "wclee_aedes_brain",
    base_url = "https://flyem.mrc-lmb.cam.ac.uk/transform-service/query/dataset") {
  pts <- nat::xyzmatrix(x)
  n <- nrow(pts)
  if (n > chunksize) {
    chunks <- nat.utils::make_chunks(seq_len(n), chunksize = chunksize)
    out <- rep("0", n)
    while (length(chunks) > 0) {
      res <- pbapply::pblapply(chunks, function(idx) {
        tryCatch(
          aedes_supervoxels_one(pts[idx, , drop = FALSE], mip = mip,
                                format = format, dataset = dataset,
                                base_url = base_url),
          error = function(e) NULL
        )
      })
      badchunks <- vapply(res, is.null, logical(1))
      for (i in which(!badchunks)) {
        out[chunks[[i]]] <- res[[i]]
      }
      if (!any(badchunks)) {
        chunks <- NULL
      } else {
        chunksize <- max(round(chunksize / 2), 1L)
        chunks <- nat.utils::make_chunks(
          unlist(chunks[badchunks]), chunksize = chunksize
        )
        message("Refetching ", sum(lengths(chunks)),
                " points after reducing chunksize to: ", chunksize)
      }
    }
    nfailed <- sum(out == "0")
    if (nfailed > 0)
      warning(nfailed, " points failed supervoxel lookup and were set to 0")
    return(out)
  }
  aedes_supervoxels_one(pts, mip = mip, format = format,
                         dataset = dataset, base_url = base_url)
}

#' @noRd
aedes_supervoxels_one <- function(
    pts,
    mip = 0,
    format = "array_float_Nx3",
    dataset = "wclee_aedes_brain",
    base_url = "https://flyem.mrc-lmb.cam.ac.uk/transform-service/query/dataset") {
  ptsb <- writeBin(as.numeric(t(pts)), con = raw(), size = 4)
  u <- glue::glue("{base_url}/{dataset}/s/{mip}/values_binary/format/{format}")

  res <- httr::POST(u, body = ptsb, encode = "raw")
  httr::stop_for_status(res)
  arr <- httr::content(res, as = "raw")
  bytes <- readBin(
    arr,
    what = numeric(),
    n = length(arr) / 8,
    size = 8,
    endian = "little"
  )
  class(bytes) <- "integer64"
  as.character(bytes)
}
