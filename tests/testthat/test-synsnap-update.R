# rows of a snapshot tag at T should match the fake world's truth
expect_tag_matches <- function(w, tag, T) {
  rows <- DBI::dbGetQuery(synsnap_con(), sprintf(
    "SELECT pre_root, post_root, count(*) AS weight FROM (%s) GROUP BY ALL",
    synsnap_rows_sql(tag, w$root)))
  tr <- dplyr::bind_rows(w$truth(c(0, 10, 20, 30, 40, 41, 42, 43, 50), "pre", T))
  key <- function(d) sort(paste(d$pre_root, d$post_root, d$weight))
  expect_equal(key(rows), key(tr))
}

test_that("checkpoints from full snapshots and checkpoints", {
  skip_if_no_duckdb()
  root <- make_snapshot(withr::local_tempdir())
  w <- fake_world()
  w$root <- root
  h <- 3600
  t0 <- as.POSIXct("2026-01-01", tz = "UTC")
  readlog <- function(tag) arrow::read_parquet(synsnap_path(root, tag, "log.parquet"))

  # no edits: an empty log
  synsnap_update("s1", "u0", t0 + 0.5 * h, root, w$ctx)
  expect_equal(nrow(readlog("u0")), 0)
  expect_tag_matches(w, "u0", t0 + 0.5 * h)

  synsnap_update("s1", "u1", t0 + 1.5 * h, root, w$ctx)
  m <- synsnap_meta("u1", root)
  expect_equal(m$base, "s1")
  expect_equal(m$parent, "s1")
  expect_equal(m$kind, "local")
  expect_equal(m$timestamp, t0 + 1.5 * h)
  expect_tag_matches(w, "u1", t0 + 1.5 * h)
  # root 30 split: only the changed side of each synapse, with its old root
  l1 <- readlog("u1")
  expect_equal(l1$id, c(4L, 7L, 10L))
  expect_equal(as.character(l1$post_root), c("40", NA, NA))
  expect_equal(as.character(l1$old_pre), c(NA, "30", "30"))
  expect_equal(as.character(l1$pre_root), c(NA, "40", "41"))

  # a checkpoint on a checkpoint only logs changes since its parent
  synsnap_update("u1", "u2", t0 + 3 * h, root, w$ctx, kind = "regular", overlap = 600)
  m <- synsnap_meta("u2", root)
  expect_equal(m$base, "s1")
  expect_equal(m$parent, "u1")
  expect_equal(m$rows, 8)
  expect_tag_matches(w, "u2", t0 + 3 * h)
  # synapses 1-3, 5-6 (root 20) and 4/7 (40) merged into 50; 10 41 -> 43
  expect_equal(readlog("u2")$id, c(1:7, 10L))
  expect_equal(synsnap_chain("u2", root), c("u2", "u1"))

  # queries on the new tag agree, and no session state was touched
  expect_length(.synsnap$states, 0)
  expect_same_counts(synsnap_query(bit64::as.integer64(50), "post", "u2", root),
                     w$truth(50, "post", t0 + 3 * h))

  expect_error(synsnap_update("s1", "u1", t0 + 2 * h, root, w$ctx), "exists")
  expect_error(synsnap_update("u2", "u3", t0 + 2 * h, root, w$ctx), "before")

  # rebasing gives a full snapshot with the same rows
  synsnap_rebase("u2", root)
  expect_true(is.na(synsnap_meta("u2", root)$base))
  expect_equal(synsnap_meta("u2", root)$parent, "u1")
  expect_tag_matches(w, "u2", t0 + 3 * h)
})

