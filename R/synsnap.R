# Dataset-agnostic access to a local synapse snapshot folder.
#
# Layout (see aedes_synapse_snapshot() for the user-facing description):
#   <root>/static.parquet      id, pre_sv, post_sv, xyz, size; sorted by id
#   <root>/<tag>/meta.json     tag, timestamp, base (NULL for a full snapshot)
#   <root>/<tag>/by_pre.parquet
#                              full: pre_root, post_root, id; sorted by
#                              pre_root, id
#   <root>/<tag>/by_post.parquet
#                              optional: the same rows sorted by post_root, id.
#                              Only speeds up small input queries.
#   <root>/<tag>/delta.parquet delta: rows that differ from full snapshot `base`
#
# Older snapshots also have <tag>/ids.parquet (sorted by id); it is not read.
#
# Nothing here knows about aedes: every function takes the snapshot `root`
# folder and `tag` explicitly.

.synsnap <- new.env(parent = emptyenv())
.synsnap$states <- list()

synsnap_check <- function() {
  pkgs <- c("duckdb", "DBI", "dbplyr", "jsonlite")
  missing <- pkgs[!sapply(pkgs, requireNamespace, quietly = TRUE)]
  if (length(missing))
    stop("Local synapse queries need the following packages: ",
         paste(missing, collapse = ", "), call. = FALSE)
}

synsnap_path <- function(root, tag = NULL, file = NULL) {
  if (is.null(root) || !nzchar(root))
    stop("No synapse snapshot folder specified", call. = FALSE)
  do.call(file.path, as.list(c(normalizePath(root, mustWork = TRUE), tag, file)))
}

# One in-memory duckdb connection per session; parquet files are read by path.
# BIGINT comes back as integer64, never double.
synsnap_con <- function() {
  synsnap_check()
  con <- .synsnap$con
  if (is.null(con) || !DBI::dbIsValid(con)) {
    con <- DBI::dbConnect(duckdb::duckdb(shared_home = FALSE),
                          bigint = "integer64")
    tmp <- file.path(tempdir(), "synsnap_duckdb")
    dir.create(tmp, showWarnings = FALSE)
    DBI::dbExecute(con, sprintf("SET temp_directory = '%s'", tmp))
    .synsnap$con <- con
    reg.finalizer(.synsnap, function(e) {
      if (!is.null(e$con) && DBI::dbIsValid(e$con))
        DBI::dbDisconnect(e$con, shutdown = TRUE)
    }, onexit = TRUE)
  }
  con
}

synsnap_parse_time <- function(x) {
  as.POSIXct(x, tz = "UTC",
             tryFormats = c("%Y-%m-%d %H:%M:%OS", "%Y-%m-%dT%H:%M:%OS"))
}

synsnap_meta <- function(tag, root) {
  f <- synsnap_path(root, tag, "meta.json")
  if (!file.exists(f))
    stop("No synapse snapshot '", tag, "' in ", root, call. = FALSE)
  m <- jsonlite::read_json(f, simplifyVector = TRUE)
  if (is.null(m$base)) m$base <- NA_character_
  m$timestamp <- synsnap_parse_time(m$timestamp)
  m
}

synsnap_is_delta <- function(tag, root) !is.na(synsnap_meta(tag, root)$base)

# data.frame of available snapshots, oldest first
synsnap_tags <- function(root) {
  metas <- Sys.glob(file.path(synsnap_path(root), "*", "meta.json"))
  tags <- basename(dirname(metas))
  if (!length(tags))
    return(data.frame(tag = character(), timestamp = synsnap_parse_time(character()),
                      base = character()))
  mm <- lapply(tags, synsnap_meta, root = root)
  df <- data.frame(
    tag = tags,
    timestamp = do.call(c, lapply(mm, `[[`, "timestamp")),
    base = vapply(mm, function(m) as.character(m$base), ""))
  df[order(df$timestamp), , drop = FALSE]
}

synsnap_latest <- function(root) {
  tags <- synsnap_tags(root)
  if (!nrow(tags)) stop("No synapse snapshots in ", root, call. = FALSE)
  tags$tag[nrow(tags)]
}

synsnap_sql_str <- function(x) paste0("'", gsub("'", "''", x), "'")

# ids as SQL integer literals without going through double
synsnap_sql_ids <- function(x)
  paste(as.character(bit64::as.integer64(x)), collapse = ",")

# root id file of a full snapshot to read for `side`: by_post.parquet for
# "post" when the snapshot has one, otherwise by_pre.parquet
synsnap_ids_file <- function(root, tag, side = NULL) {
  if (identical(side, "post")) {
    f <- synsnap_path(root, tag, "by_post.parquet")
    if (file.exists(f)) return(f)
  }
  synsnap_path(root, tag, "by_pre.parquet")
}

