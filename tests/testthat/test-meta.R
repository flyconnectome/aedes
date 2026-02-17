test_that("aedes_set_version updates package option", {
  old <- getOption("aedes.version")
  on.exit(options(aedes.version = old), add = TRUE)

  aedes_set_version("latest")
  expect_equal(getOption("aedes.version"), "latest")

  aedes_set_version("now")
  expect_equal(getOption("aedes.version"), "now")
})

cam_meta_aedes <- function(...) {
  fafbseg::cam_meta(..., table = "aedes_main")
}

expect_meta_core_equal <- function(a, b) {
  common_cols <- intersect(names(a), names(b))
  core_cols <- intersect(c("root_id", "supervoxel_id", "type", "class", "subclass", "side", "status"), common_cols)
  if (length(core_cols) == 0L) {
    fail("No shared core columns to compare")
  }
  a2 <- a[, core_cols, drop = FALSE]
  b2 <- b[, core_cols, drop = FALSE]
  a2 <- a2[order(as.character(a2$root_id)), , drop = FALSE]
  b2 <- b2[order(as.character(b2$root_id)), , drop = FALSE]
  expect_equal(a2, b2, ignore_attr = TRUE)
}

probe_aedes_main <- function() {
  probe <- try(fafbseg::flytable_query(
    "select root_id, class, type from aedes_main WHERE status NOT IN ('duplicate', 'bad_nucleus')"
  ), silent = TRUE)
  skip_if(inherits(probe, "try-error") || !is.data.frame(probe) || nrow(probe) < 10,
          "Skipping: no aedes_main table access")
  probe
}

test_that("aedes_get_version returns version/timestamp list", {
  res <- try(aedes_get_version(version = "latest"), silent = TRUE)
  skip_if(inherits(res, "try-error"), "Skipping: unable to resolve CAVE version context")

  expect_type(res, "list")
  expect_named(res, c("version", "timestamp"))
})

test_that("aedes_meta query returns data frame when table access exists", {
  df <- try(aedes_meta("class:ALPN"), silent = TRUE)
  skip_if(inherits(df, "try-error") || !is.data.frame(df), "Skipping: no FlyTable metadata access to aedes_main")

  expect_s3_class(df, "data.frame")
  expect_true("root_id" %in% names(df))
})


test_that("aedes_ids resolves ids when metadata access is available", {
  ids <- try(aedes_ids("class:ALPN"), silent = TRUE)
  skip_if(inherits(ids, "try-error") || length(ids) < 1, "Skipping: no FlyTable metadata access for aedes_ids query")

  expect_true(length(ids) >= 1)
})

test_that("aedes_meta and cam_meta agree for fixed class query", {
  probe <- probe_aedes_main()
  cls <- probe$class[which(!is.na(probe$class))[1]]
  skip_if(is.na(cls) || !nzchar(cls), "Skipping: no non-missing class values in probe data")

  query <- paste0("class:", cls)
  got <- try(aedes_meta(query, fixed = TRUE, unique = FALSE), silent = TRUE)
  ref <- try(cam_meta_aedes(query, fixed = TRUE, unique = FALSE), silent = TRUE)
  skip_if(inherits(ref, "try-error") || inherits(got, "try-error"), "Skipping: no metadata access for query comparison")

  expect_setequal(as.character(got$root_id), as.character(ref$root_id))
  expect_meta_core_equal(got, ref)
})

test_that("aedes_meta and cam_meta agree for slash-prefixed query", {
  probe <- probe_aedes_main()
  cls <- probe$class[which(!is.na(probe$class))[1]]
  skip_if(is.na(cls) || !nzchar(cls), "Skipping: no non-missing class values in probe data")

  query <- paste0("/class:", cls)
  got <- try(aedes_meta(query, fixed = TRUE, unique = FALSE), silent = TRUE)
  ref <- try(cam_meta_aedes(query, fixed = TRUE, unique = FALSE), silent = TRUE)
  skip_if(inherits(ref, "try-error") || inherits(got, "try-error"), "Skipping: no metadata access for slash query comparison")

  expect_setequal(as.character(got$root_id), as.character(ref$root_id))
  expect_meta_core_equal(got, ref)
})

test_that("aedes_meta and cam_meta agree for explicit root_id subset", {
  probe <- probe_aedes_main()
  seed_ids <- unique(head(probe$root_id[!is.na(probe$root_id)], 10))
  skip_if(length(seed_ids) < 5, "Skipping: insufficient root IDs in probe data")

  got <- try(aedes_meta(seed_ids, unique = FALSE), silent = TRUE)
  ref <- try(cam_meta_aedes(seed_ids, unique = FALSE), silent = TRUE)
  skip_if(inherits(ref, "try-error") || inherits(got, "try-error"), "Skipping: no metadata access for id subset comparison")

  expect_setequal(as.character(got$root_id), as.character(ref$root_id))
  expect_meta_core_equal(got, ref)
})

test_that("aedes_meta and cam_meta unique mode agree on row ids", {
  probe <- probe_aedes_main()
  cls <- probe$class[which(!is.na(probe$class))[1]]
  skip_if(is.na(cls) || !nzchar(cls), "Skipping: no non-missing class values in probe data")
  query <- paste0("class:", cls)

  got <- try(aedes_meta(query, fixed = TRUE, unique = TRUE), silent = TRUE)
  ref <- try(cam_meta_aedes(query, fixed = TRUE, unique = TRUE), silent = TRUE)
  skip_if(inherits(ref, "try-error") || inherits(got, "try-error"), "Skipping: no metadata access for unique mode comparison")

  expect_setequal(as.character(got$root_id), as.character(ref$root_id))
})