test_that("missed and backfilled checkpoints", {
  skip_if_no_duckdb()
  root <- make_snapshot(withr::local_tempdir())
  w <- fake_world()
  w$root <- root
  h <- 3600
  t0 <- as.POSIXct("2026-01-01", tz = "UTC")
  # a missed run: one checkpoint covers all the edits
  synsnap_update("s1", "a3", t0 + 3 * h, root, w$ctx)
  expect_tag_matches(w, "a3", t0 + 3 * h)
  # backfilled later: a side branch from s1, which leaves a3 alone
  synsnap_update(synsnap_at(root, t0 + 1.5 * h), "b1", t0 + 1.5 * h, root, w$ctx)
  synsnap_update("b1", "b2", t0 + 2.55 * h, root, w$ctx)
  for (x in list(c("a3", 3), c("b1", 1.5), c("b2", 2.55)))
    expect_tag_matches(w, x[1], t0 + as.numeric(x[2]) * h)
  # later checkpoints build on whichever is newest
  w$now <- t0 + 4 * h
  synsnap_update(synsnap_at(root, w$now), "a4", w$now, root, w$ctx)
  expect_equal(synsnap_meta("a4", root)$parent, "a3")
  expect_tag_matches(w, "a4", w$now)

  # an unfinished checkpoint (no meta.json) is not a snapshot
  dir.create(file.path(root, "c1"))
  file.copy(synsnap_path(root, "b1", "log.parquet"), file.path(root, "c1"))
  expect_false("c1" %in% synsnap_tags(root, all = TRUE)$tag)

  # a checkpoint whose chain is broken is skipped, and says why when used
  unlink(file.path(root, "b1"), recursive = TRUE)
  tags <- synsnap_tags(root, all = TRUE)
  expect_equal(tags$usable[tags$tag == "b2"], FALSE)
  expect_false("b2" %in% synsnap_tags(root)$tag)
  expect_equal(synsnap_at(root, t0 + 2.6 * h), "s1")
  expect_error(synsnap_rows_sql("b2", root), "needs snapshot 'b1'")
})

test_that("old delta snapshots are converted to logs", {
  skip_if_no_duckdb()
  i64 <- bit64::as.integer64
  root <- make_snapshot(withr::local_tempdir(), delta = TRUE)
  expect_equal(synsnap_tags(root)$tag, "s1")
  expect_error(synsnap_rows_sql("s2", root), "old format")
  # a second old delta on top of s2: synapse 1 post 20 -> 60, 7 pre 40 -> 70
  d3 <- data.frame(id = c(1L, 4L, 7L), pre_root = i64(c(10, 10, 70)),
                   post_root = i64(c(60, 40, 10)))
  dir.create(file.path(root, "s3"))
  arrow::write_parquet(d3, file.path(root, "s3", "delta.parquet"))
  jsonlite::write_json(list(tag = "s3", timestamp = "2026-01-03 00:00:00.000000 UTC",
                            base = "s1", parent = "s2"),
                       file.path(root, "s3", "meta.json"), auto_unbox = TRUE)
  rows <- function(tag) dplyr::arrange(dplyr::collect(synsnap_tbl(tag, root)), id)
  expected <- rows("s1")

  expect_equal(synsnap_convert_deltas(root), c("s2", "s3"))
  expect_equal(synsnap_tags(root)$tag, c("s1", "s2", "s3"))
  expect_false(file.exists(synsnap_path(root, "s2", "delta.parquet")))
  expect_equal(synsnap_meta("s3", root)$kind, "local")
  expected[c(4, 7), c("pre_root", "post_root")] <- list(i64(c(10, 40)), i64(c(40, 10)))
  expect_equal(rows("s2"), expected)
  expected[c(1, 7), c("pre_root", "post_root")] <- list(i64(c(10, 70)), i64(c(60, 10)))
  expect_equal(rows("s3"), expected)
  l3 <- arrow::read_parquet(synsnap_path(root, "s3", "log.parquet"))
  expect_equal(l3$id, c(1L, 7L))
  expect_equal(as.character(l3$old_post), c("20", NA))
  expect_equal(as.character(l3$old_pre), c(NA, "40"))
  expect_length(synsnap_convert_deltas(root), 0)
})

test_that("aedes_update_snapshot", {
  skip_if_no_duckdb()
  root <- make_snapshot(withr::local_tempdir())
  w <- fake_world()
  w$root <- root
  local_mocked_bindings(aedes_synsnap_ctx = function() w$ctx)
  withr::local_options(aedes.synapse_snapshot_root = NULL,
                       aedes.synapse_snapshot = NULL, aedes.version = "latest")
  expect_message(s <- aedes_update_snapshot(from = "s1", root = root, set = FALSE),
                 "to 2026-01-01 03:00:00 UTC \\(now\\)")
  expect_equal(s$tag, "20260101T030000")
  expect_equal(s$timestamp, w$now)
  expect_tag_matches(w, s$tag, w$now)
  aedes_update_snapshot("2026-01-01 02:00:00", from = "s1", tag = "full",
                                root = root, rebase = TRUE)
  expect_true(file.exists(synsnap_path(root, "full", "by_pre.parquet")))
  expect_equal(getOption("aedes.synapse_snapshot"), "full")
  expect_tag_matches(w, "full", w$now - 3600)
  expect_message(aedes_update_snapshot(), "aedes_set_version")

  # "latest": the time of the newest version; the start is the newest
  # snapshot at or before it
  local_mocked_bindings(aedes_version_timestamp = function(version) w$now - 7200)
  expect_message(s <- aedes_update_snapshot("latest", root = root, set = FALSE),
                 "'s1'.*latest materialisation")
  expect_equal(s$timestamp, w$now - 7200)
  expect_message(aedes_update_snapshot("latest", root = root, set = FALSE),
                 "already at")
  expect_error(aedes_update_snapshot("2025-01-01", root = root), "as old as")
})

