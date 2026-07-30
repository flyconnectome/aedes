aedes_pt <- function() matrix(c(390, 260, 110), ncol = 3)

test_that("xform_aedes moves points between Aedes and FlyWire space", {
  skip_if_not_installed("Morpho")
  pt <- aedes_pt()

  fly <- xform_aedes(pt, sample = "aedes", reference = "FlyWire", units = "microns")

  expect_equal(dim(fly), dim(pt))
  expect_true(all(is.finite(fly)))
  # the two brains sit in different coordinate frames, so the point must move
  expect_gt(sqrt(sum((fly - pt)^2)), 1)
})

test_that("xform_aedes round trips within the registration's accuracy", {
  skip_if_not_installed("Morpho")
  pt <- aedes_pt()

  rt <- xform_aedes(
    xform_aedes(pt, sample = "aedes", reference = "FlyWire", units = "microns"),
    sample = "FlyWire", reference = "aedes", units = "microns"
  )

  # each direction is an independent fit, so a round trip is not exact;
  # median round-trip error across the brain is ~10 um (see ?xform_aedes)
  expect_lt(sqrt(sum((rt - pt)^2)), 50)
})

test_that("xform_aedes nm and micron paths agree", {
  skip_if_not_installed("Morpho")
  pt <- aedes_pt()

  fly_um <- xform_aedes(pt, sample = "aedes", reference = "FlyWire", units = "microns")
  fly_nm <- xform_aedes(pt * 1e3, sample = "aedes", reference = "FlyWire", units = "nm")

  expect_equal(unname(fly_nm), unname(fly_um * 1e3))
})

test_that("xform_aedes bridges beyond FlyWire to a template brain", {
  skip_if_not_installed("Morpho")
  skip_if_not_installed("nat.templatebrains")
  skip_if_not_installed("nat.jrcbrains")

  jrc <- xform_aedes(aedes_pt(), sample = "aedes", reference = "JRC2018F", units = "microns")

  expect_true(all(is.finite(jrc)))
  # JRC2018F spans roughly 628 x 292 x 182 um; a central brain point lands inside
  expect_true(all(jrc > 0))
  expect_lt(jrc[1], 628)
  expect_lt(jrc[2], 292)
})

test_that("xform_aedes requires exactly one side to be aedes", {
  expect_snapshot(
    error = TRUE,
    xform_aedes(aedes_pt(), sample = "FlyWire", reference = "JRC2018F")
  )
  expect_snapshot(
    error = TRUE,
    xform_aedes(aedes_pt(), sample = "aedes", reference = "aedes")
  )
})
