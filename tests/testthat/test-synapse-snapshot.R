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

  withr::local_options(aedes.version = "latest")
  expect_equal(partner_summary_local_time(), "now")
  expect_equal(partner_summary_local_time(timestamp = "now"), "now")
  withr::local_options(aedes.version = "2026-01-02 12:00:00.5 UTC")
  expect_equal(partner_summary_local_time(), snap$timestamp)
  expect_equal(partner_summary_local_time(timestamp = "2026-01-03 UTC"),
               as.POSIXct("2026-01-03", tz = "UTC"))

  expect_null(partner_summary_local_problem(snap, "now"))
  expect_null(partner_summary_local_problem(snap, "now", remove_autapses = FALSE))
  expect_null(partner_summary_local_problem(snap, snap$timestamp))
  expect_match(partner_summary_local_problem(snap, "now", cleft.threshold = 50),
               "cleft.threshold")
  expect_match(partner_summary_local_problem(snap, as.POSIXct("2026-01-01", tz = "UTC")),
               "before snapshot")

  withr::local_options(aedes.synapse_snapshot_root = NULL,
                       aedes.synapse_snapshot = NULL)
  expect_error(aedes_partner_summary(10, method = "local"), "No local synapse")

  withr::local_options(aedes.synapse_snapshot_root = root,
                       aedes.synapse_snapshot = "s1", aedes.version = "latest")
  expect_error(aedes_partner_summary(10, method = "local", timestamp = "2025-01-01 UTC"),
               "Cannot use the local")
  # CAVE access through the fake world (edits after s1, now = +3h)
  w <- fake_world()
  withr::defer(synsnap_state_reset())
  local_mocked_bindings(aedes_synsnap_ctx = function() w$ctx)
  res <- aedes_partner_summary(10)
  expect_equal(res$post_id, "50")
  expect_equal(res$weight, 4L)
  expect_equal(attr(res, "snapshot"), "s1")
  expect_equal(attr(res, "timestamp"), w$now)
  res0 <- aedes_partner_summary("10", timestamp = "2026-01-01 00:00:00 UTC")
  expect_equal(res0$post_id, c("20", "30"))
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

test_that("aedes_synapse_snapshot_root", {
  tmp <- withr::local_tempdir()
  withr::local_options(aedes.synapse_snapshot_root = file.path(tmp, "a", "b"))
  expect_equal(aedes_synapse_snapshot_root(), file.path(tmp, "a", "b"))
  expect_false(dir.exists(file.path(tmp, "a")))
  expect_error(synsnap_tags(aedes_synapse_snapshot_root()), "No synapse snapshot folder")
  # parents are created too
  expect_true(dir.exists(aedes_synapse_snapshot_root(create = TRUE)))

  withr::local_options(aedes.synapse_snapshot_root = NULL)
  withr::local_envvar(HOME = tmp, XDG_DATA_HOME = file.path(tmp, "xdg"))
  expect_match(aedes_synapse_snapshot_root(), "rpkg-aedes.syn_snapshot$")
  proj <- file.path(tmp, "projects", "2025aedes", "data", "syn_snapshot")
  dir.create(proj, recursive = TRUE)
  expect_match(aedes_synapse_snapshot_root(), "rpkg-aedes")
  file.create(file.path(proj, "static.parquet"))
  expect_equal(normalizePath(aedes_synapse_snapshot_root()), normalizePath(proj))
})