test_that("publish and download snapshots", {
  skip_if_no_duckdb()
  skip_if(!nzchar(Sys.which("curl")))
  root <- make_snapshot(withr::local_tempdir())
  pub <- withr::local_tempdir()
  m <- synsnap_publish(root, pub, "s2")
  expect_equal(m$latest, "s2")
  expect_setequal(m$snapshots$tag, c("s1", "s2"))
  expect_true(file.exists(file.path(pub, "s1", "by_pre.parquet")))
  expect_equal(unname(tools::md5sum(file.path(pub, m$files$path))), m$files$md5)
  # republishing reuses the md5s and leaves files alone
  expect_equal(synsnap_publish(root, pub, "s2")$files$md5, m$files$md5)

  local <- withr::local_tempdir()
  url <- paste0("file://", normalizePath(pub))
  expect_equal(synsnap_download(url, local), c("s1", "s2"))
  expect_equal(synsnap_tags(local)$tag, c("s1", "s2"))
  expect_false(dir.exists(file.path(local, ".staging", "download")))
  expect_equal(
    dplyr::collect(dplyr::arrange(synsnap_tbl("s2", local, static = TRUE), id)),
    dplyr::collect(dplyr::arrange(synsnap_tbl("s2", root, static = TRUE), id)))
  expect_length(synsnap_download(paste0(url, "/manifest.json"), local), 0)

  # later checkpoints, including a backfill on a side branch, arrive after
  # their parents; an unfinished one is not published
  add_cp <- function(tag, parent, time, base = "s1") {
    dir.create(file.path(root, tag))
    file.copy(file.path(root, "s2", "log.parquet"), file.path(root, tag))
    if (!is.null(time))
      jsonlite::write_json(list(tag = tag, timestamp = time, base = base, parent = parent),
                           file.path(root, tag, "meta.json"), auto_unbox = TRUE)
  }
  add_cp("s4", "s2", "2026-01-04 00:00:00.000000 UTC")
  add_cp("s3", "s2", "2026-01-03 00:00:00.000000 UTC")
  add_cp("s3b", "s3", "2026-01-03 06:00:00.000000 UTC")
  add_cp("s5", "s4", NULL)
  m <- synsnap_publish(root, pub)
  expect_equal(m$latest, "s4")
  expect_equal(m$snapshots$tag, c("s1", "s2", "s3", "s3b", "s4"))
  expect_equal(m$snapshots$parent[m$snapshots$tag == "s3b"], "s3")
  expect_equal(synsnap_download(url, local), c("s3", "s4", "s3b"))
  expect_true(all(synsnap_tags(local)$usable))
  expect_equal(synsnap_meta("s3b", local)$timestamp, synsnap_meta("s3b", root)$timestamp)

  # a checkpoint with a missing parent is not published
  unlink(file.path(root, "s3"), recursive = TRUE)
  expect_error(synsnap_publish(root, pub, "s3b"), "needs snapshot 's3'")
  expect_false("s3b" %in% synsnap_publish(root, pub)$snapshots$tag)

  # after a rebase only the new full snapshot and its checkpoints are listed;
  # dropped files are removed one publish later
  synsnap_rebase("s4", root)
  m2 <- synsnap_publish(root, pub)
  expect_equal(m2$snapshots$tag, "s4")
  expect_true(file.exists(file.path(pub, "s4", "by_pre.parquet")))
  expect_true("s2/log.parquet" %in% m2$keep)
  expect_true(file.exists(file.path(pub, "s2", "log.parquet")))
  synsnap_publish(root, pub)
  expect_false(dir.exists(file.path(pub, "s2")))
  expect_false(file.exists(file.path(pub, "s4", "log.parquet")))

  other <- make_snapshot(withr::local_tempdir())
  jsonlite::write_json(list(x = 1), file.path(other, "static.json"))
  expect_error(synsnap_download(url, other), "different static data")
  withr::local_options(aedes.snapshot_url = url)
  expect_equal(aedes_snapshot_url(), url)
})

