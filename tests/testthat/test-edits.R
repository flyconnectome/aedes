test_that("operation detail helper preserves IDs from named lists", {
  x <- list(
    `101` = list(timestamp = "2026-01-01T00:00:00Z", user = "a"),
    `102` = list(timestamp = "2026-01-02T00:00:00Z", user = "b")
  )

  df <- aedes:::.operation_details_list_to_df(x)

  expect_equal(df$operation_id, c(101L, 102L))
  expect_equal(df$user, c("a", "b"))
  expect_s3_class(df$timestamp, "POSIXct")
})

test_that("operation detail helper returns empty data frame for empty input", {
  df <- aedes:::.operation_details_list_to_df(list())

  expect_s3_class(df, "data.frame")
  expect_equal(nrow(df), 0L)
  expect_equal(df$operation_id, integer())
})

test_that("operation detail helper rejects unnamed responses", {
  expect_error(
    aedes:::.operation_details_list_to_df(list(list(user = "a"))),
    "did not include valid operation IDs"
  )
})

test_that("operation cache writes fresh results without centroid columns", {
  tmp <- tempdir()
  path <- file.path(tmp, "ops.arrow")
  fresh <- list(
    `101` = list(timestamp = "2026-01-01T00:00:00Z", user = "a", sink_x = 1),
    `102` = list(timestamp = "2026-01-02T00:00:00Z", user = "b", source_z = 2)
  )

  aedes:::.write_ops_cache(path, existing = NULL, fresh_list = fresh)
  got <- aedes:::.read_ops_cache(path)

  expect_equal(got$operation_id, c(101L, 102L))
  expect_equal(got$user, c("a", "b"))
  expect_false("sink_x" %in% colnames(got))
  expect_false("source_z" %in% colnames(got))
})

test_that("operation cache appends with schema drift", {
  tmp <- tempdir()
  path <- file.path(tmp, "ops2.arrow")
  existing <- data.frame(
    operation_id = 101L,
    user = "a",
    stringsAsFactors = FALSE
  )
  fresh <- list(
    `102` = list(timestamp = "2026-01-02T00:00:00Z", user = "b", status = "new")
  )

  aedes:::.write_ops_cache(path, existing = existing, fresh_list = fresh)
  got <- aedes:::.read_ops_cache(path)

  expect_equal(got$operation_id, c(101L, 102L))
  expect_equal(got$user, c("a", "b"))
  expect_true("status" %in% colnames(got))
  expect_true(is.na(got$status[1]))
  expect_equal(got$status[2], "new")
})
