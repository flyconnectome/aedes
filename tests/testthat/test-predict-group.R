test_that("aedes_predict_group prefers type, then group, then serial_id", {
  df <- data.frame(
    serial_id = c("10005", "10002", "10009", "10003", "10004", "10007", "10008"),
    type = c("KC4", "KC4?", "KC4", NA, "", "undefined", NA),
    group = c(10009, NA, 10009, 10003, 10003, NA, NA)
  )
  expect_equal(aedes_predict_group(df),
               c(10002, 10002, 10002, 10003, 10003, 10007, 10008))

  # custom badtypes: KC4 no longer defines a group
  expect_equal(aedes_predict_group(df, badtypes = c(NA, "", "KC4")),
               c(10009, 10002, 10009, 10003, 10003, 10007, 10008))

  # character group column with "0" for ungrouped (as in coconatfly partners)
  df2 <- transform(df, group = c("10009", "0", "10009", "10003", "10003", "0", "0"))
  expect_equal(aedes_predict_group(df2), aedes_predict_group(df))

  expect_error(aedes_predict_group(df[c("type", "group")]), "serial_id")
})
