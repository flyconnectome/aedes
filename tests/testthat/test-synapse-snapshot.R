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
  s1 <- dplyr::collect(aedes_synapse_data("pre", snapshot = "s1", details = TRUE))
  expect_true(all(c("pre_sv", "size") %in% colnames(s1)))
  expect_equal(sum(s1$post_root == bit64::as.integer64(30)), 1L)
})

test_that("aedes_use_snapshot sets options", {
  skip_if_no_duckdb()
  root <- make_snapshot(withr::local_tempdir())
  withr::local_options(aedes.synapse_snapshot_root = root,
                       aedes.synapse_snapshot = NULL, aedes.version = NULL)
  t1 <- synsnap_meta("s1", root)$timestamp
  local_mocked_bindings(aedes_version_timestamp = function(version) t1 + 3600)
  info <- aedes_use_snapshot("s1", set = FALSE)
  expect_equal(info$tag, "s1")
  expect_error(aedes_use_snapshot("s1", version = 1), "not both")

  # default "latest": the snapshot of the newest version; option untouched
  op <- expect_message(aedes_use_snapshot(), "'s1'")
  expect_null(op$aedes.synapse_snapshot)
  expect_equal(getOption("aedes.synapse_snapshot"), "s1")
  expect_null(getOption("aedes.version"))
  expect_equal(aedes_snapshot_active()$tag, "s1")

  # explicit times pick the newest snapshot at or before them and set the option
  expect_message(aedes_use_snapshot(timestamp = "now"), "'s2'")
  expect_equal(getOption("aedes.version"), "now")
  expect_message(aedes_use_snapshot(timestamp = "2026-01-02 12:00:00 UTC"), "'s2'")
  expect_equal(getOption("aedes.version"), "2026-01-02 12:00:00.000000 UTC")
  expect_message(aedes_use_snapshot(version = 518), "'s1'")
  expect_identical(getOption("aedes.version"), 518L)
  expect_equal(aedes_use_snapshot("latest", set = FALSE)$tag, "s2")
  expect_message(aedes_use_snapshot(timestamp = "2025-01-01 UTC"), "use CAVE")
  expect_equal(getOption("aedes.synapse_snapshot"), "s1")
})

