# Answering synapse queries at times after a snapshot.
#
# Only supervoxels are ever mapped to new roots; root ids are never translated
# directly. Changes since the snapshot come from a log of expired/created roots
# (chunkedgraph get_delta_roots), cached per session in chunks.
#
# Two ways to answer a query at time T:
#   head:  advance a per-session in-memory "head" (the snapshot with the rows
#          of every synapse on an expired root updated) to T, then read from it.
#          Cost grows with the number of edits since the head was last advanced;
#          later queries reuse the work.
#   query: update just the rows of this query (new query roots via their
#          leaves, expired partner roots via their supervoxels). Cost grows with
#          the size of the query.
# The cheaper one is chosen from supervoxel counts that DuckDB gives cheaply.
#
# All CAVE access goes through `ctx`, a list of functions:
#   delta_roots(past, future) -> list(old = integer64, new = integer64)
#   rootid(sv, timestamp)     -> integer64 roots for (sorted) supervoxels
#   leaves(root)              -> integer64 supervoxels of one root
#   is_latest(roots, timestamp) -> logical
#   latest_id(roots, timestamp) -> integer64, one per input root
#   now()                     -> POSIXct

#' @importFrom bit64 %in%
NULL



synsnap_tmpname <- function(prefix = "synsnap_")
  paste0(prefix, paste(sample(c(letters, 0:9), 16, TRUE), collapse = ""))

# register a data.frame with duckdb until the calling function exits
synsnap_register <- function(con, df, env = parent.frame()) {
  nm <- synsnap_tmpname("synsnap_r_")
  duckdb::duckdb_register(con, nm, df)
  withr::defer(duckdb::duckdb_unregister(con, nm), envir = env)
  nm
}

i64_union <- function(l)
  unique(do.call(c, c(list(bit64::integer64()), lapply(l, bit64::as.integer64))))

# per-session state for one snapshot: head time, head rows table, root log
synsnap_state <- function(tag, root) {
  key <- paste(normalizePath(root, mustWork = TRUE), tag, sep = "|")
  st <- .synsnap$states[[key]]
  if (is.null(st)) {
    t0 <- synsnap_meta(tag, root)$timestamp
    st <- new.env(parent = emptyenv())
    st$tag <- tag
    st$root <- root
    st$t0 <- t0     # snapshot time
    st$t <- t0      # head time
    st$table <- NULL
    st$log <- list()
    st$log_t <- t0  # end of cached log
    .synsnap$states[[key]] <- st
  }
  st
}

synsnap_state_reset <- function(tag = NULL, root = NULL) {
  keys <- names(.synsnap$states)
  if (!is.null(tag)) {
    k <- paste(normalizePath(root, mustWork = TRUE), tag, sep = "|")
    keys <- keys[keys == k | startsWith(keys, paste0(k, "|"))]
  }
  con <- .synsnap$con
  for (k in keys) {
    tb <- .synsnap$states[[k]]$table
    if (!is.null(tb) && !is.null(con) && DBI::dbIsValid(con))
      DBI::dbExecute(con, paste("DROP TABLE IF EXISTS", tb))
    .synsnap$states[[k]] <- NULL
  }
  invisible(keys)
}

# fetch the root log in steps of at most max_interval seconds
synsnap_fetch_log <- function(from, to, ctx, max_interval = 86400) {
  res <- list()
  while (from < to) {
    te <- min(to, from + max_interval)
    d <- ctx$delta_roots(from, te)
    if (!is.list(d) || !all(c("old", "new") %in% names(d)))
      stop("delta_roots must return a list with old and new")
    res[[length(res) + 1]] <- list(t0 = from, t1 = te,
                                   old = bit64::as.integer64(d$old),
                                   new = bit64::as.integer64(d$new))
    from <- te
  }
  res
}

# roots expired (old) and created (new) between from and to. Extends the
# cached log when `to` is later than its end; gaps at either end of the cached
# chunks are fetched without caching.
synsnap_log_range <- function(st, from, to, ctx) {
  if (to > st$log_t) {
    st$log <- c(st$log, synsnap_fetch_log(st$log_t, to, ctx))
    st$log_t <- to
  }
  ch <- Filter(function(x) x$t0 >= from && x$t1 <= to, st$log)
  ch <- if (!length(ch)) synsnap_fetch_log(from, to, ctx)
  else c(synsnap_fetch_log(from, ch[[1]]$t0, ctx), ch,
         synsnap_fetch_log(ch[[length(ch)]]$t1, to, ctx))
  list(old = i64_union(lapply(ch, `[[`, "old")),
       new = i64_union(lapply(ch, `[[`, "new")))
}

