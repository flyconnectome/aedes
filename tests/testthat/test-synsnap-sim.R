# Checkpoint chains in a random fake chunkedgraph (merges, splits and bursts
# of re-edits), checked against the brute force state at each time.
sim_world <- function(seed = 1, nsv = 600, nsyn = 1500, nroot0 = 60, days = 6) {
  withr::local_seed(seed)
  i64 <- bit64::as.integer64
  t0 <- as.POSIXct("2026-01-01", tz = "UTC")
  day <- 86400
  init <- sample(seq_len(nroot0), nsv, TRUE) + 1000
  cur <- init
  next_id <- 5000
  events <- list()
  # whole ms, as CAVE gives them
  times <- sort(round(as.numeric(c(
    t0 + runif(80, 0.01, days) * day,
    rep(t0 + runif(6, 0.01, days) * day, each = 5) + runif(30, 0, 600))), 3))
  for (tt in times) {
    rr <- unique(cur)
    if (runif(1) < 0.5) {
      a <- sample(rr, 2)
      new <- next_id
      next_id <- next_id + 1
      idx <- which(cur %in% a)
      r <- rep(new, length(idx))
    } else {
      big <- rr[tabulate(match(cur, rr), length(rr)) > 1]
      a <- big[sample.int(length(big), 1)]
      idx <- which(cur == a)
      k <- runif(length(idx)) < 0.5
      if (all(k) || !any(k)) k[1] <- !k[1]
      new <- next_id + 0:1
      next_id <- next_id + 2
      r <- ifelse(k, new[1], new[2])
    }
    events[[length(events) + 1]] <- list(t = tt, old = a, new = new, idx = idx, root = r)
    cur[idx] <- r
  }
  ev_t <- vapply(events, `[[`, 0, "t")
  w <- new.env()
  # edits are only visible `lag` seconds after their timestamp, as of `now`
  w$lag <- 0
  w$now <- Inf
  seen <- function() ev_t + w$lag <= as.numeric(w$now)
  map_at <- function(T) {
    m <- init
    for (e in events[ev_t <= as.numeric(T) & seen()]) m[e$idx] <- e$root
    m
  }
  sv <- i64(1e6 + seq_len(nsv))
  w$ctx <- list(
    # as padded by cave_delta_roots: past <= t <= future
    delta_roots = function(past, future) {
      ee <- events[ev_t >= as.numeric(past) & ev_t <= as.numeric(future) & seen()]
      list(old = i64(unique(unlist(lapply(ee, `[[`, "old")))),
           new = i64(unique(unlist(lapply(ee, `[[`, "new")))))
    },
    rootid = function(x, timestamp) i64(map_at(timestamp)[match(x, sv)]))
  syn <- data.frame(id = seq_len(nsyn), pre = sample(nsv, nsyn, TRUE),
                    post = sample(nsv, nsyn, TRUE))
  w$truth <- function(T) {
    m <- map_at(T)
    data.frame(id = syn$id, pre_root = m[syn$pre], post_root = m[syn$post])
  }
  w$t0 <- t0
  w$events <- ev_t
  w$root <- withr::local_tempdir(.local_envir = parent.frame())
  static <- data.frame(id = syn$id, pre_sv = sv[syn$pre], post_sv = sv[syn$post],
                       size = 1L)
  synsnap_build_static(static, w$root, columns = setNames(names(static), names(static)))
  synsnap_build("b0", data.frame(sv = sv, root_id = i64(init)), t0, w$root)
  w
}

sim_matches <- function(w, tag, T) {
  d <- DBI::dbGetQuery(synsnap_con(), synsnap_rows_sql(tag, w$root))
  d <- d[order(d$id), ]
  tr <- w$truth(T)
  identical(as.numeric(d$pre_root), as.numeric(tr$pre_root)) &&
    identical(as.numeric(d$post_root), as.numeric(tr$post_root))
}

test_that("server and local checkpoint chains match the truth", {
  skip_if_no_duckdb()
  skip_on_cran()
  w <- sim_world()
  day <- 86400
  withr::local_seed(2)
  # daily server checkpoints, missing day 3
  for (k in setdiff(1:6, 3)) {
    T <- synsnap_floor_ms(w$t0 + k * day + runif(1, 0, 7200))
    tag <- sprintf("s%d", k)
    synsnap_update(synsnap_at(w$root, T), tag, T, w$root, w$ctx, kind = "regular",
                   overlap = 600)
    expect_true(sim_matches(w, tag, T), label = tag)
  }
  expect_equal(synsnap_meta("s4", w$root)$parent, "s2")
  # local checkpoints at arbitrary times from the newest one before, which
  # may itself be local; then a backfill of the missing day
  for (j in 1:6) {
    T <- synsnap_floor_ms(w$t0 + runif(1, 0.2, 6.5) * day)
    tag <- sprintf("L%d", j)
    synsnap_update(synsnap_at(w$root, T), tag, T, w$root, w$ctx)
    expect_true(sim_matches(w, tag, T), label = tag)
  }
  T <- synsnap_floor_ms(w$t0 + 3 * day)
  synsnap_update(synsnap_at(w$root, T), "s3", T, w$root, w$ctx, kind = "regular")
  expect_true(sim_matches(w, "s3", T))
  # every checkpoint still reads correctly after all that
  tags <- synsnap_tags(w$root)
  expect_true(all(tags$usable))
  for (i in seq_len(nrow(tags)))
    expect_true(sim_matches(w, tags$tag[i], tags$timestamp[i]), label = tags$tag[i])
  # a checkpoint exactly at an edit includes it
  T <- .POSIXct(w$events[40], tz = "UTC")
  synsnap_update(synsnap_at(w$root, T), "edit", T, w$root, w$ctx)
  expect_true(sim_matches(w, "edit", T))
})

