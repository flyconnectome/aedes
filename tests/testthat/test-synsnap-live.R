local_world <- function(env = parent.frame()) {
  skip_if_no_duckdb()
  root <- make_snapshot(withr::local_tempdir(.local_envir = env))
  withr::defer(synsnap_state_reset(), envir = env)
  w <- fake_world()
  w$root <- root
  w
}

h <- 3600
t0 <- as.POSIXct("2026-01-01", tz = "UTC")

test_that("root log is cached in chunks and gaps are fetched", {
  w <- local_world()
  st <- synsnap_state("s1", w$root)
  lg <- synsnap_log_range(st, t0, t0 + 3 * h, w$ctx)
  expect_setequal(as.character(lg$old), c("30", "20", "40", "41", "42"))
  expect_setequal(as.character(lg$new), c("40", "41", "50", "42", "43"))
  expect_equal(st$log_t, t0 + 3 * h)
  n <- w$calls$delta_roots
  lg2 <- synsnap_log_range(st, t0 + 3 * h, t0 + 3 * h, w$ctx)
  expect_equal(w$calls$delta_roots, n)
  expect_length(lg2$old, 0)
  # a sub-range inside the cached chunk is fetched directly
  lg3 <- synsnap_log_range(st, t0 + 1.5 * h, t0 + 2.55 * h, w$ctx)
  expect_setequal(as.character(lg3$old), c("20", "40", "41"))
  # long intervals are split
  st2 <- synsnap_state("s2", w$root)
  expect_length(synsnap_fetch_log(t0, t0 + 3 * 86400 + 1, w$ctx), 4)
})

test_that("both update methods match the truth", {
  w <- local_world()
  cases <- list(list(q = 10, side = "pre"), list(q = 10, side = "post"),
                list(q = 50, side = "pre"), list(q = 50, side = "post"),
                list(q = c(10, 50, 43), side = "pre"))
  for (T in list(t0 + 1.5 * h, t0 + 2 * h, t0 + 3 * h)) {
    for (cs in cases) {
      tr <- w$truth(cs$q, cs$side, T)
      # 50 made at +2h, 43 at +2.6h
      if ((50 %in% cs$q && T < t0 + 2 * h) || (43 %in% cs$q && T < t0 + 2.6 * h))
        next
      synsnap_state_reset()
      rq <- synsnap_query_at(cs$q, cs$side, "s1", w$root, T, w$ctx,
                             min_sv = 0, f = Inf)
      expect_equal(attr(rq, "method"), "query")
      expect_same_counts(rq, tr)
      synsnap_state_reset()
      rh <- synsnap_query_at(cs$q, cs$side, "s1", w$root, T, w$ctx)
      expect_equal(attr(rh, "method"), "head")
      expect_same_counts(rh, tr)
      expect_equal(attr(rh, "timestamp"), T)
    }
  }
})

test_that("head advances incrementally and past times use the snapshot", {
  w <- local_world()
  r1 <- synsnap_query_at(10, "pre", "s1", w$root, t0 + h, w$ctx)
  expect_same_counts(r1, w$truth(10, "pre", t0 + h))
  st <- synsnap_state("s1", w$root)
  expect_equal(st$t, t0 + h)
  r2 <- synsnap_query_at(10, "pre", "s1", w$root, t0 + 2 * h, w$ctx)
  expect_equal(attr(r2, "method"), "head")
  expect_same_counts(r2, w$truth(10, "pre", t0 + 2 * h))
  # inputs of 50 from the head
  expect_same_counts(synsnap_query_at(50, "post", "s1", w$root, t0 + 2 * h, w$ctx),
                     w$truth(50, "post", t0 + 2 * h))
  # earlier than the head: per-query update from the snapshot, head unchanged
  r0 <- synsnap_query_at(10, "pre", "s1", w$root, t0 + 1.5 * h, w$ctx)
  expect_equal(attr(r0, "method"), "query")
  expect_same_counts(r0, w$truth(10, "pre", t0 + 1.5 * h))
  expect_equal(st$t, t0 + 2 * h)
  expect_error(synsnap_query_at(10, "pre", "s1", w$root, t0 - h, w$ctx), "before snapshot")
})