# rbind for data.frames with integer64 columns
rbind_i64 <- function(a, b) {
  l <- lapply(names(a), function(n) c(a[[n]], b[[n]]))
  names(l) <- names(a)
  dplyr::as_tibble(l)
}

# snapshot rows, overridden by head rows when use_head
synsnap_view_sql <- function(st, side = NULL, where = NULL, use_head = TRUE) {
  rows <- synsnap_rows_sql(st$tag, st$root, side = side, where = where)
  if (!use_head || is.null(st$table)) return(rows)
  w <- if (is.null(where)) "" else paste(" WHERE", where)
  sprintf("SELECT id, pre_root, post_root FROM (%s) WHERE id NOT IN (SELECT id FROM %s)
    UNION ALL SELECT id, pre_root, post_root FROM %s%s", rows, st$table, st$table, w)
}

synsnap_static_sql <- function(st)
  synsnap_sql_str(synsnap_path(st$root, file = "static.parquet"))

# Table of head rows touching an expired root, with their supervoxels.
# Returns the table name and the number of supervoxels to look up.
synsnap_changed <- function(st, old, con, env = parent.frame()) {
  if (!length(old)) return(list(table = NULL, nsv = 0))
  exp <- synsnap_register(con, data.frame(root = old), env = env)
  inexp <- function(s) sprintf("%s_root IN (SELECT root FROM %s)", s, exp)
  tb <- synsnap_tmpname("synsnap_chg_")
  DBI::dbExecute(con, sprintf("CREATE TEMP TABLE %s AS
    SELECT c.id, c.pre_root, c.post_root, s.pre_sv, s.post_sv,
      %s AS pre_stale, %s AS post_stale
    FROM (SELECT DISTINCT * FROM (%s UNION ALL %s)) c JOIN %s s USING (id)",
    tb, inexp("c.pre"), inexp("c.post"),
    synsnap_view_sql(st, "pre", inexp("pre")),
    synsnap_view_sql(st, "post", inexp("post")), synsnap_static_sql(st)))
  withr::defer(DBI::dbExecute(con, paste("DROP TABLE IF EXISTS", tb)), envir = env)
  nsv <- DBI::dbGetQuery(con, sprintf("SELECT count(*)::DOUBLE AS n FROM (
    SELECT pre_sv FROM %s WHERE pre_stale UNION SELECT post_sv FROM %s WHERE post_stale)",
    tb, tb))$n
  list(table = tb, nsv = nsv)
}

# look up roots at T for sorted unique supervoxels
synsnap_lookup <- function(sv, T, ctx) {
  sv <- sort(unique(bit64::as.integer64(sv)))
  r <- if (length(sv)) bit64::as.integer64(ctx$rootid(sv, T)) else bit64::integer64()
  if (length(r) != length(sv) || anyNA(r))
    stop("supervoxel lookup failed for ", sum(is.na(r)), " supervoxels")
  data.frame(sv = sv, root = r)
}

