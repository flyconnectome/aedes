# Dataset-agnostic access to a local synapse snapshot folder.
#
# Layout (see aedes_use_snapshot() for the user-facing description):
#   <root>/static.parquet      id, pre_sv, post_sv, xyz, size; sorted by id
#   <root>/<tag>/meta.json     tag, timestamp, base (NULL for a full snapshot),
#                              parent, kind, version. Written last: its presence
#                              marks a finished snapshot.
#   <root>/<tag>/by_pre.parquet
#                              full: pre_root, post_root, id; sorted by
#                              pre_root, id
#   <root>/<tag>/by_post.parquet
#                              optional: the same rows sorted by post_root, id.
#                              Only speeds up small input queries.
#   <root>/<tag>/log.parquet   checkpoint: id, t, pre_root, post_root, old_pre,
#                              old_post for synapses whose roots changed since
#                              the `parent` snapshot; sorted by id. Only a side
#                              that changed is filled in (the others are NULL);
#                              old_* are its roots at the parent.
#
# A checkpoint's rows are those of its full `base` updated by the logs of every
# checkpoint between them (its chain of parents), taking the latest value of
# each side of each synapse. Root ids are never reused, so each log row is a
# fact ("at time t this side had root r") whichever chain it came from.
# Full snapshots made with synsnap_rebase() keep their log.parquet, which is
# then not read. Older checkpoints instead have <tag>/delta.parquet (all rows
# that differ from the base); synsnap_convert_deltas() turns them into logs.
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
  if (!dir.exists(root))
    stop("No synapse snapshot folder at ", root, call. = FALSE)
  do.call(file.path, as.list(c(normalizePath(root, mustWork = TRUE), tag, file)))
}

