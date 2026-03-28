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
#' @param cache Path to a cache directory. Set to `NULL` to disable caching.
#'   Defaults to the user cache dir managed by `rappdirs`.
#' @param ... Additional arguments (currently unused).
#'
#' @return A data.frame with one row per operation (or a named list if
#'   `return.data.frame = FALSE`).
#' @keywords internal
chunkedgraph_operation_details <- function(ops, datastack_name,
                                           chunksize = 50,
                                           return.data.frame = TRUE,
                                           compute_centroids = FALSE,
                                           cache = rappdirs::user_cache_dir("aedes", appauthor = FALSE),
                                           ...) {
  ops <- as.integer(ops)

  if (!return.data.frame || is.null(cache)) {
    acc <- fafbseg::flywire_cave_client(datastack_name = datastack_name)
    pyjson <- reticulate::import("json")
    df <- .chunkedgraph_operation_details(ops, acc = acc, chunksize = chunksize,
                                          return.data.frame = return.data.frame,
                                          pyjson = pyjson, ...)
    if (compute_centroids && return.data.frame)
      df <- add_operation_centroids(df)
    return(df)
  }

  cache_files <- .chunkedgraph_ops_cache_files(datastack_name, cache)
  cached_df <- .read_ops_cache(cache_files$ops)
  known_missing <- .read_missing_ops_cache(cache_files$missing)
  cached_ids <- if (is.null(cached_df)) integer(0) else cached_df$operation_id
  to_fetch <- setdiff(ops, union(cached_ids, known_missing))

  if (length(to_fetch) > 0) {
    acc <- fafbseg::flywire_cave_client(datastack_name = datastack_name)
    pyjson <- reticulate::import("json")
    fresh <- .chunkedgraph_operation_details(to_fetch, acc = acc, chunksize = chunksize,
                                             return.data.frame = FALSE,
                                             pyjson = pyjson, ...)
    new_missing <- setdiff(to_fetch, as.integer(names(fresh)))
    .write_ops_cache(cache_files$ops, cached_df, fresh)
    .write_missing_ops_cache(cache_files$missing, known_missing, new_missing)
    cached_df <- .read_ops_cache(cache_files$ops)
  }

  if (is.null(cached_df))
    cached_df <- data.frame(operation_id = integer())

  found_ops <- ops[ops %in% cached_df$operation_id]
  df <- cached_df[match(found_ops, cached_df$operation_id), , drop = FALSE]
  if (compute_centroids && return.data.frame)
    df <- add_operation_centroids(df)
  df
}

#' @noRd
.chunkedgraph_ops_cache_files <- function(datastack_name, cache_dir) {
  list(
    ops = file.path(cache_dir, paste0(datastack_name, "_operations.arrow")),
    missing = file.path(cache_dir, paste0(datastack_name, "_missing_ops.rds"))
  )
}

#' @noRd
.read_ops_cache <- function(path) {
  if (is.null(path) || !file.exists(path))
    return(NULL)
  arrow::read_feather(path)
}

#' @noRd
.read_missing_ops_cache <- function(path) {
  if (is.null(path) || !file.exists(path))
    return(integer(0))
  readRDS(path)
}

#' @noRd
.centroid_cols <- c("sink_x", "sink_y", "sink_z", "source_x", "source_y", "source_z")

#' @noRd
.redundant_ops_cache_cols <- c(.centroid_cols, "operation_ts")

#' @noRd
.write_ops_cache <- function(path, existing, fresh_list) {
  if (!length(fresh_list))
    return(invisible(existing))

  fresh_df <- .operation_details_list_to_df(fresh_list)
  fresh_df <- fresh_df[setdiff(colnames(fresh_df), .redundant_ops_cache_cols)]
  combined <- if (is.null(existing)) {
    fresh_df
  } else {
    .rbind_fill_df(existing, fresh_df)
  }
  dir.create(dirname(path), showWarnings = FALSE, recursive = TRUE)
  arrow::write_feather(combined, path)
  invisible(combined)
}

#' @noRd
.write_missing_ops_cache <- function(path, existing, new_missing) {
  all_missing <- unique(c(existing, new_missing))
  dir.create(dirname(path), showWarnings = FALSE, recursive = TRUE)
  saveRDS(all_missing, path)
  invisible(all_missing)
}

#' Populate the on-disk operation cache from an existing data.frame
#'
#' Useful for seeding the cache from previously fetched results.
#'
#' @param df A data.frame of operation details as returned by
#'   [chunkedgraph_operation_details()].
#' @param datastack_name CAVE datastack name.
#' @param cache Cache directory. Defaults to the user cache dir managed by
#'   `rappdirs`.
#' @keywords internal
populate_chunkedgraph_ops_cache <- function(
    df,
    datastack_name,
    cache = rappdirs::user_cache_dir("aedes", appauthor = FALSE)) {
  cache_files <- .chunkedgraph_ops_cache_files(datastack_name, cache)
  existing <- .read_ops_cache(cache_files$ops)
  df <- df[setdiff(colnames(df), .redundant_ops_cache_cols)]
  if (!is.null(existing)) {
    df <- df[!df$operation_id %in% existing$operation_id, , drop = FALSE]
    df <- .rbind_fill_df(existing, df)
  }
  dir.create(dirname(cache_files$ops), showWarnings = FALSE, recursive = TRUE)
  arrow::write_feather(df, cache_files$ops)
  invisible(df)
}

#' @noRd
.rbind_fill_df <- function(x, y) {
  cols <- union(colnames(x), colnames(y))
  for (nm in setdiff(cols, colnames(x)))
    x[[nm]] <- NA
  for (nm in setdiff(cols, colnames(y)))
    y[[nm]] <- NA
  x <- x[cols]
  y <- y[cols]
  rbind(x, y)
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
                                        compute_centroids = FALSE,
                                        cache = rappdirs::user_cache_dir("aedes", appauthor = FALSE),
                                        ...) {
  if (is.null(last))
    last <- last_chunkedgraph_edit(datastack_name)
  chunkedgraph_operation_details(seq_len(last), datastack_name = datastack_name,
                                 compute_centroids = compute_centroids,
                                 cache = cache, ...)
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
