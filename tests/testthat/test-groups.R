test_that("aedes_set_group treats NA (not 0) as the ungrouped sentinel", {
  am <- try(aedes_meta(), silent = TRUE)
  skip_if(inherits(am, "try-error"), "aedes_meta() unavailable")

  grouped <- am$root_id[!is.na(am$group)]
  ungrouped <- am$root_id[is.na(am$group)]
  skip_if(!length(grouped) || !length(ungrouped),
          "no grouped/ungrouped rows to exercise")

  # An already ungrouped neuron must read back as NA and register no change.
  # FlyTable reports empty numeric cells as NaN and as.integer("NaN") is 0, so
  # a character round-trip here would make this look like a member of group 0.
  p <- aedes_set_group(ungrouped[1], group = NA, dryrun = TRUE,
                       annotator = FALSE)
  expect_true(is.na(p$group_old))
  expect_true(is.na(p$group_new))
  expect_false(p$changed)

  # Ungrouping a grouped neuron targets NA, so the cell is cleared rather than
  # set to a literal 0 that would read back as a shared group.
  p2 <- suppressWarnings(aedes_set_group(grouped[1], group = NA, dryrun = TRUE,
                                         annotator = FALSE))
  expect_false(is.na(p2$group_old))
  expect_true(is.na(p2$group_new))
  expect_true(p2$changed)
})

test_that("aedes_set_group requires a positive whole group id", {
  am <- try(aedes_meta(), silent = TRUE)
  skip_if(inherits(am, "try-error"), "aedes_meta() unavailable")
  grouped <- am$root_id[!is.na(am$group)]
  skip_if(!length(grouped), "no grouped rows to exercise")

  for (bad in list(0, -5, 1.5))
    expect_error(
      aedes_set_group(grouped[1], group = bad, dryrun = TRUE,
                      annotator = FALSE),
      "positive whole number", fixed = TRUE)
})

test_that("aedes_set_group rejects a root_id-sized `group`", {
  am <- try(aedes_meta(), silent = TRUE)
  skip_if(inherits(am, "try-error"), "aedes_meta() unavailable")

  grouped <- am$root_id[!is.na(am$group)]
  ungrouped <- am$root_id[is.na(am$group)]
  skip_if(!length(grouped) || !length(ungrouped),
          "no grouped/ungrouped rows to exercise")

  # A root_id cannot be a group id (group ids are serial_id-style and fit in an
  # integer). Writing one out would mint a bogus group, so it is an error in
  # either form rather than being silently reinterpreted.
  ref <- as.character(grouped[1])
  for (bad in list(ref, as.numeric(ref)))
    expect_error(
      aedes_set_group(ungrouped[1], group = bad, dryrun = TRUE,
                      annotator = FALSE),
      "too large to be a group id", fixed = TRUE)
})

test_that("aedes_set_group joins the group named by a query", {
  am <- try(aedes_meta(), silent = TRUE)
  skip_if(inherits(am, "try-error"), "aedes_meta() unavailable")

  grouped <- am$root_id[!is.na(am$group)]
  ungrouped <- am$root_id[is.na(am$group)]
  skip_if(!length(grouped) || !length(ungrouped),
          "no grouped/ungrouped rows to exercise")

  ref <- as.character(grouped[1])
  refgroup <- as.integer(am$group[match(ref, as.character(am$root_id))])
  p <- suppressWarnings(
    aedes_set_group(ungrouped[1], group = paste0("root_id:", ref),
                    dryrun = TRUE, annotator = FALSE))
  expect_equal(p$group_new, refgroup)
  expect_true(p$changed)
})
