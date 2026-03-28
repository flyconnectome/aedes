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
