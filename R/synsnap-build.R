# Building local synapse snapshots (layout in R/synsnap.R). Used by
# data-raw/synapse-snapshot.R; nothing here is exported. Like R/synsnap.R this
# knows nothing about aedes except the default edgelist column names.
#
# Files are written with zstd level 19: about a third smaller than DuckDB's
# default (level 3) for root id tables and ~15% for static.parquet, while
# queries are barely slower. Writing is slower, but happens once.

# Write the result of `sql` to parquet file `f` via a tmp file, so that a
# partial file never looks finished. `check` is called with SQL reading the
# tmp file before renaming and should stop() if the file is bad.
synsnap_write <- function(con, sql, f, row_group_size = 262144, level = 19,
                          check = NULL) {
  tmp <- paste0(f, ".tmp")
  on.exit(unlink(tmp))
  DBI::dbExecute(con, sprintf(
    "COPY (%s) TO %s (FORMAT parquet, COMPRESSION zstd, COMPRESSION_LEVEL %d,
      ROW_GROUP_SIZE %d)",
    sql, synsnap_sql_str(tmp), as.integer(level), as.integer(row_group_size)))
  if (!is.null(check)) check(sprintf("read_parquet(%s)", synsnap_sql_str(tmp)))
  if (!file.rename(tmp, f)) stop("Could not write ", f, call. = FALSE)
  invisible(f)
}

# Make a data.frame or feather file(s) queryable as a duckdb view. Returns its
# name; unregistered when `env` exits.
synsnap_source <- function(con, x, env = parent.frame()) {
  nm <- paste0("synsnap_src_", paste(sample(letters, 12, TRUE), collapse = ""))
  if (is.data.frame(x)) {
    duckdb::duckdb_register(con, nm, x)
    withr::defer(duckdb::duckdb_unregister(con, nm), envir = env)
  } else {
    arrow::to_duckdb(arrow::open_dataset(x, format = "feather"), con = con,
                     table_name = nm, auto_disconnect = FALSE)
    withr::defer(duckdb::duckdb_unregister_arrow(con, nm), envir = env)
  }
  nm
}

# static.parquet column = source edgelist column, for the 260226_v3 edgelist
synsnap_edgelist_cols <- function() c(
  id = "cleft_segid", pre_sv = "presyn_basin", post_sv = "postsyn_basin",
  pre_x = "presyn_x", pre_y = "presyn_y", pre_z = "presyn_z",
  post_x = "postsyn_x", post_y = "postsyn_y", post_z = "postsyn_z",
  size = "size")

# Write <root>/static.parquet (sorted by id) from a synapse edgelist: a
# data.frame or feather file(s), with `columns` mapping output to input names.
synsnap_build_static <- function(edgelist, root, columns = synsnap_edgelist_cols(),
                                 overwrite = FALSE) {
  f <- file.path(synsnap_path(root), "static.parquet")
  if (file.exists(f) && !overwrite)
    stop("static.parquet already exists in ", root, call. = FALSE)
  con <- synsnap_con()
  src <- synsnap_source(con, edgelist)
  sel <- paste(sprintf("%s AS %s", columns, names(columns)), collapse = ", ")
  synsnap_write(con, sprintf("SELECT %s FROM %s ORDER BY id", sel, src), f,
                row_group_size = 1048576, check = function(written) {
    n <- DBI::dbGetQuery(con, sprintf(
      "SELECT count(*) - count(DISTINCT id) AS n FROM %s", written))$n
    if (n > 0) stop(n, " duplicate synapse ids in edgelist", call. = FALSE)
  })
}

# write meta.json last: its presence marks a finished snapshot
synsnap_write_meta <- function(root, tag, meta) {
  if (!is.null(meta$timestamp))
    meta$timestamp <- format(synsnap_parse_time(meta$timestamp),
                             "%Y-%m-%d %H:%M:%OS6 UTC", tz = "UTC")
  jsonlite::write_json(meta, synsnap_path(root, tag, "meta.json"),
                       auto_unbox = TRUE, pretty = TRUE, null = "null")
}

# by_pre.parquet (and by_post.parquet if wanted) for a full snapshot, from
# SQL giving pre_root, post_root, id
synsnap_write_ids <- function(con, sql, root, tag, by_post = FALSE,
                              check = NULL) {
  by_pre <- synsnap_path(root, tag, "by_pre.parquet")
  synsnap_write(con, sprintf(
    "SELECT pre_root, post_root, id FROM (%s) ORDER BY pre_root, id", sql),
    by_pre, check = check)
  if (by_post)
    synsnap_write(con, sprintf(
      "SELECT post_root, pre_root, id FROM %s ORDER BY post_root, id",
      synsnap_sql_str(by_pre)), synsnap_path(root, tag, "by_post.parquet"))
}

