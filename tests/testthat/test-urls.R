test_that("aedes_scene returns a URL", {
  skip_if_offline()
  sc <- aedes_scene()
  expect_type(sc, "character")
  expect_length(sc, 1)
  expect_match(sc, "https?://")
})

test_that("choose_aedes(set=FALSE) returns option-like named list", {
  skip_if_offline()
  opts <- choose_aedes(set = FALSE)
  expect_type(opts, "list")
  expect_true(length(names(opts)) > 0)
  expect_true(any(grepl("^fafbseg\\.", names(opts))))
})

test_that("with_aedes evaluates an expression", {
  res <- try(with_aedes(1 + 1), silent = TRUE)
  skip_if(inherits(res, "try-error"), "Skipping: unable to activate Aedes dataset")
  expect_equal(res, 2)
})
