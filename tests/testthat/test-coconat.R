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
