test_that("aedes_predict_group prefers type, group, nblast cluster", {
  df <- data.frame(
    serial_id = c("10005", "10002", "10009", "10003", "10004", "10007",
                  "10008", "10010", "10011", "10012"),
    type = c("KC4", "KC4?", "KC4", NA, "", "undefined", NA, NA, NA, NA),
    group = c(10009, NA, 10009, 10003, 10003, NA, NA, NA, NA, NA),
    # CNNNNN and plain NNNNN clusters count; X-struck clusters are ignored
    nblast_group = c("C10001", NA, NA, "C10001", NA, "C10007", "10003",
                     "C10007", "XC10007", NA)
  )
  expect_equal(aedes_predict_group(df),
               c(10002, 10002, 10002, 10003, 10003, 10007, 10003, 10007,
                 NA, NA))

  # optionally fall back to serial_id (singleton groups)
  expect_equal(aedes_predict_group(df, singletons = TRUE),
               c(10002, 10002, 10002, 10003, 10003, 10007, 10003, 10007,
                 10011, 10012))

  # custom badtypes: KC4 no longer defines a group
  expect_equal(aedes_predict_group(df, badtypes = c(NA, "", "KC4")),
               c(10009, NA, 10009, 10003, 10003, 10007, 10003, 10007,
                 NA, NA))

  # character group column with "0" for ungrouped (as in coconatfly partners)
  df2 <- df
  df2$group <- ifelse(is.na(df$group), "0", as.character(df$group))
  expect_equal(aedes_predict_group(df2), aedes_predict_group(df))

  expect_error(aedes_predict_group(df[c("type", "group")]), "serial_id")
})

test_that("parse_nblast_group handles C prefix, plain ids, whitespace and ?", {
  expect_equal(
    parse_nblast_group(c("C10001", "10001", " C10001 ", "C10001?", "10001 ?",
                         "XC10001", "X10001", "c10001", "C", "", NA)),
    c(10001, 10001, 10001, 10001, 10001, NA, NA, NA, NA, NA, NA))
})
