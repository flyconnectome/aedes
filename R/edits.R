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
#' @param ... Additional arguments (currently unused).
#'
#' @return A data.frame with one row per operation (or a named list if
#'   `return.data.frame = FALSE`).
#' @keywords internal
chunkedgraph_operation_details <- function(ops, datastack_name,
                                           chunksize = 50,
                                           return.data.frame = TRUE, ...) {
  acc <- fafbseg::flywire_cave_client(datastack_name = datastack_name)
  .chunkedgraph_operation_details(ops, acc = acc, chunksize = chunksize,
                                  return.data.frame = return.data.frame, ...)
}

#' @noRd
.chunkedgraph_operation_details <- function(ops, acc, chunksize = 50,
                                            return.data.frame = TRUE, ...) {
  nops <- length(ops)
  if (nops > chunksize) {
    nchunks <- ceiling(nops / chunksize)
    chunks <- rep(seq_len(nchunks), rep(chunksize, nchunks))[seq_len(nops)]
    sops <- split(ops, chunks)
    ll <- pbapply::pblapply(sops, .chunkedgraph_operation_details, acc = acc,
                            chunksize = Inf, return.data.frame = FALSE, ...)
    l2 <- unlist(ll, recursive = FALSE, use.names = FALSE)
    if (return.data.frame) {
      df <- fafbseg:::list2df(l2)
      df$operation_id <- as.integer(unlist(sapply(ll, names), use.names = FALSE))
      df <- df[c("operation_id", setdiff(colnames(df), "operation_id"))]
      df$timestamp <- as.POSIXct(df$timestamp, tz = "UTC")
      return(df)
    } else {
      return(l2)
    }
  }

  pyjson <- reticulate::import("json")
  v <- reticulate::py_call(acc$chunkedgraph$get_operation_details,
                           operation_ids = as.list(as.integer(ops)))
  ps <- RcppSimdJson::fparse(pyjson$dumps(v), int64_policy = "string",
                             always_list = FALSE)

  if (return.data.frame) {
    df <- fafbseg:::list2df(ps)
    df$operation_id <- as.integer(names(ps))
    df <- df[c("operation_id", setdiff(colnames(df), "operation_id"))]
    if (!is.null(df$timestamp))
      df$timestamp <- as.POSIXct(df$timestamp, tz = "UTC")
    df
  } else {
    ps
  }
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
#' @param ... Additional arguments passed to [chunkedgraph_operation_details()].
#'
#' @return A data.frame of all operation details.
#' @keywords internal
all_chunkedgraph_operations <- function(datastack_name, last = NULL, ...) {
  if (is.null(last))
    last <- last_chunkedgraph_edit(datastack_name)
  chunkedgraph_operation_details(seq_len(last), datastack_name = datastack_name, ...)
}

#' @noRd
.parse_op_coords <- function(s) {
  if (is.na(s) || s == "NA") return(NULL)
  v <- as.numeric(strsplit(s, ",", fixed = TRUE)[[1]])
  n <- length(v) / 3L
  matrix(v, nrow = n, ncol = 3, dimnames = list(NULL, c("x", "y", "z")))
}

#' @noRd
.coord_centroid <- function(s) {
  m <- .parse_op_coords(s)
  if (is.null(m)) return(c(x = NA_real_, y = NA_real_, z = NA_real_))
  colMeans(m)
}

#' @noRd
add_operation_centroids <- function(df) {
  sink_ctr   <- do.call(rbind, lapply(df$sink_coords,   .coord_centroid))
  source_ctr <- do.call(rbind, lapply(df$source_coords, .coord_centroid))
  df$sink_x <- sink_ctr[, "x"];   df$sink_y <- sink_ctr[, "y"];   df$sink_z <- sink_ctr[, "z"]
  df$source_x <- source_ctr[, "x"]; df$source_y <- source_ctr[, "y"]; df$source_z <- source_ctr[, "z"]
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