test_that("now queries honour max_age", {
  w <- local_world()
  w$now <- t0 + 2 * h
  r1 <- synsnap_query_at(10, "pre", "s1", w$root, "now", w$ctx)
  expect_equal(attr(r1, "timestamp"), t0 + 2 * h)
  n <- w$calls$delta_roots
  w$now <- t0 + 2 * h + 30
  r2 <- synsnap_query_at(10, "pre", "s1", w$root, "now", w$ctx)
  expect_equal(w$calls$delta_roots, n)
  expect_equal(attr(r2, "timestamp"), t0 + 2 * h)
  r3 <- synsnap_query_at(10, "pre", "s1", w$root, "now", w$ctx, max_age = 0)
  expect_equal(attr(r3, "timestamp"), t0 + 2 * h + 30)
  expect_gt(w$calls$delta_roots, n)
})

test_that("edits that become visible late are caught", {
  # 30 -> 40, 41 at +1h, visible 2 min later; synapse 4 is 10 -> 30 (40)
  T1 <- t0 + h + 30
  T2 <- t0 + h + 200
  for (m in c("head", "query")) for (overlap in c(600, 0)) {
    w <- local_world()
    w$lag <- 120
    q <- function(T) {
      w$now <- T
      r <- synsnap_query_at(10, "pre", "s1", w$root, "now", w$ctx,
                            overlap = overlap, min_sv = if (m == "query") -1 else 5e4,
                            f = if (m == "query") 1e9 else 0.3)
      # without the overlap, T2 sees no edits so there is nothing to choose
      if (overlap && identical(T, T2)) expect_equal(attr(r, "method"), m)
      r
    }
    q(T1)
    r <- q(T2)
    key <- function(d) sort(paste(d$pre_root, d$post_root, d$weight))
    if (overlap) expect_equal(key(r), key(w$truth(10, "pre", T2)))
    else expect_false(identical(key(r), key(w$truth(10, "pre", T2))))
  }
})

test_that("out of date query ids are updated", {
  w <- local_world()
  # 30 expired at +1h; its largest part (40) merged into 50 at +2h
  r <- synsnap_query_at(30, "post", "s1", w$root, t0 + 2 * h, w$ctx)
  expect_same_counts(r, w$truth(50, "post", t0 + 2 * h))
  expect_equal(w$calls$latest_id, 1L)
  # roots with no synapses are checked with is_latest
  r0 <- synsnap_query_at(99, "pre", "s1", w$root, t0 + 2 * h, w$ctx)
  expect_equal(nrow(r0), 0L)
  expect_equal(w$calls$is_latest, 1L)
})

test_that("choice between head and query depends on query size", {
  w <- local_world()
  # small query, large head update relative to it -> query
  r <- synsnap_query_at(43, "pre", "s1", w$root, t0 + 3 * h, w$ctx, min_sv = 0,
                        f = 2, leaf_cost = 0)
  expect_equal(attr(r, "method"), "query")
  # large query -> head
  r <- synsnap_query_at(c(10, 50, 43), "pre", "s1", w$root, t0 + 3 * h, w$ctx,
                        min_sv = 0, f = 0.5)
  expect_equal(attr(r, "method"), "head")
})

test_that("partner summary at a time", {
  w <- local_world()
  ps <- synsnap_partner_summary(10, "outputs", tag = "s1", root = w$root,
                                timestamp = t0 + 2 * h, ctx = w$ctx)
  expect_equal(ps$post_id, "50")
  expect_equal(ps$weight, 4L)
  expect_equal(attr(ps, "timestamp"), t0 + 2 * h)
})