test_that("choosing between local and CAVE", {
  skip_if_no_duckdb()
  root <- make_snapshot(withr::local_tempdir())
  snap <- aedes_use_snapshot("s2", root = root, set = FALSE)

  t1 <- synsnap_meta("s1", root)$timestamp
  local_mocked_bindings(aedes_version_timestamp = function(version) t1 + 3600)
  withr::local_options(aedes.version = "latest")
  expect_equal(partner_summary_local_time(), t1 + 3600)
  expect_equal(partner_summary_local_time(version = 518), t1 + 3600)
  withr::local_options(aedes.version = "now")
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
                       aedes.synapse_snapshot = "s1", aedes.version = "now")
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
  # a selected snapshot newer than the query time gives way to an older one
  withr::local_options(aedes.synapse_snapshot = "s2")
  res1 <- aedes_partner_summary("10", timestamp = "2026-01-01 00:00:00 UTC")
  expect_equal(attr(res1, "snapshot"), "s1")
  expect_equal(res1$post_id, c("20", "30"))
  # and an older selected snapshot gives way to a newer one for later times
  withr::local_options(aedes.synapse_snapshot = "s1")
  w$now <- as.POSIXct("2026-01-03", tz = "UTC")
  expect_equal(attr(aedes_partner_summary("10"), "snapshot"), "s2")
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

test_that("aedes_snapshot_root", {
  tmp <- withr::local_tempdir()
  withr::local_options(aedes.synapse_snapshot_root = file.path(tmp, "a", "b"))
  expect_equal(aedes_snapshot_root(), file.path(tmp, "a", "b"))
  expect_false(dir.exists(file.path(tmp, "a")))
  expect_error(synsnap_tags(aedes_snapshot_root()), "No synapse snapshot folder")
  # parents are created too
  expect_true(dir.exists(aedes_snapshot_root(create = TRUE)))

  withr::local_options(aedes.synapse_snapshot_root = NULL)
  withr::local_envvar(HOME = tmp, XDG_DATA_HOME = file.path(tmp, "xdg"))
  expect_match(aedes_snapshot_root(), "rpkg-aedes.syn_snapshot$")
  proj <- file.path(tmp, "projects", "2025aedes", "data", "syn_snapshot")
  dir.create(proj, recursive = TRUE)
  expect_match(aedes_snapshot_root(), "rpkg-aedes")
  file.create(file.path(proj, "static.parquet"))
  expect_equal(normalizePath(aedes_snapshot_root()), normalizePath(proj))
})

test_that("snapshots are built in a staging folder", {
  skip_if_no_duckdb()
  root <- make_snapshot(withr::local_tempdir())
  static <- dplyr::collect(synsnap_tbl("s1", root, static = TRUE))
  svmap <- data.frame(sv = c(static$pre_sv, static$post_sv),
                      root_id = c(static$pre_root, static$post_root))
  seen <- NULL
  synsnap_build("s3", svmap, "2026-01-03 00:00:00", root, verify = function(stage) {
    seen <<- stage
    expect_false(dir.exists(file.path(root, "s3")))
    expect_equal(nrow(dplyr::collect(synsnap_tbl(stage, root))), 10)
  })
  expect_equal(seen, file.path(".staging", "s3"))
  expect_equal(synsnap_meta("s3", root)$tag, "s3")
  expect_false(dir.exists(file.path(root, ".staging", "s3")))
  expect_equal(synsnap_tags(root)$tag, c("s1", "s2", "s3"))

  # failed verification: no tag, files kept in .failed
  expect_error(synsnap_build("s4", svmap, "2026-01-04 00:00:00", root,
                             verify = function(stage) stop("mismatch")), "mismatch")
  expect_false(dir.exists(file.path(root, "s4")))
  failed <- list.files(file.path(root, ".failed"), full.names = TRUE)
  expect_match(basename(failed), "^s4-")
  expect_true(file.exists(file.path(failed, "s4", "meta.json")))
  # and a later build of the same tag works
  synsnap_build("s4", svmap, "2026-01-04 00:00:00", root)
  expect_true(file.exists(file.path(root, "s4", "by_pre.parquet")))
})

test_that("static.parquet from a csv edgelist", {
  skip_if_no_duckdb()
  root <- withr::local_tempdir()
  csv <- file.path(root, "edges.df")
  big <- c("73959615070926589", "73959615070926590")
  writeLines(c("cleft_segid,presyn_basin,postsyn_basin,presyn_x,presyn_y,presyn_z,postsyn_x,postsyn_y,postsyn_z,size,extra",
               sprintf("2.0,%s,%s,1,2,3,4,5,6,14.0,0.5", big[1], big[2]),
               sprintf("1.0,%s,%s,1,2,3,4,5,6,7.0,0.5", big[2], big[1])), csv)
  synsnap_build_static(csv, root, format = "csv", meta = list(source_md5 = "abc"))
  st <- arrow::read_parquet(file.path(root, "static.parquet"))
  expect_equal(st$id, 1:2)
  expect_equal(as.character(st$pre_sv), rev(big))
  expect_equal(st$size, c(7L, 14L))
  expect_true(is.integer(st$pre_x))
  js <- jsonlite::read_json(file.path(root, "static.json"))
  expect_equal(js$rows, 2)
  expect_equal(js$source_md5, "abc")

  writeLines(c("cleft_segid,presyn_basin,postsyn_basin,presyn_x,presyn_y,presyn_z,postsyn_x,postsyn_y,postsyn_z,size",
               "1.5,1,2,1,2,3,4,5,6,7.0"), csv)
  expect_error(synsnap_build_static(csv, root, format = "csv", overwrite = TRUE),
               "id is not a whole number")
})

test_that("full snapshot from a resumable supervoxel lookup", {
  skip_if_no_duckdb()
  root <- make_snapshot(withr::local_tempdir())
  w <- fake_world()
  t3 <- "2026-01-01 03:00:00"
  # the lookup fails after the first chunk has been saved
  ctx <- w$ctx
  n <- 0L
  ctx$rootid <- function(x, timestamp) {
    n <<- n + 1L
    if (n == 2L) stop("server down")
    w$ctx$rootid(x, timestamp)
  }
  expect_error(suppressMessages(synsnap_build_from_lookup(
    "s3", t3, root, ctx, chunksize = 8, wait = numeric())), "server down")
  cache <- file.path(root, ".staging", "s3.svmap")
  expect_equal(basename(list.files(cache, "^chunk")), "chunk-00000.parquet")
  expect_false(dir.exists(file.path(root, "s3")))
  # a different timestamp can't reuse the cache
  expect_error(synsnap_build_from_lookup("s3", "2026-01-01 04:00:00", root, ctx,
                                         chunksize = 8), "different timestamp")
  # resume: only the two missing chunks are looked up
  w$calls$rootid <- 0L
  suppressMessages(synsnap_build_from_lookup("s3", t3, root, w$ctx, chunksize = 8))
  expect_equal(w$calls$rootid, 2L)
  expect_false(dir.exists(cache))
  got <- dplyr::arrange(dplyr::collect(synsnap_tbl("s3", root)), .data$id)
  T <- synsnap_parse_time(t3)
  i64 <- bit64::as.integer64
  expect_equal(got$pre_root, w$ctx$rootid(i64(got$id + 100), T))
  expect_equal(got$post_root, w$ctx$rootid(i64(got$id + 200), T))
})

test_that("fetching the source file", {
  src <- withr::local_tempfile(fileext = ".csv")
  writeLines(c("a,b", "1,2"), src)
  md5 <- unname(tools::md5sum(src))
  b64 <- jsonlite::base64_enc(as.raw(strtoi(substring(md5, seq(1, 31, 2), seq(2, 32, 2)), 16L)))
  expect_true(synsnap_md5_ok(src, md5))
  expect_true(synsnap_md5_ok(src, b64))
  skip_if(!nzchar(Sys.which("curl")))
  dest <- withr::local_tempfile(fileext = ".csv")
  url <- paste0("file://", src)
  synsnap_fetch_source(url, dest, b64, method = "curl")
  expect_equal(readLines(dest), c("a,b", "1,2"))
  unlink(dest)
  # a path with ~
  withr::local_envvar(HOME = dirname(dest))
  synsnap_fetch_source(url, file.path("~", basename(dest)), md5, method = "curl")
  expect_equal(readLines(dest), c("a,b", "1,2"))
  unlink(dest)
  expect_error(synsnap_fetch_source(url, dest, strrep("0", 32), method = "curl"),
               "wrong md5")
  expect_false(file.exists(dest) || file.exists(paste0(dest, ".part")))
  # the url doesn't appear in errors
  err <- tryCatch(synsnap_fetch_source(paste0(url, "-missing"), dest, md5,
                                       method = "curl"), error = conditionMessage)
  expect_match(err, "Download failed")
  expect_false(grepl(src, err, fixed = TRUE))
})

test_that("verifying a snapshot against CAVE", {
  skip_if_no_duckdb()
  root <- make_snapshot(withr::local_tempdir())
  w <- fake_world()
  s1 <- dplyr::collect(synsnap_tbl("s1", root))
  cave <- data.frame(id = s1$id, pre_pt_root_id = s1$pre_root,
                     post_pt_root_id = s1$post_root)
  local_mocked_bindings(aedes_cave_query = function(table, filter_in_dict, ...) {
    col <- names(filter_in_dict)
    cave[as.character(cave[[col]]) %in% filter_in_dict[[col]], ]
  })
  expect_true(suppressMessages(aedes_synsnap_verify("s1", root, 1, ctx = w$ctx)))
  # a stale root in CAVE is fine if the chunkedgraph agrees with the snapshot
  cave$post_pt_root_id[cave$id == 1] <- bit64::as.integer64(99)
  expect_match(capture_messages(aedes_synsnap_verify("s1", root, 1, ctx = w$ctx)),
               "1 synapses with stale", all = FALSE)
  # but not if it disagrees
  ctx <- w$ctx
  ctx$rootid <- function(x, timestamp) {
    r <- w$ctx$rootid(x, timestamp)
    r[x == 201] <- bit64::as.integer64(99)
    r
  }
  expect_error(suppressMessages(aedes_synsnap_verify("s1", root, 1, ctx = ctx)),
               "1 synapses have root ids")
  # and synapses missing from CAVE are always an error
  cave <- cave[cave$id != 2, ]
  expect_error(suppressMessages(aedes_synsnap_verify("s1", root, 1, ctx = w$ctx)),
               "synapse ids differ")
})

test_that("aedes_use_snapshot without a snapshot", {
  empty <- file.path(withr::local_tempdir(), "none")
  withr::local_options(rlang_interactive = FALSE)
  expect_error(aedes_use_snapshot(root = empty), "aedes_download_snapshot\\(\\)")
  withr::local_options(rlang_interactive = TRUE)
  local_mocked_bindings(ask_yes_no = function(msg) FALSE)
  expect_error(aedes_use_snapshot(root = empty), "No local synapse snapshot")
  skip_if_no_duckdb()
  root <- withr::local_tempdir()
  local_mocked_bindings(
    ask_yes_no = function(msg) TRUE,
    aedes_download_snapshot = function(root) make_snapshot(root))
  withr::local_options(aedes.synapse_snapshot_root = NULL,
                       aedes.synapse_snapshot = NULL, aedes.version = "now")
  expect_message(aedes_use_snapshot(root = root), "'s2'")
})

test_that("aedes.duckdb_threads limits duckdb threads", {
  skip_if_no_duckdb()
  old <- .synsnap$con
  .synsnap$con <- NULL
  withr::defer({
    DBI::dbDisconnect(.synsnap$con, shutdown = TRUE)
    .synsnap$con <- old
  })
  withr::local_options(aedes.duckdb_threads = 2)
  expect_equal(DBI::dbGetQuery(synsnap_con(),
                               "SELECT current_setting('threads') AS n")$n, 2)
})
