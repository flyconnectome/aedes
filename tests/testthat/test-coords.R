test_that("aedes_nm2raw and aedes_raw2nm are inverse for explicit voxel dims", {
  pts_nm <- rbind(c(1000, 2000, 3000), c(1500, 2500, 3500))
  vd <- c(2, 4, 5)

  pts_raw <- aedes_nm2raw(pts_nm, vd = vd)
  pts_nm_rt <- aedes_raw2nm(pts_raw, vd = vd)

  expect_equal(unname(pts_nm_rt), unname(pts_nm))
})

test_that("aedes_voxdims returns a numeric 3-vector", {
  vd <- try(aedes_voxdims(), silent = TRUE)
  skip_if(inherits(vd, "try-error"), "Skipping: unable to fetch voxel dimensions")

  expect_type(vd, "double")
  expect_length(vd, 3)
  expect_true(all(is.finite(vd)))
})
