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

test_that("aedes_mirror landmarks method mirrors points from explicit landmarks", {
  pts_a <- rbind(
    c(0, 0, 0),
    c(0, 1, 0),
    c(0, 0, 1),
    c(0, 1, 1)
  )
  pts_b <- pts_a
  pts_b[, 1] <- 10

  mirrored <- aedes_mirror(
    rbind(c(2, 0.5, 0.5), c(8, 0.5, 0.5)),
    method = "landmarks",
    landmarks = list(pointA = pts_a, pointB = pts_b),
    raw = FALSE
  )

  expect_equal(unname(mirrored), rbind(c(8, 0.5, 0.5), c(2, 0.5, 0.5)))
})

test_that("aedes_mirror landmarks method respects nm units for raw landmarks", {
  pts_a <- rbind(
    c(0, 0, 0),
    c(0, 1, 0),
    c(0, 0, 1),
    c(0, 1, 1)
  )
  pts_b <- pts_a
  pts_b[, 1] <- 5

  mirrored <- aedes_mirror(
    rbind(c(2, 0.5, 0.5), c(8, 0.5, 0.5)),
    method = "landmarks",
    units = "nm",
    landmarks = list(pointA = pts_a, pointB = pts_b),
    raw = TRUE,
    vd = c(2, 1, 1)
  )

  expect_equal(unname(mirrored), rbind(c(8, 0.5, 0.5), c(2, 0.5, 0.5)))
  expect_equal(
    unname(aedes_mirror(
      rbind(c(2, 0.5, 0.5), c(8, 0.5, 0.5)),
      method = "landmarks",
      landmarks = list(pointA = pts_a, pointB = pts_b),
      raw = TRUE,
      vd = c(2, 1, 1)
    )),
    unname(mirrored)
  )
})

test_that("internal landmarks mirror registration validates input", {
  expect_error(
    aedes:::.aedes_mirror_reg_landmarks(landmarks = list(pointA = diag(3)), raw = FALSE),
    "pointA.*pointB"
  )
})

test_that("suggested package check reports missing packages clearly", {
  expect_error(
    aedes:::check_package_available("definitelynotapackage"),
    "Please install suggested package: definitelynotapackage"
  )
})

test_that("aedes_mirror tps method mirrors through bundled registration", {
  pts <- rbind(c(100, 200, 150), c(300, 250, 120))

  mirrored <- aedes_mirror(pts, method = "tps")

  expect_equal(dim(mirrored), dim(pts))
  expect_true(all(is.finite(mirrored)))
  expect_false(isTRUE(all.equal(unname(mirrored), unname(pts))))
})

test_that("aedes_mirror defaults to tps method", {
  pts <- rbind(c(100, 200, 150), c(300, 250, 120))

  expect_equal(
    unname(aedes_mirror(pts)),
    unname(aedes_mirror(pts, method = "tps"))
  )
})