test_that("aedes_synapse_data at a timestamp", {
  skip_if_no_duckdb()
  root <- make_snapshot(withr::local_tempdir())
  w <- fake_world()
  w$root <- root
  local_mocked_bindings(aedes_synsnap_ctx = function() w$ctx)
  n <- function(...) nrow(dplyr::collect(aedes_synapse_data(root = root, ...)))
  # s1 is used as it is
  expect_silent(n(timestamp = "2026-01-01 00:00:30"))
  # otherwise a checkpoint is made, then reused
  expect_message(n(timestamp = "now"), "Updating synapse snapshot 's1'")
  expect_true("20260101T030000" %in% synsnap_tags(root)$tag)
  expect_tag_matches(w, "20260101T030000", w$now)
  w$now <- w$now + 30
  expect_silent(n(timestamp = "now"))
  expect_error(aedes_synapse_data(root = root, timestamp = "2025-01-01"), "as old as")
})

test_that("newly published checkpoints are fetched automatically", {
  skip_if_no_duckdb()
  skip_if(!nzchar(Sys.which("curl")))
  root <- make_snapshot(withr::local_tempdir())
  pub <- withr::local_tempdir()
  synsnap_publish(root, pub)
  local <- withr::local_tempdir()
  url <- paste0("file://", normalizePath(pub))
  withr::local_options(aedes.snapshot_url = url)
  synsnap_download(url, local)
  add_cp <- function(tag, parent, time, base = "s1") {
    dir.create(file.path(root, tag))
    file.copy(file.path(root, "s2", "log.parquet"), file.path(root, tag))
    jsonlite::write_json(list(tag = tag, timestamp = time, base = base, parent = parent),
                         file.path(root, tag, "meta.json"), auto_unbox = TRUE)
    synsnap_publish(root, pub)
  }
  add_cp("s3", "s2", "2026-01-03 00:00:00.000000 UTC")
  expect_equal(suppressMessages(aedes_snapshot_refresh(local, hours = 6)), "s3")
  # not again within `hours`, even in a new session
  add_cp("s4", "s3", "2026-01-04 00:00:00.000000 UTC")
  expect_length(aedes_snapshot_refresh(local, hours = 6), 0)
  expect_equal(suppressMessages(aedes_snapshot_refresh(local, hours = 0)), "s4")
  expect_length(aedes_snapshot_refresh(local, hours = Inf), 0)
  # a new full snapshot is only announced
  synsnap_rebase("s4", root)
  add_cp("s5", "s4", "2026-01-05 00:00:00.000000 UTC", base = "s4")
  expect_message(res <- aedes_snapshot_refresh(local, hours = 0), "new full")
  expect_length(res, 0)
  expect_false("s5" %in% synsnap_tags(local, all = TRUE)$tag)
  # failures are quiet for a day
  withr::local_options(aedes.snapshot_url = paste0(url, "-missing"))
  expect_silent(aedes_snapshot_refresh(local, hours = 0))
  f <- file.path(local, ".last_check.json")
  st <- jsonlite::read_json(f)
  expect_false(is.null(st$failing_since))
  st$failing_since <- "2026-01-01 00:00:00.000000 UTC"
  jsonlite::write_json(st, f, auto_unbox = TRUE)
  expect_message(aedes_snapshot_refresh(local, hours = 0), "Could not check")
  withr::local_options(aedes.snapshot_url = url)
  suppressMessages(aedes_snapshot_refresh(local, hours = 0))
  expect_null(jsonlite::read_json(f)$failing_since)
})

test_that("synsnap_l2_hash", {
  h <- digest::digest("9\n10\n648518347624785674", algo = "sha256", serialize = FALSE)
  expect_equal(synsnap_l2_hash(c("648518347624785674", "10", "9", "10")), h)
  expect_equal(synsnap_l2_hash(bit64::as.integer64(c("10", "9", "648518347624785674"))), h)
})