# Full snapshot `tag` at `timestamp` from a supervoxel -> root map (a
# data.frame or feather file(s) with columns sv, root_id) that covers every
# pre_sv and post_sv in static.parquet.
synsnap_build <- function(tag, svmap, timestamp, root, by_post = FALSE) {
  if (file.exists(file.path(synsnap_path(root), tag, "meta.json")))
    stop("Synapse snapshot '", tag, "' already exists", call. = FALSE)
  dir.create(file.path(synsnap_path(root), tag), showWarnings = FALSE)
  con <- synsnap_con()
  src <- synsnap_source(con, svmap)
  DBI::dbExecute(con, sprintf(
    "CREATE OR REPLACE TEMP TABLE synsnap_svmap AS SELECT DISTINCT sv, root_id FROM %s",
    src))
  on.exit(DBI::dbExecute(con, "DROP TABLE IF EXISTS synsnap_svmap"), add = TRUE)
  dup <- DBI::dbGetQuery(con,
    "SELECT count(*) - count(DISTINCT sv) AS n FROM synsnap_svmap")$n
  if (dup > 0) stop(dup, " supervoxels map to more than one root", call. = FALSE)
  sql <- sprintf("SELECT p.root_id AS pre_root, q.root_id AS post_root, s.id
    FROM %s s LEFT JOIN synsnap_svmap p ON s.pre_sv = p.sv
    LEFT JOIN synsnap_svmap q ON s.post_sv = q.sv",
    synsnap_sql_str(synsnap_path(root, file = "static.parquet")))
  synsnap_write_ids(con, sql, root, tag, by_post = by_post, check = function(written) {
    n <- DBI::dbGetQuery(con, sprintf("SELECT count(*) AS n FROM %s
      WHERE pre_root IS NULL OR post_root IS NULL", written))$n
    if (n > 0)
      stop(n, " synapses have a supervoxel missing from svmap", call. = FALSE)
  })
  synsnap_write_meta(root, tag, list(tag = tag, timestamp = timestamp, parent = NULL))
  invisible(tag)
}

# Turn delta snapshot `tag` into a full one, to base later deltas on
synsnap_rebase <- function(tag, root, by_post = FALSE) {
  m <- synsnap_meta(tag, root)
  if (is.na(m$base)) return(invisible(tag))
  con <- synsnap_con()
  synsnap_write_ids(con, synsnap_rows_sql(tag, root), root, tag, by_post = by_post)
  # the delta is ignored once meta.json no longer names a base
  synsnap_write_meta(root, tag, list(tag = tag, timestamp = m$timestamp,
                                     parent = if (is.null(m$parent)) m$base else m$parent))
  file.remove(synsnap_path(root, tag, "delta.parquet"))
  invisible(tag)
}

# Delta snapshot `tag` at `timestamp` from snapshot `from`, using CAVE access
# in `ctx` (see R/synsnap-live.R). Only synapses on roots that expired since
# `from` are looked up. The delta is always against a full snapshot: `from`, or
# `from`'s base when `from` is itself a delta. Rows that are the same as the
# base are dropped, so edits that are later undone do not grow the delta.
synsnap_update <- function(from, tag, timestamp, root, ctx) {
  if (file.exists(file.path(synsnap_path(root), tag, "meta.json")))
    stop("Synapse snapshot '", tag, "' already exists", call. = FALSE)
  m <- synsnap_meta(from, root)
  base <- if (is.na(m$base)) from else m$base
  T <- as.POSIXct(timestamp, tz = "UTC")
  if (T < m$timestamp)
    stop("timestamp is before snapshot '", from, "'", call. = FALSE)
  con <- synsnap_con()
  # a private head state for `from`, so session states are left alone
  st <- new.env(parent = emptyenv())
  st$tag <- from
  st$root <- root
  st$t0 <- st$t <- st$log_t <- m$timestamp
  st$table <- NULL
  st$log <- list()
  on.exit(if (!is.null(st$table))
    DBI::dbExecute(con, paste("DROP TABLE IF EXISTS", st$table)), add = TRUE)
  lg <- synsnap_log_range(st, m$timestamp, T, ctx)
  synsnap_advance(st, synsnap_changed(st, lg$old, con), T, ctx, con)

  # rows of `from` that differ from the base, updated by the head rows
  rows <- if (is.null(st$table)) {
    if (is.na(m$base)) sprintf("SELECT id, pre_root, post_root FROM %s WHERE false",
                               synsnap_sql_str(synsnap_ids_file(root, base)))
    else sprintf("SELECT id, pre_root, post_root FROM %s",
                 synsnap_sql_str(synsnap_path(root, from, "delta.parquet")))
  } else if (is.na(m$base)) sprintf("SELECT id, pre_root, post_root FROM %s", st$table)
  else sprintf("SELECT id, pre_root, post_root FROM %s WHERE id NOT IN (SELECT id FROM %s)
    UNION ALL SELECT id, pre_root, post_root FROM %s",
    synsnap_sql_str(synsnap_path(root, from, "delta.parquet")), st$table, st$table)
  sql <- sprintf("SELECT d.id, d.pre_root, d.post_root FROM (%s) d
    ANTI JOIN %s b ON d.id = b.id AND d.pre_root = b.pre_root
      AND d.post_root = b.post_root
    ORDER BY d.id", rows, synsnap_sql_str(synsnap_ids_file(root, base)))
  dir.create(file.path(synsnap_path(root), tag), showWarnings = FALSE)
  synsnap_write(con, sql, synsnap_path(root, tag, "delta.parquet"))
  synsnap_write_meta(root, tag, list(tag = tag, timestamp = T, base = base,
                                     parent = from))
  invisible(tag)
}
