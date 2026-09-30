# Offline tests on a small synthetic snapshot: full tag "s1" and delta "s2".
# layout "one" (by_pre only) and "both" (plus by_post) are made by the build
# functions; "old" also has ids.parquet, as written before those existed.
make_snapshot <- function(root, layout = c("one", "both", "old")) {
  layout <- match.arg(layout)
  con <- synsnap_con()
  i64 <- bit64::as.integer64
  dir.create(file.path(root, "s2"), recursive = TRUE)
  # roots 10, 20, 30; 0 = no root
  ids <- data.frame(
    id = 1:10,
    pre_root = i64(c(10, 10, 10, 10, 20, 20, 30, 10, 0, 30)),
    post_root = i64(c(20, 20, 20, 30, 10, 10, 10, 10, 10, 0)))
  static <- data.frame(id = ids$id, pre_sv = i64(ids$id + 100),
                       post_sv = i64(ids$id + 200), size = 5L)
  # at s2 root 30 was split: synapses 4 and 7 now on root 40
  delta <- data.frame(id = c(4L, 7L), pre_root = i64(c(10, 40)),
                      post_root = i64(c(40, 10)))
  write_pq <- function(df, f, order) {
    duckdb::duckdb_register(con, "tmpdf", df)
    on.exit(duckdb::duckdb_unregister(con, "tmpdf"))
    DBI::dbExecute(con, sprintf("COPY (SELECT * FROM tmpdf ORDER BY %s) TO '%s' (FORMAT parquet)",
                                order, file.path(root, f)))
  }
  t1 <- "2026-01-01 00:00:00 UTC"
  if (layout == "old") {
    dir.create(file.path(root, "s1"))
    write_pq(static, "static.parquet", "id")
    write_pq(ids, "s1/ids.parquet", "id")
    write_pq(ids[c("pre_root", "post_root", "id")], "s1/by_pre.parquet", "pre_root, id")
    write_pq(ids[c("post_root", "pre_root", "id")], "s1/by_post.parquet", "post_root, id")
    jsonlite::write_json(list(tag = "s1", timestamp = t1),
                         file.path(root, "s1", "meta.json"), auto_unbox = TRUE)
  } else {
    synsnap_build_static(static, root, columns = setNames(names(static), names(static)))
    svmap <- data.frame(sv = c(static$pre_sv, static$post_sv),
                        root_id = c(ids$pre_root, ids$post_root))
    synsnap_build("s1", svmap, t1, root, by_post = layout == "both")
  }
  write_pq(delta, "s2/delta.parquet", "id")
  jsonlite::write_json(list(tag = "s2", timestamp = "2026-01-02 12:00:00.5 UTC",
                            base = "s1", parent = "s1"),
                       file.path(root, "s2", "meta.json"), auto_unbox = TRUE)
  root
}

skip_if_no_duckdb <- function() {
  for (p in c("duckdb", "DBI", "dbplyr", "jsonlite")) skip_if_not_installed(p)
}

# A fake CAVE world for snapshot "s1" (see make_snapshot): supervoxels are
# pre_sv = id + 100, post_sv = id + 200. Edits after the snapshot time t0:
#   +1h   root 30 split -> 40 (svs 107, 204) and 41 (sv 110)
#   +2h   roots 20 and 40 merge -> 50
#   +2.5h 41 -> 42, +2.6h 42 -> 43 (42 is transient)
fake_world <- function(t0 = as.POSIXct("2026-01-01", tz = "UTC")) {
  i64 <- bit64::as.integer64
  sv <- i64(c(101:110, 201:210))
  base <- i64(c(10, 10, 10, 10, 20, 20, 30, 10, 0, 30,
                20, 20, 20, 30, 10, 10, 10, 10, 10, 0))
  h <- 3600
  events <- list(
    list(t = t0 + h, old = 30, new = c(40, 41),
         sv = c(107, 204, 110), root = c(40, 40, 41)),
    list(t = t0 + 2 * h, old = c(20, 40), new = 50,
         sv = c(201, 202, 203, 105, 106, 107, 204), root = rep(50, 7)),
    list(t = t0 + 2.5 * h, old = 41, new = 42, sv = 110, root = 42),
    list(t = t0 + 2.6 * h, old = 42, new = 43, sv = 110, root = 43))
  map_at <- function(T) {
    m <- base
    for (e in events) if (e$t <= T) m[match(i64(e$sv), sv)] <- i64(e$root)
    m
  }
  created <- function(r) {
    for (e in events) if (r %in% e$new) return(e$t)
    t0
  }
  env <- new.env()
  env$calls <- list(delta_roots = 0L, rootid = 0L, leaves = 0L, is_latest = 0L,
                    latest_id = 0L)
  env$now <- t0 + 3 * h
  count <- function(f) env$calls[[f]] <- env$calls[[f]] + 1L
  env$ctx <- list(
    delta_roots = function(past, future) {
      count("delta_roots")
      ee <- Filter(function(e) e$t > past && e$t <= future, events)
      list(old = i64(unlist(lapply(ee, `[[`, "old"))),
           new = i64(unlist(lapply(ee, `[[`, "new"))))
    },
    rootid = function(x, timestamp) {
      count("rootid")
      map_at(timestamp)[match(x, sv)]
    },
    leaves = function(r) {
      count("leaves")
      sv[map_at(created(as.numeric(as.character(r)))) == r]
    },
    is_latest = function(r, timestamp) {
      count("is_latest")
      r %in% map_at(timestamp)
    },
    latest_id = function(r, timestamp) {
      count("latest_id")
      m <- map_at(timestamp)
      do.call(c, lapply(r, function(x) {
        s <- sv[map_at(created(as.numeric(as.character(x)))) == x]
        tt <- table(as.character(m[match(s, sv)]))
        i64(names(tt)[which.max(tt)])
      }))
    },
    now = function() env$now)
  # brute force truth: weights for roots q on one side at T
  env$truth <- function(q, side, T) {
    m <- map_at(T)
    pre <- m[match(i64(100 + 1:10), sv)]
    post <- m[match(i64(200 + 1:10), sv)]
    d <- dplyr::tibble(pre_root = pre, post_root = post)
    d <- d[d[[paste0(side, "_root")]] %in% i64(q), ]
    dplyr::count(d, .data$pre_root, .data$post_root, name = "weight")
  }
  env
}

# compare a synsnap_query_at result with the truth, ignoring order
expect_same_counts <- function(res, truth) {
  key <- function(d) sort(paste(d$pre_root, d$post_root, d$weight))
  expect_equal(key(res), key(truth))
}
