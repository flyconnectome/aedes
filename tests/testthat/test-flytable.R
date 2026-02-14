test_that("write_info writes a stable local info file", {
  td <- tempfile("aedes_info_")
  dir.create(td)
  infof <- file.path(td, "info")

  anndf <- data.frame(
    root_id = c("1", "2"),
    type = c("A", "B"),
    stringsAsFactors = FALSE
  )

  expect_no_error(write_info(anndf, td))
  expect_true(file.exists(infof))

  md5_1 <- unname(tools::md5sum(infof))
  expect_no_error(write_info(anndf, td))
  md5_2 <- unname(tools::md5sum(infof))

  expect_equal(md5_1, md5_2)
})
