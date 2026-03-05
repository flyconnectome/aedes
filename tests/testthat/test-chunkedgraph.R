test_that("aedes_supervoxels matches flywire_xyz2id for known live point", {
  pt <- c(24606, 12450, 5798)

  ref <- expect_equal(
    with_aedes(fafbseg::flywire_xyz2id(pt, root = FALSE, rawcoords = T, method="cloudvolume")),
  aedes_supervoxels(pt))
})