# One in-memory duckdb connection per session; parquet files are read by path.
# BIGINT comes back as integer64, never double. The aedes.duckdb_threads option
# limits the threads it uses (default: one per core).
synsnap_con <- function() {
  synsnap_check()
  con <- .synsnap$con
  if (is.null(con) || !DBI::dbIsValid(con)) {
    # shared_home (duckdb >= 1.5.5) avoids a prompt about extension storage
    drv <- if ("shared_home" %in% names(formals(duckdb::duckdb)))
      duckdb::duckdb(shared_home = FALSE) else duckdb::duckdb()
    con <- DBI::dbConnect(drv, bigint = "integer64")
    tmp <- file.path(tempdir(), "synsnap_duckdb")
    dir.create(tmp, showWarnings = FALSE)
    DBI::dbExecute(con, sprintf("SET temp_directory = '%s'", tmp))
    threads <- getOption("aedes.duckdb_threads")
    if (!is.null(threads))
      DBI::dbExecute(con, sprintf("SET threads = %d", as.integer(threads)))
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

# Times are kept to whole milliseconds, as CAVE gives them. Rounding down to
# the ms tolerates 1 microsecond of floating point error.
synsnap_floor_ms <- function(x)
  .POSIXct(floor(as.numeric(x) * 1000 + 1e-3) / 1000, tz = "UTC")

# Exact text of a time to the microsecond, which python (and so CAVE) rounds
# to; format(x, "%OS6") truncates, so can be 1 microsecond early.
synsnap_format_time <- function(x) {
  us <- round(as.numeric(x) * 1e6)
  paste0(format(.POSIXct(us %/% 1e6, tz = "UTC"), "%Y-%m-%d %H:%M:%S", tz = "UTC"),
         sprintf(".%06d UTC", as.integer(us %% 1e6)))
}

synsnap_meta <- function(tag, root) {
  f <- synsnap_path(root, tag, "meta.json")
  if (!file.exists(f))
    stop("No synapse snapshot '", tag, "' in ", root, call. = FALSE)
  m <- jsonlite::read_json(f, simplifyVector = TRUE)
  if (is.null(m$base)) m$base <- NA_character_
  if (is.null(m$parent)) m$parent <- if (is.na(m$base)) NA_character_ else m$base
  if (is.null(m$kind)) m$kind <- NA_character_
  m$timestamp <- synsnap_parse_time(m$timestamp)
  # a checkpoint from before logs, which synsnap_convert_deltas() can convert
  m$old_delta <- !is.na(m$base) &&
    !file.exists(synsnap_path(root, tag, "log.parquet"))
  m
}

synsnap_is_delta <- function(tag, root) !is.na(synsnap_meta(tag, root)$base)

# data.frame of usable snapshots, oldest first. Checkpoints whose chain of
# parents back to their base is incomplete, or that still need converting
# (`old_delta`), are left out unless `all`.
synsnap_tags <- function(root, all = FALSE) {
  metas <- Sys.glob(file.path(synsnap_path(root), "*", "meta.json"))
  tags <- basename(dirname(metas))
  if (!length(tags))
    return(data.frame(tag = character(), timestamp = synsnap_parse_time(character()),
                      base = character(), parent = character(), kind = character(),
                      usable = logical()))
  mm <- lapply(tags, synsnap_meta, root = root)
  str <- function(f) vapply(mm, function(m) as.character(m[[f]]), "")
  df <- data.frame(
    tag = tags,
    timestamp = do.call(c, lapply(mm, `[[`, "timestamp")),
    base = str("base"), parent = str("parent"), kind = str("kind"),
    old_delta = vapply(mm, `[[`, FALSE, "old_delta"))
  df <- df[order(df$timestamp), , drop = FALSE]
  # parents are always older, so one pass in time order settles each chain
  ok <- stats::setNames(logical(nrow(df)), df$tag)
  for (i in seq_len(nrow(df))) ok[i] <- is.na(df$base[i]) ||
    (!df$old_delta[i] && isTRUE(ok[df$parent[i]]) &&
       identical(df$base[match(df$parent[i], df$tag)],
                 if (df$parent[i] == df$base[i]) NA_character_ else df$base[i]))
  df$usable <- unname(ok)
  df$old_delta <- NULL
  rownames(df) <- NULL
  if (all) df else df[df$usable, , drop = FALSE]
}

# Tags of the checkpoints from `tag` back to (not including) its base, newest
# first; character(0) for a full snapshot
synsnap_chain <- function(tag, root) {
  m <- synsnap_meta(tag, root)
  chain <- character()
  while (!is.na(m$base)) {
    if (m$old_delta)
      stop("Synapse snapshot '", m$tag, "' is in an old format; convert it ",
           "with aedes:::synsnap_convert_deltas()", call. = FALSE)
    chain <- c(chain, m$tag)
    if (identical(m$parent, m$base)) break
    if (!file.exists(synsnap_path(root, m$parent, "meta.json")))
      stop("Synapse snapshot '", tag, "' needs snapshot '", m$parent,
           "', which is missing", call. = FALSE)
    m2 <- synsnap_meta(m$parent, root)
    if (!identical(m2$base, m$base))
      stop("Synapse snapshot '", m$tag, "' has parent '", m$parent,
           "' with a different base", call. = FALSE)
    m <- m2
  }
  chain
}

synsnap_latest <- function(root) {
  tags <- synsnap_tags(root)
  if (!nrow(tags)) stop("No synapse snapshots in ", root, call. = FALSE)
  tags$tag[nrow(tags)]
}

# newest snapshot at or before `when` (a time, or "now" for the newest
# snapshot), allowing `tol` seconds for rounding; NULL if there is none. With
# `locals = FALSE`, local checkpoints only count at `when` itself: they are
# made without waiting for late edits to become visible, so anything worked
# out for a later time should start from a published (or full) snapshot.
synsnap_at <- function(root, when, tol = 1, locals = TRUE) {
  tags <- synsnap_tags(root)
  if (!identical(when, "now"))
    tags <- tags[as.numeric(tags$timestamp) <= as.numeric(when) + tol, , drop = FALSE]
  if (!locals) {
    exact <- if (identical(when, "now")) FALSE
      else as.numeric(when) - as.numeric(tags$timestamp) <= tol
    tags <- tags[!(tags$kind %in% "local" & !is.na(tags$base)) | exact, , drop = FALSE]
  }
  if (nrow(tags)) tags$tag[nrow(tags)]
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
# groups. `where` may only refer to pre_root and post_root.
synsnap_rows_sql <- function(tag, root, side = NULL, where = NULL) {
  w <- function(x) if (is.null(where)) "" else paste(x, where)
  cols <- "id, pre_root, post_root"
  m <- synsnap_meta(tag, root)
  if (is.na(m$base))
    return(sprintf("SELECT %s FROM %s%s", cols,
                   synsnap_sql_str(synsnap_ids_file(root, tag, side)), w(" WHERE")))
  base <- synsnap_sql_str(synsnap_ids_file(root, m$base, side))
  logs <- file.path(synsnap_path(root), synsnap_chain(tag, root), "log.parquet")
  # latest value of each changed side
  fold <- sprintf("SELECT id,
      arg_max(pre_root, t) FILTER (WHERE pre_root IS NOT NULL) AS pre_root,
      arg_max(post_root, t) FILTER (WHERE post_root IS NOT NULL) AS post_root
    FROM read_parquet([%s]) GROUP BY id",
    paste(synsnap_sql_str(logs), collapse = ", "))
  # base rows matching `where` before or after the changes
  b <- if (is.null(where)) base
  else sprintf("(SELECT %s FROM %s WHERE %s UNION SELECT %s FROM %s
      WHERE id IN (SELECT id FROM synsnap_f WHERE %s))",
      cols, base, where, cols, base, where)
  # a plain SELECT (no top-level WITH), so callers can UNION it
  sprintf("SELECT %s FROM (WITH synsnap_f AS (%s)
    SELECT b.id,
      coalesce(f.pre_root, b.pre_root) AS pre_root,
      coalesce(f.post_root, b.post_root) AS post_root
    FROM %s b LEFT JOIN synsnap_f f USING (id))%s", cols, fold, b, w(" WHERE"))
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
synsnap_tbl <- function(tag, root, side = NULL, static = FALSE,
                        rows = synsnap_rows_sql(tag, root, side = side)) {
  con <- synsnap_con()
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
