test_that("aedes_set_version updates package option", {
  old <- getOption("aedes.version")
  on.exit(options(aedes.version = old), add = TRUE)

  aedes_set_version("latest")
  expect_equal(getOption("aedes.version"), "latest")

  aedes_set_version("now")
  expect_equal(getOption("aedes.version"), "now")
})

test_that("aedes_get_version returns version/timestamp list", {
  aedes_get_version(version = 1)
  res <- try(aedes_get_version(version = 'latest'), silent = TRUE)
  skip_if(inherits(res, "try-error"), "Skipping: unable to resolve CAVE version context")

  expect_type(res, "list")
  expect_named(res, c("version", "timestamp"))
})

test_that("aedes_meta query returns data frame when table access exists", {
  df <- try(aedes_meta("class:ALPN"), silent = TRUE)
  skip_if(inherits(df, "try-error") || !is.data.frame(df), "Skipping: no FlyTable metadata access to aedes_main")

  expect_s3_class(df, "data.frame")
  expect_true("root_id" %in% names(df))
})


test_that("aedes_ids resolves ids when metadata access is available", {
  ids <- try(aedes_ids("class:ALPN"), silent = TRUE)
  skip_if(inherits(ids, "try-error") || length(ids) < 1, "Skipping: no FlyTable metadata access for aedes_ids query")

  expect_true(length(ids) >= 1)
})
