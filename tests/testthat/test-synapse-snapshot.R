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

test_that("snapshot metadata", {
  skip_if_no_duckdb()
  root <- make_snapshot(withr::local_tempdir())
  tags <- synsnap_tags(root)
  expect_equal(tags$tag, c("s1", "s2"))
  expect_equal(tags$base, c(NA, "s1"))
  expect_equal(synsnap_latest(root), "s2")
  expect_equal(as.numeric(synsnap_meta("s2", root)$timestamp),
               as.numeric(as.POSIXct("2026-01-02 12:00:00.5", tz = "UTC")))
  expect_error(synsnap_meta("nope", root), "No synapse snapshot")
})

test_that("synsnap_partner_summary on full and delta snapshots", {
  skip_if_no_duckdb()
  root <- make_snapshot(withr::local_tempdir())

  out <- synsnap_partner_summary(10, "outputs", tag = "s1", root = root)
  expect_named(out, c("query", "post_id", "weight"))
  expect_type(out$query, "character")
  # autapse (10->10) and nothing else dropped; sorted by weight
  expect_equal(out$post_id, c("20", "30"))
  expect_equal(out$weight, c(3L, 1L))
  expect_equal(attr(out, "snapshot"), "s1")

  inp <- synsnap_partner_summary(10, "inputs", tag = "s1", root = root)
  expect_named(inp, c("query", "pre_id", "weight"))
  # root 0 partner dropped
  expect_equal(inp$pre_id, c("20", "30"))
  expect_equal(inp$weight, c(2L, 1L))

  inp2 <- synsnap_partner_summary(10, "inputs", tag = "s1", root = root,
                                  remove_autapses = FALSE, threshold = 1)
  expect_equal(inp2$pre_id, "20")

  # delta: synapses 4 and 7 moved from root 30 to root 40
  out2 <- synsnap_partner_summary(10, "outputs", tag = "s2", root = root)
  expect_equal(out2$post_id, c("20", "40"))
  expect_equal(synsnap_partner_summary(30, "inputs", tag = "s2", root = root)$pre_id,
               character())
  in40 <- synsnap_partner_summary(40, "outputs", tag = "s2", root = root)
  expect_equal(in40$post_id, "10")

  # multiple query roots, some absent or 0
  both <- synsnap_partner_summary(c(10, 20, 0, 99), "outputs", tag = "s2", root = root)
  expect_setequal(paste(both$query, both$post_id), c("10 20", "10 40", "20 10"))

  # empty queries keep the column layout
  none <- synsnap_partner_summary(character(), "outputs", tag = "s1", root = root)
  expect_named(none, c("query", "post_id", "weight"))
  expect_equal(nrow(none), 0L)
})

test_that("large queries give the same answer via a registered table", {
  skip_if_no_duckdb()
  root <- make_snapshot(withr::local_tempdir())
  many <- c(10, 20, 1e6 + seq_len(6000))
  big <- synsnap_partner_summary(many, "outputs", tag = "s2", root = root)
  small <- synsnap_partner_summary(c(10, 20), "outputs", tag = "s2", root = root)
  expect_equal(as.data.frame(big), as.data.frame(small))
  expect_false(any(grepl("^synsnap_q_", DBI::dbListTables(synsnap_con()))))
})

test_that("synapse rows and lazy tables", {
  skip_if_no_duckdb()
  root <- make_snapshot(withr::local_tempdir())
  rows <- synsnap_query(40, "post", tag = "s2", root = root, partners = FALSE)
  expect_equal(rows$id, 4L)
  st <- synsnap_query(40, "post", tag = "s2", root = root, partners = FALSE,
                      static = TRUE)
  expect_equal(as.character(st$post_sv), "204")

  withr::local_options(aedes.synapse_snapshot_root = root,
                       aedes.synapse_snapshot = NULL)
  all <- dplyr::collect(aedes_synapse_data())
  expect_equal(nrow(all), 10L)
  expect_equal(sort(all$id), 1:10)
  expect_s3_class(all$pre_root, "integer64")
  expect_equal(sum(all$post_root == bit64::as.integer64(40)), 1L)
  s1 <- dplyr::collect(aedes_synapse_data("pre", snapshot = "s1", static = TRUE))
  expect_true(all(c("pre_sv", "size") %in% colnames(s1)))
  expect_equal(sum(s1$post_root == bit64::as.integer64(30)), 1L)
})

test_that("aedes_synapse_snapshot sets options", {
  skip_if_no_duckdb()
  root <- make_snapshot(withr::local_tempdir())
  withr::local_options(aedes.synapse_snapshot_root = root,
                       aedes.synapse_snapshot = NULL, aedes.version = NULL)
  info <- aedes_synapse_snapshot("s1", set = FALSE)
  expect_equal(info$tag, "s1")
  op <- aedes_synapse_snapshot()
  expect_null(op$aedes.synapse_snapshot)
  expect_equal(getOption("aedes.synapse_snapshot"), "s2")
  expect_equal(fafbseg::flywire_timestamp(timestamp = getOption("aedes.version")),
               synsnap_meta("s2", root)$timestamp)
  expect_equal(aedes_synapse_snapshot_active()$tag, "s2")
})

