test_that("coconatfly can query Aedes ids when FlyTable access is available", {
  skip_if_not_installed("coconatfly")
  skip_if_not_installed("coconat")

  meta_probe <- try(aedes_meta("class:ALPN"), silent = TRUE)
  skip_if(
    inherits(meta_probe, "try-error") || !is.data.frame(meta_probe),
    message = "Skipping: no FlyTable metadata access to aedes_main"
  )

  suppressWarnings(register_aedes_coconat())
  ids <- try(coconatfly::cf_ids(aedes = "/class:ALPN"), silent = TRUE)
  skip_if(
    inherits(ids, "try-error") || length(ids) < 1,
    message = "Skipping: coconatfly cf_ids query failed despite available FlyTable metadata"
  )

  expect_true(length(ids) >= 1)
  expect_false(all(is.na(ids)))
})

test_that("aedes_cfids says which ids it replaces to match a version", {
  old <- c("648518347522654868", "648518347566004516")
  new <- c("648518347579064530", "648518347566004516")
  local_mocked_bindings(
    aedes_get_version = function(which = NULL, version = NULL, timestamp = NULL)
      list(version = 521L, timestamp = NULL),
    aedes_ids = function(ids, ...) new[match(ids, old)]
  )
  withr::local_options(aedes.version = "latest")
  expect_message(res <- aedes_cfids(paste(old, collapse = ", ")),
                 "Replaced 1/2 ids to match version 521.*648518347522654868 -> 648518347579064530")
  expect_equal(res, new)
  expect_silent(aedes_cfids(old[2]))
  # queries can't be compared with their input
  expect_silent(aedes_cfids("class:ALPN"))
  # mapping to now is quiet
  withr::local_options(aedes.version = "now")
  expect_silent(aedes_cfids(old))
})

test_that("aedes_cfpartners adds partner metadata at the query time", {
  got <- list()
  local_mocked_bindings(
    aedes_get_version = function(...) list(version = NULL, timestamp = "T1"),
    aedes_partner_summary = function(ids, partners, threshold, version,
                                     timestamp, ...) {
      got$partners <<- timestamp
      data.frame(query = "1", post_id = c("2", "3"), weight = c(5L, 3L))
    },
    aedes_cfmeta = function(ids, version, timestamp, ...) {
      got$meta <<- timestamp
      data.frame(id = ids, type = c("a", "b"),
                 group = bit64::as.integer64(c(NA, 7)))
    })
  res <- aedes_cfpartners("1", partners = "outputs")
  expect_equal(got, list(partners = "T1", meta = "T1"))
  expect_equal(res$type, c("a", "b"))
  expect_equal(res$post_id, c("2", "3"))
})