# SQL giving id, pre_root, post_root for a snapshot. With `side`, reads a copy
# sorted by that root if there is one, so that a `where` on it prunes row
# groups.
synsnap_rows_sql <- function(tag, root, side = NULL, where = NULL) {
  w <- if (is.null(where)) "" else paste(" WHERE", where)
  cols <- "id, pre_root, post_root"
  m <- synsnap_meta(tag, root)
  if (is.na(m$base))
    return(sprintf("SELECT %s FROM %s%s", cols,
                   synsnap_sql_str(synsnap_ids_file(root, tag, side)), w))
  d <- synsnap_sql_str(synsnap_path(root, tag, "delta.parquet"))
  sprintf("SELECT %s FROM %s%s%s id NOT IN (SELECT id FROM %s)
    UNION ALL SELECT %s FROM %s%s",
    cols, synsnap_sql_str(synsnap_ids_file(root, m$base, side)), w,
    if (is.null(where)) " WHERE" else " AND", d, cols, d, w)
}

# restrict to query roots: literal IN list for small queries, otherwise a
# registered table (faster above a few thousand ids)
synsnap_where <- function(roots, side, con) {
  roots <- unique(bit64::as.integer64(roots))
  if (length(roots) <= 5000)
    return(sprintf("%s_root IN (%s)", side, synsnap_sql_ids(roots)))
  nm <- paste0("synsnap_q_", paste(sample(letters, 12, TRUE), collapse = ""))
  duckdb::duckdb_register(con, nm, data.frame(root = roots))
  structure(sprintf("%s_root IN (SELECT root FROM %s)", side, nm), table = nm)
}

# Synapses (partners = FALSE) or connection weights (partners = TRUE) for
# roots on one side ("pre" = their outputs, "post" = their inputs)
synsnap_query <- function(roots, side = c("pre", "post"), tag, root,
                          partners = TRUE, static = FALSE) {
  side <- match.arg(side)
  con <- synsnap_con()
  where <- synsnap_where(roots, side, con)
  if (!is.null(attr(where, "table")))
    on.exit(duckdb::duckdb_unregister(con, attr(where, "table")), add = TRUE)
  rows <- synsnap_rows_sql(tag, root, side = side, where = where)
  sql <- if (partners)
    sprintf("SELECT pre_root, post_root, count(*)::INTEGER AS weight FROM (%s)
      GROUP BY pre_root, post_root", rows)
  else if (static)
    sprintf("SELECT b.pre_root, b.post_root, s.* FROM (%s) b JOIN %s s USING (id)
      ORDER BY s.id", rows, synsnap_sql_str(synsnap_path(root, file = "static.parquet")))
  else sprintf("%s ORDER BY id", rows)
  dplyr::as_tibble(DBI::dbGetQuery(con, sql))
}

# lazy dbplyr table of all synapses in a snapshot
synsnap_tbl <- function(tag, root, side = NULL, static = FALSE) {
  con <- synsnap_con()
  rows <- synsnap_rows_sql(tag, root, side = side)
  if (static)
    rows <- sprintf("SELECT b.pre_root, b.post_root, s.* FROM (%s) b JOIN %s s USING (id)",
                    rows, synsnap_sql_str(synsnap_path(root, file = "static.parquet")))
  dplyr::tbl(con, dplyr::sql(rows))
}

# Partner summary in the fafbseg::flywire_partner_summary format: columns
# query, post_id (outputs) or pre_id (inputs), weight; character ids.
# With a timestamp (POSIXct or "now") and ctx, answers at that time (see
# synsnap_query_at, which gets `...`); otherwise at the snapshot time.
synsnap_partner_summary <- function(roots, partners = c("outputs", "inputs"),
                                    tag, root, threshold = 0,
                                    remove_autapses = TRUE,
                                    timestamp = NULL, ctx = NULL, ...) {
  partners <- match.arg(partners)
  roots <- bit64::as.integer64(roots)
  roots <- roots[!is.na(roots) & roots != 0]
  side <- if (partners == "outputs") "pre" else "post"
  other <- if (partners == "outputs") "post" else "pre"
  res <- if (!is.null(timestamp))
    synsnap_query_at(roots, side = side, tag = tag, root = root,
                     timestamp = timestamp, ctx = ctx, ...)
  else if (length(roots)) synsnap_query(roots, side = side, tag = tag, root = root)
  else dplyr::tibble(pre_root = bit64::integer64(), post_root = bit64::integer64(),
                      weight = integer())
  ts <- attr(res, "timestamp")
  method <- attr(res, "method")
  q <- res[[paste0(side, "_root")]]
  p <- res[[paste0(other, "_root")]]
  keep <- p != 0 & res$weight > threshold
  if (remove_autapses) keep <- keep & p != q
  res <- dplyr::tibble(query = as.character(q[keep]),
                        partner = as.character(p[keep]),
                        weight = res$weight[keep])
  colnames(res)[2] <- paste0(other, "_id")
  res <- dplyr::arrange(res, dplyr::desc(.data$weight))
  attr(res, "snapshot") <- tag
  attr(res, "timestamp") <- if (is.null(ts)) synsnap_meta(tag, root)$timestamp else ts
  if (!is.null(method)) attr(res, "method") <- method
  res
}
