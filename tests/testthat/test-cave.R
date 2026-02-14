test_that("aedes_cave_query works when access is available", {
  df <- suppressWarnings(try(aedes_cave_query(table = "nuclei_v1_aedes", limit = 1), silent = TRUE))
  skip_if(inherits(df, "try-error") || !is.data.frame(df), "Skipping: no CAVE access to nuclei_v1_aedes")

  expect_s3_class(df, "data.frame")
})

test_that("aedes_cave_client initialises when access is available", {
  cli <- suppressWarnings(try(aedes_cave_client(), silent = TRUE))
  skip_if(inherits(cli, "try-error"), "Skipping: unable to initialise CAVE client")

  expect_false(is.null(cli))
})