test_that("choosing between local and CAVE", {
  skip_if_no_duckdb()
  root <- make_snapshot(withr::local_tempdir())
  snap <- aedes_synapse_snapshot("s2", root = root, set = FALSE)
  expect_null(partner_summary_local_problem(snap))
  expect_null(partner_summary_local_problem(snap, remove_autapses = FALSE))
  expect_null(partner_summary_local_problem(snap, timestamp = snap$timestamp))
  expect_match(partner_summary_local_problem(snap, version = 1), "version")
  expect_match(partner_summary_local_problem(snap, cleft.threshold = 50),
               "cleft.threshold")
  expect_match(partner_summary_local_problem(snap, timestamp = "2026-01-01 00:00:00 UTC"),
               "differs")

  withr::local_options(aedes.synapse_snapshot_root = NULL,
                       aedes.synapse_snapshot = NULL)
  expect_error(aedes_partner_summary(10, method = "local"), "No local synapse")

  withr::local_options(aedes.synapse_snapshot_root = root,
                       aedes.synapse_snapshot = "s2")
  expect_error(aedes_partner_summary(10, method = "local", version = 1),
               "Cannot use the local")
  # id resolution needs CAVE, so mock it
  local_mocked_bindings(aedes_ids = function(ids, ...) as.character(ids))
  local_mocked_bindings(flywire_latestid = function(rootid, ...) rootid,
                        .package = "fafbseg")
  res <- aedes_partner_summary(10)
  expect_equal(res$post_id, c("20", "40"))
  expect_equal(attr(res, "snapshot"), "s2")
})

test_that("old, one-file and two-file layouts give the same answers", {
  skip_if_no_duckdb()
  td <- withr::local_tempdir()
  roots <- lapply(c(one = "one", both = "both", old = "old"), function(l) {
    dir.create(file.path(td, l))
    make_snapshot(file.path(td, l), l)
  })
  expect_false(file.exists(file.path(roots$one, "s1", "by_post.parquet")))
  expect_false(file.exists(file.path(roots$one, "s1", "ids.parquet")))
  expect_true(file.exists(file.path(roots$both, "s1", "by_post.parquet")))
  sorted <- function(d) {
    d <- as.data.frame(d)
    d <- d[do.call(order, unname(lapply(d, as.character))), , drop = FALSE]
    rownames(d) <- NULL
    d
  }
  res <- lapply(roots, function(r) lapply(list(
    synsnap_query(c(10, 30), "pre", tag = "s1", root = r),
    synsnap_query(c(10, 30), "post", tag = "s1", root = r),
    synsnap_query(c(10, 40), "pre", tag = "s2", root = r, partners = FALSE, static = TRUE),
    synsnap_query(c(10, 40), "post", tag = "s2", root = r, partners = FALSE),
    dplyr::collect(synsnap_tbl("s2", r))), sorted))
  expect_equal(res$one, res$old)
  expect_equal(res$both, res$old)
  # the post side reads by_post.parquet only when there is one
  expect_match(synsnap_rows_sql("s1", roots$one, "post"), "by_pre.parquet")
  expect_match(synsnap_rows_sql("s1", roots$both, "post"), "by_post.parquet")
  expect_match(synsnap_rows_sql("s1", roots$old), "by_pre.parquet")
})

test_that("building snapshots", {
  skip_if_no_duckdb()
  root <- make_snapshot(withr::local_tempdir())
  con <- synsnap_con()
  compression <- function(f) DBI::dbGetQuery(con, sprintf(
    "SELECT DISTINCT compression FROM parquet_metadata('%s')", file.path(root, f)))$compression
  expect_equal(compression("s1/by_pre.parquet"), "ZSTD")
  expect_equal(compression("static.parquet"), "ZSTD")
  expect_equal(synsnap_meta("s1", root)$timestamp, as.POSIXct("2026-01-01", tz = "UTC"))
  expect_true(is.na(synsnap_meta("s1", root)$base))
  expect_error(synsnap_build("s1", data.frame(), "2026-01-01", root), "already exists")
  expect_error(synsnap_build_static(data.frame(), root), "already exists")

  static <- dplyr::collect(synsnap_tbl("s1", root, static = TRUE))
  svmap <- data.frame(sv = c(static$pre_sv, static$post_sv),
                      root_id = c(static$pre_root, static$post_root))
  expect_error(synsnap_build("bad", svmap[-1, ], "2026-01-01", root),
               "1 synapses have a supervoxel missing")
  expect_equal(list.files(file.path(root, "bad")), character())
  dup <- rbind(svmap, data.frame(sv = svmap$sv[1], root_id = bit64::as.integer64(99)))
  expect_error(synsnap_build("bad", dup, "2026-01-01", root),
               "1 supervoxels map to more than one root")

  # rebasing a delta gives a full snapshot with the same rows
  rows <- function() dplyr::arrange(dplyr::collect(synsnap_tbl("s2", root)), .data$id)
  before <- rows()
  synsnap_rebase("s2", root)
  m <- synsnap_meta("s2", root)
  expect_true(is.na(m$base))
  expect_equal(m$parent, "s1")
  expect_equal(m$timestamp, as.POSIXct("2026-01-02 12:00:00.5", tz = "UTC"))
  expect_false(file.exists(file.path(root, "s2", "delta.parquet")))
  expect_equal(rows(), before)
})