# Update the head rows in `chg` to time T
synsnap_advance <- function(st, chg, T, ctx, con) {
  if (!is.null(chg$table)) {
    sv <- DBI::dbGetQuery(con, sprintf("SELECT pre_sv AS sv FROM %s WHERE pre_stale
      UNION SELECT post_sv FROM %s WHERE post_stale", chg$table, chg$table))$sv
    nr <- synsnap_register(con, synsnap_lookup(sv, T, ctx))
    upd <- sprintf("SELECT c.id,
        CASE WHEN c.pre_stale THEN p.root ELSE c.pre_root END AS pre_root,
        CASE WHEN c.post_stale THEN q.root ELSE c.post_root END AS post_root
      FROM %s c LEFT JOIN %s p ON c.pre_sv = p.sv LEFT JOIN %s q ON c.post_sv = q.sv",
      chg$table, nr, nr)
    tb <- synsnap_tmpname("synsnap_head_")
    sql <- if (is.null(st$table))
      sprintf("CREATE TEMP TABLE %s AS %s", tb, upd)
    else sprintf("CREATE TEMP TABLE %s AS SELECT * FROM %s
        WHERE id NOT IN (SELECT id FROM %s) UNION ALL %s",
        tb, st$table, chg$table, upd)
    DBI::dbExecute(con, sql)
    if (!is.null(st$table)) DBI::dbExecute(con, paste("DROP TABLE", st$table))
    st$table <- tb
  }
  st$t <- T
  invisible(st)
}

# A head for snapshot `tag` at time T, for reading every synapse (see
# aedes_synapse_data()). Unlike the head that synsnap_query_at() advances,
# these are fixed in time and kept until synsnap_state_reset(), so lazy tables
# made from them stay valid. One within max_age seconds before T is reused;
# a new one starts from a copy of the advancing head when that is not after T.
# Shares the advancing head's cached log.
synsnap_head_at <- function(tag, root, T, ctx, max_age = 60) {
  st <- synsnap_state(tag, root)
  T <- as.POSIXct(T, tz = "UTC")
  if (as.numeric(T) < as.numeric(st$t0) - 1)
    stop("requested time is before snapshot '", tag, "'")
  if (T < st$t0) T <- st$t0
  prefix <- paste(normalizePath(root, mustWork = TRUE), tag, "t", sep = "|")
  keys <- names(.synsnap$states)
  heads <- .synsnap$states[keys[startsWith(keys, prefix)]]
  age <- as.numeric(T) - vapply(heads, function(h) as.numeric(h$t), numeric(1))
  ok <- age >= 0 & age <= max_age
  if (any(ok)) return(heads[[which(ok)[which.min(age[ok])]]])

  con <- synsnap_con()
  h <- new.env(parent = emptyenv())
  h$tag <- tag
  h$root <- root
  h$t0 <- st$t0
  h$t <- st$t0
  h$table <- NULL
  if (!is.null(st$table) && st$t <= T) {
    h$table <- synsnap_tmpname("synsnap_head_")
    DBI::dbExecute(con, sprintf("CREATE TEMP TABLE %s AS SELECT * FROM %s",
                                h$table, st$table))
    h$t <- st$t
  }
  if (T > h$t) {
    chg <- synsnap_changed(h, synsnap_log_range(st, h$t, T, ctx)$old, con)
    synsnap_advance(h, chg, T, ctx, con)
  }
  .synsnap$states[[paste0(prefix, format(as.numeric(T), nsmall = 3))]] <- h
  h
}

# Rows for query roots q at T, updating only what this query needs.
# `from` is the time of the rows being read (head or snapshot); lg the log since.
synsnap_rows_query <- function(q, side, st, use_head, lg, T, ctx, con) {
  other <- if (side == "pre") "post" else "pre"
  sidecol <- paste0(side, "_root")
  othercol <- paste0(other, "_root")
  fresh <- q[q %in% lg$new & !q %in% lg$old]
  known <- q[!q %in% fresh]
  rows <- if (length(known)) {
    where <- synsnap_where(known, side, con)
    if (!is.null(attr(where, "table")))
      on.exit(duckdb::duckdb_unregister(con, attr(where, "table")), add = TRUE)
    DBI::dbGetQuery(con, synsnap_view_sql(st, side, where, use_head = use_head))
  } else data.frame(id = integer(), pre_root = bit64::integer64(),
                    post_root = bit64::integer64())
  if (length(fresh)) {
    lv <- lapply(fresh, function(r) bit64::as.integer64(ctx$leaves(r)))
    lv <- synsnap_register(con, data.frame(
      q = rep(fresh, lengths(lv)), sv = do.call(c, c(list(bit64::integer64()), lv))))
    fid <- DBI::dbGetQuery(con, sprintf("SELECT s.id, lv.q FROM %s s JOIN %s lv ON s.%s_sv = lv.sv",
                                        synsnap_static_sql(st), lv, side))
    if (nrow(fid)) {
      idt <- synsnap_register(con, fid)
      fr <- DBI::dbGetQuery(con, sprintf("SELECT v.id, v.pre_root, v.post_root, f.q FROM (%s) v JOIN %s f USING (id)",
        synsnap_view_sql(st, NULL, sprintf("id IN (SELECT id FROM %s)", idt), use_head = use_head), idt))
      fr[[sidecol]] <- fr$q
      rows <- rbind_i64(rows, fr[c("id", "pre_root", "post_root")])
    }
  }
  stale <- rows[[othercol]] %in% lg$old
  if (any(stale)) {
    sid <- synsnap_register(con, data.frame(id = rows$id[stale]))
    sv <- DBI::dbGetQuery(con, sprintf("SELECT id, %s_sv AS sv FROM %s WHERE id IN (SELECT id FROM %s)",
                                       other, synsnap_static_sql(st), sid))
    lk <- synsnap_lookup(sv$sv, T, ctx)
    newroot <- lk$root[match(sv$sv, lk$sv)]
    rows[[othercol]][stale] <- newroot[match(rows$id[stale], sv$id)]
  }
  rows
}

# Synapse connection weights for roots on one side at time T (a POSIXct or
# "now"). Returns pre_root, post_root, weight with timestamp/method attributes.
synsnap_query_at <- function(roots, side = c("pre", "post"), tag, root, timestamp,
                             ctx, max_age = 60, f = 0.3, min_sv = 5e4,
                             leaf_cost = 1e4) {
  side <- match.arg(side)
  sidecol <- paste0(side, "_root")
  con <- synsnap_con()
  st <- synsnap_state(tag, root)
  T <- if (identical(timestamp, "now")) {
    tn <- ctx$now()
    if (as.numeric(tn) - as.numeric(st$log_t) <= max_age) st$log_t else tn
  } else as.POSIXct(timestamp, tz = "UTC")
  if (as.numeric(T) < as.numeric(st$t0) - 1)
    stop("requested time is before snapshot '", tag, "'")
  if (T < st$t0) T <- st$t0
  use_head <- T >= st$t
  from <- if (use_head) st$t else st$t0
  lg <- synsnap_log_range(st, from, T, ctx)

  q <- unique(bit64::as.integer64(roots))
  q <- q[!is.na(q) & q != 0]
  # query roots that expired since the snapshot
  expired <- synsnap_log_range(st, st$t0, T, ctx)$old
  bad <- q %in% expired
  if (any(bad))
    q <- unique(c(q[!bad], bit64::as.integer64(ctx$latest_id(q[bad], T))))

  method <- "query"
  if (use_head) {
    chg <- synsnap_changed(st, lg$old, con)
    est_q <- if (chg$nsv > min_sv) {
      nfresh <- sum(q %in% lg$new & !q %in% lg$old)
      where <- synsnap_where(q, side, con)
      if (!is.null(attr(where, "table")))
        on.exit(duckdb::duckdb_unregister(con, attr(where, "table")), add = TRUE)
      other <- if (side == "pre") "post" else "pre"
      exp <- synsnap_register(con, data.frame(root = lg$old))
      DBI::dbGetQuery(con, sprintf("SELECT count(*)::DOUBLE AS n FROM (%s) WHERE %s_root IN (SELECT root FROM %s)",
        synsnap_view_sql(st, side, where), other, exp))$n + leaf_cost * nfresh
    } else 0
    if (chg$nsv <= min_sv || est_q >= f * chg$nsv) {
      synsnap_advance(st, chg, T, ctx, con)
      method <- "head"
      lg <- list(old = bit64::integer64(), new = bit64::integer64())
    }
  }
  counts <- function(q) {
    if (!length(lg$old) && !length(lg$new)) {
      # nothing changed since the rows we read: aggregate in duckdb
      where <- synsnap_where(q, side, con)
      if (!is.null(attr(where, "table")))
        on.exit(duckdb::duckdb_unregister(con, attr(where, "table")), add = TRUE)
      return(dplyr::as_tibble(DBI::dbGetQuery(con, sprintf(
        "SELECT pre_root, post_root, count(*)::INTEGER AS weight FROM (%s)
        GROUP BY pre_root, post_root", synsnap_view_sql(st, side, where, use_head)))))
    }
    rows <- synsnap_rows_query(q, side, st, use_head, lg, T, ctx, con)
    res <- dplyr::count(dplyr::as_tibble(rows[c("pre_root", "post_root")]),
                        .data$pre_root, .data$post_root, name = "weight")
    res$weight <- as.integer(res$weight)
    res
  }
  res <- if (length(q)) counts(q)
  else dplyr::tibble(pre_root = bit64::integer64(), post_root = bit64::integer64(),
                     weight = integer())

  # query roots with no synapses may be out of date ids from before the
  # snapshot; check those with CAVE
  unk <- q[!q %in% res[[sidecol]] & !q %in% lg$new]
  if (length(unk)) {
    il <- as.logical(ctx$is_latest(unk, T))
    if (any(!il)) {
      q2 <- bit64::as.integer64(ctx$latest_id(unk[!il], T))
      q2 <- q2[!q2 %in% q]
      if (length(q2)) res <- rbind_i64(res, counts(q2))
    }
  }
  attr(res, "timestamp") <- T
  attr(res, "method") <- method
  res
}