test_that("an overlap catches edits that became visible late", {
  skip_if_no_duckdb()
  skip_on_cran()
  w <- sim_world(seed = 3)
  day <- 86400
  w$lag <- 300
  # made 1 min after T1, so it misses an edit 1 min before T1
  T1 <- .POSIXct(w$events[which(w$events > as.numeric(w$t0) + 2 * day)[1]] + 60,
                 tz = "UTC")
  w$now <- T1 + 60
  synsnap_update("b0", "c1", T1, w$root, w$ctx)
  w$now <- Inf
  expect_false(sim_matches(w, "c1", T1))
  T2 <- w$t0 + 3 * day
  synsnap_update("c1", "c2", T2, w$root, w$ctx)
  expect_false(sim_matches(w, "c2", T2))
  synsnap_update("c1", "c2o", T2, w$root, w$ctx, overlap = 600)
  expect_true(sim_matches(w, "c2o", T2))
})

test_that("the server job makes and fills in regular and version checkpoints", {
  skip_if_no_duckdb()
  skip_on_cran()
  w <- sim_world(seed = 4)
  day <- 86400
  pub <- withr::local_tempdir()
  now <- w$t0 + 3 * day + 1800
  ctx <- w$ctx
  ctx$now <- function() now
  rootid <- ctx$rootid
  fail <- FALSE
  ctx$rootid <- function(x, timestamp) {
    if (fail) stop("CAVE is down")
    rootid(x, timestamp)
  }
  vv <- data.frame(version = 1:3,
                   timestamp = w$t0 + c(1.5, 2.7, 3) * day + 0.123456)
  # by default regular checkpoints are at 20:00, skipped after v1 and v2
  expect_equal(synsnap_server_todo(w$root, now, vv)$tag,
               c("r20260101T200000", "v1", "v2"))
  # at midnight: no r20260103T000000, since v1 is in the day before it
  expect_equal(synsnap_server_todo(w$root, now, vv, at = 0)$tag,
               c("r20260101T000000", "r20260102T000000", "v1", "v2"))
  st <- synsnap_server_update(w$root, ctx, dest = pub, versions = vv, at = 0)
  expect_equal(st$built, c("r20260101T000000", "r20260102T000000", "v1", "v2"))
  expect_equal(st$latest, "v2")
  expect_equal(synsnap_meta("v2", w$root)$timestamp, synsnap_parse_time(
    synsnap_format_time(vv$timestamp[2])))
  expect_equal(synsnap_meta("v1", w$root)$parent, "r20260102T000000")
  expect_equal(synsnap_meta("v2", w$root)$parent, "v1")
  expect_true(jsonlite::read_json(file.path(pub, "status.json"))$ok)
  expect_length(synsnap_server_todo(w$root, now, vv, at = 0)$tag, 0)

  # v3 is only made once it has settled. A failed run reports the error; the
  # next one fills in the gap
  now <- now + day
  fail <- TRUE
  expect_error(synsnap_server_update(w$root, ctx, dest = pub, versions = vv, at = 0),
               "v3: CAVE is down")
  expect_false(jsonlite::read_json(file.path(pub, "status.json"))$ok)
  fail <- FALSE
  now <- now + 2 * day
  st <- synsnap_server_update(w$root, ctx, dest = pub, versions = vv, at = 0)
  # v2 covers r20260104T000000 and v3 (just after midnight) r20260105T000000
  expect_equal(st$built, c("v3", "r20260106T000000"))
  tags <- synsnap_tags(w$root)
  expect_true(all(tags$usable))
  for (i in seq_len(nrow(tags)))
    expect_true(sim_matches(w, tags$tag[i], tags$timestamp[i]), label = tags$tag[i])
  m <- jsonlite::read_json(file.path(pub, "manifest.json"), simplifyVector = TRUE)
  expect_equal(m$latest, "r20260106T000000")
  expect_setequal(m$snapshots$tag, tags$tag)

  # a stale newest snapshot is an error even when nothing failed
  now <- now + 3 * day
  expect_error(synsnap_server_update(w$root, ctx, versions = vv, every = 7 * day),
               "hours old")
})
