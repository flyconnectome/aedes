# rows of a snapshot tag at T should match the fake world's truth
expect_tag_matches <- function(w, tag, T) {
  rows <- DBI::dbGetQuery(synsnap_con(), sprintf(
    "SELECT pre_root, post_root, count(*) AS weight FROM (%s) GROUP BY ALL",
    synsnap_rows_sql(tag, w$root)))
  tr <- dplyr::bind_rows(w$truth(c(0, 10, 20, 30, 40, 41, 42, 43, 50), "pre", T))
  key <- function(d) sort(paste(d$pre_root, d$post_root, d$weight))
  expect_equal(key(rows), key(tr))
}

test_that("delta snapshots from full and delta snapshots", {
  skip_if_no_duckdb()
  root <- make_snapshot(withr::local_tempdir())
  w <- fake_world()
  w$root <- root
  h <- 3600
  t0 <- as.POSIXct("2026-01-01", tz = "UTC")

  # no edits: an empty delta
  synsnap_update("s1", "u0", t0 + 0.5 * h, root, w$ctx)
  expect_equal(nrow(arrow::read_parquet(synsnap_path(root, "u0", "delta.parquet"))), 0)
  expect_tag_matches(w, "u0", t0 + 0.5 * h)

  synsnap_update("s1", "u1", t0 + 1.5 * h, root, w$ctx)
  m <- synsnap_meta("u1", root)
  expect_equal(m$base, "s1")
  expect_equal(m$parent, "s1")
  expect_equal(m$timestamp, t0 + 1.5 * h)
  expect_tag_matches(w, "u1", t0 + 1.5 * h)

  # a delta on a delta is against the full base, and only has changed rows
  synsnap_update("u1", "u2", t0 + 3 * h, root, w$ctx)
  m <- synsnap_meta("u2", root)
  expect_equal(m$base, "s1")
  expect_equal(m$parent, "u1")
  expect_tag_matches(w, "u2", t0 + 3 * h)
  d <- arrow::read_parquet(synsnap_path(root, "u2", "delta.parquet"))
  # synapses 1-7 and 10 touch roots 20/30/40/41
  expect_equal(sort(d$id), c(1:7, 10L))

  # queries on the new tag agree, and no session state was touched
  expect_length(.synsnap$states, 0)
  expect_same_counts(synsnap_query(bit64::as.integer64(50), "post", "u2", root),
                     w$truth(50, "post", t0 + 3 * h))

  expect_error(synsnap_update("s1", "u1", t0 + 2 * h, root, w$ctx), "exists")
  expect_error(synsnap_update("u2", "u3", t0 + 2 * h, root, w$ctx), "before")

  # rebasing gives a full snapshot with the same rows
  synsnap_rebase("u2", root)
  expect_true(is.na(synsnap_meta("u2", root)$base))
  expect_tag_matches(w, "u2", t0 + 3 * h)
})

test_that("aedes_update_snapshot", {
  skip_if_no_duckdb()
  root <- make_snapshot(withr::local_tempdir())
  w <- fake_world()
  w$root <- root
  local_mocked_bindings(aedes_synsnap_ctx = function() w$ctx)
  withr::local_options(aedes.synapse_snapshot_root = NULL,
                       aedes.synapse_snapshot = NULL, aedes.version = NULL)
  s <- aedes_update_snapshot(from = "s1", root = root, set = FALSE)
  expect_equal(s$tag, "20260101T030000")
  expect_equal(s$timestamp, w$now)
  expect_tag_matches(w, s$tag, w$now)
  aedes_update_snapshot("2026-01-01 02:00:00", from = "s1", tag = "full",
                                root = root, rebase = TRUE)
  expect_true(file.exists(synsnap_path(root, "full", "by_pre.parquet")))
  expect_equal(getOption("aedes.synapse_snapshot"), "full")
  expect_tag_matches(w, "full", w$now - 3600)
})
