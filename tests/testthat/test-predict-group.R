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
  # type ids come from the full aedes_main table; here that is just df
  local_mocked_bindings(aedes_meta = function(...) df)
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

test_that("aedes_predict_group takes type ids from the full table", {
  full <- data.frame(
    serial_id = c("12204", "13839", "13900", "14000", "14100"),
    type = c("KC4", "KC4", "KC4?", "MBON1", NA),
    group = NA, nblast_group = NA
  )
  local_mocked_bindings(aedes_meta = function(...) full)
  # a subset (e.g. partners) lacking the lowest KC4 still gets 12204
  expect_equal(aedes_predict_group(full[2:5, ]), c(12204, 12204, 14000, NA))
})

test_that("parse_nblast_group handles C prefix, plain ids, whitespace and ?", {
  expect_equal(
    parse_nblast_group(c("C10001", "10001", " C10001 ", "C10001?", "10001 ?",
                         "XC10001", "X10001", "c10001", "C", "", NA)),
    c(10001, 10001, 10001, 10001, 10001, NA, NA, NA, NA, NA, NA))
})
