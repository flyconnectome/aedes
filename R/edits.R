# Generic chunkedgraph edit functions ----------------------------------------
# These work with any CAVE dataset via datastack_name.
# Aedes-specific wrappers at the bottom supply the default datastack.

#' Fetch operation details from a CAVE chunkedgraph
#'
#' @param ops Integer vector of operation IDs.
#' @param datastack_name CAVE datastack name.
#' @param chunksize Number of operations per API request.
#' @param return.data.frame If `TRUE` (default), return a data.frame; otherwise
#'   return a raw named list.
#' @param compute_centroids If `TRUE`, add centroid columns for sink and source
#'   coordinates (`sink_x/y/z`, `source_x/y/z`). Only applies when
#'   `return.data.frame = TRUE`.
#' @param ... Additional arguments (currently unused).
#'
#' @return A data.frame with one row per operation (or a named list if
#'   `return.data.frame = FALSE`).
#' @keywords internal
chunkedgraph_operation_details <- function(ops, datastack_name,
                                           chunksize = 50,
                                           return.data.frame = TRUE,
                                           compute_centroids = FALSE, ...) {
  acc <- fafbseg::flywire_cave_client(datastack_name = datastack_name)
  pyjson <- reticulate::import("json")
  df <- .chunkedgraph_operation_details(ops, acc = acc, chunksize = chunksize,
                                        return.data.frame = return.data.frame,
                                        pyjson = pyjson, ...)
  if (compute_centroids && return.data.frame)
    df <- add_operation_centroids(df)
  df
}

#' @noRd
.chunkedgraph_operation_details <- function(ops, acc, chunksize = 50,
                                            return.data.frame = TRUE,
                                            pyjson = reticulate::import("json"), ...) {
  nops <- length(ops)
  if (nops > chunksize) {
    nchunks <- ceiling(nops / chunksize)
    chunks <- rep(seq_len(nchunks), rep(chunksize, nchunks))[seq_len(nops)]
    sops <- split(ops, chunks)
    ll <- pbapply::pblapply(sops, .chunkedgraph_operation_details, acc = acc,
                            chunksize = Inf, return.data.frame = FALSE,
                            pyjson = pyjson, ...)
    l2 <- unlist(ll, recursive = FALSE, use.names = TRUE)
    if (return.data.frame) {
      return(.operation_details_list_to_df(l2))
    } else {
      return(l2)
    }
  }

  v <- reticulate::py_call(acc$chunkedgraph$get_operation_details,
                           operation_ids = as.list(as.integer(ops)))
  ps <- RcppSimdJson::fparse(pyjson$dumps(v), int64_policy = "string",
                             always_list = FALSE)

  if (return.data.frame) {
    .operation_details_list_to_df(ps)
  } else {
    ps
  }
}

#' @noRd
.operation_details_list_to_df <- function(x) {
  if (!length(x))
    return(data.frame(operation_id = integer()))

  op_ids <- as.integer(names(x))
  if (length(op_ids) != length(x) || anyNA(op_ids))
    stop("Operation detail response did not include valid operation IDs")

  df <- fafbseg:::list2df(unname(x))
  df$operation_id <- op_ids
  df <- df[c("operation_id", setdiff(colnames(df), "operation_id"))]
  if (!is.null(df$timestamp))
    df$timestamp <- as.POSIXct(df$timestamp, tz = "UTC")
  df
}

#' Use binary search to find the last edit operation ID for a CAVE dataset
#'
#' @param datastack_name CAVE datastack name.
#' @param start Start index for search (must exist).
#' @param stop Finish index for search (must not exist).
#'
#' @return An integer operation ID.
#' @keywords internal
last_chunkedgraph_edit <- function(datastack_name, start = 1e5, stop = 1e6) {
  acc <- fafbseg::flywire_cave_client(datastack_name = datastack_name)
  .last_chunkedgraph_edit(start = start, stop = stop, acc = acc)
}

#' @noRd
.last_chunkedgraph_edit <- function(start, stop, acc) {
  message("start=", start, " stop=", stop)
  if (!.chunkedgraph_edit_exists(start, acc))
    stop("Couldn't verify start operation exists!")
  if (.chunkedgraph_edit_exists(stop, acc))
    stop("stop operation actually exists! It should be > the latest operation id")
  pivot <- ceiling(mean(c(start, stop)))
  if (pivot == start || pivot == stop)
    return(start)
  if (.chunkedgraph_edit_exists(pivot, acc))
    .last_chunkedgraph_edit(pivot, stop, acc)
  else
    .last_chunkedgraph_edit(start, pivot, acc)
}

#' @noRd
.chunkedgraph_edit_exists <- function(op, acc) {
  v <- tryCatch(
    reticulate::py_call(acc$chunkedgraph$get_operation_details,
                        operation_ids = list(as.integer(op))),
    error = function(e) NULL
  )
  if (is.null(v)) return(NA)
  length(v) > 0
}

#' Fetch all edit operations for a CAVE dataset
#'
#' Finds the last operation via binary search then fetches details for all IDs
#' from 1 to that maximum.
#'
#' @param datastack_name CAVE datastack name.
#' @param last Optional integer; if `NULL` (default), determined automatically
#'   via [last_chunkedgraph_edit()].
#' @param compute_centroids Passed to [chunkedgraph_operation_details()].
#' @param ... Additional arguments passed to [chunkedgraph_operation_details()].
#'
#' @return A data.frame of all operation details.
#' @keywords internal
all_chunkedgraph_operations <- function(datastack_name, last = NULL,
                                        compute_centroids = FALSE, ...) {
  if (is.null(last))
    last <- last_chunkedgraph_edit(datastack_name)
  chunkedgraph_operation_details(seq_len(last), datastack_name = datastack_name,
                                 compute_centroids = compute_centroids, ...)
}

#' @noRd
.coord_centroid <- function(s) {
  if (is.na(s) || s == "NA") return(c(x = NA_real_, y = NA_real_, z = NA_real_))
  v <- as.numeric(strsplit(s, ",", fixed = TRUE)[[1]])
  colMeans(matrix(v, ncol = 3, dimnames = list(NULL, c("x", "y", "z"))))
}

#' @noRd
add_operation_centroids <- function(df) {
  coord_cols <- paste0(c("sink", "source"), "_coords")
  if (!nrow(df) || !all(coord_cols %in% colnames(df)))
    return(df)
  for (col in c("sink", "source")) {
    ctr <- t(vapply(df[[paste0(col, "_coords")]], .coord_centroid, numeric(3)))
    df[paste0(col, c("_x", "_y", "_z"))] <- ctr
  }
  df
}

# Aedes wrappers --------------------------------------------------------------

#' @describeIn chunkedgraph_operation_details Aedes-specific wrapper.
#' @keywords internal
aedes_operation_details <- function(ops, ...) {
  chunkedgraph_operation_details(
    ops,
    datastack_name = choose_aedes(set = FALSE)[["fafbseg.cave.datastack_name"]],
    ...
  )
}

#' @describeIn last_chunkedgraph_edit Aedes-specific wrapper.
#' @keywords internal
last_aedes_edit <- function(...) {
  last_chunkedgraph_edit(
    datastack_name = choose_aedes(set = FALSE)[["fafbseg.cave.datastack_name"]],
    ...
  )
}

#' @describeIn all_chunkedgraph_operations Aedes-specific wrapper.
#' @keywords internal
aedes_all_operations <- function(...) {
  all_chunkedgraph_operations(
    datastack_name = choose_aedes(set = FALSE)[["fafbseg.cave.datastack_name"]],
    ...
  )
}
