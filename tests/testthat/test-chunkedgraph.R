test_that("aedes_xyz2id auto matches cloudvolume for ids", {
  pt <- c(24606, 12450, 5798)

  # root ids
  got <- try(aedes_xyz2id(pt, rawcoords = TRUE, method = "auto", version=333), silent = TRUE)
  skip_if(inherits(got, "try-error"), "Skipping: transform service unavailable")

  expect_equal(got, '648518347566403105')
  expect_equal(
    aedes_xyz2id('393696 199200 260910', rawcoords = F, version=333),
    '648518347566403105')

  pts <- rbind(pt, c(NA, NA, NA))
  expect_equal(
    aedes_xyz2id(pts, rawcoords = T, version=333),
    c('648518347566403105', '0'))

  # supervoxel_ids
  sv <- try(aedes_xyz2id(pt, rawcoords = TRUE, root = FALSE, method = "cloudvolume"), silent = TRUE)
  skip_if(inherits(sv, "try-error"), "Skipping: cloudvolume service unavailable")

  expect_equal(aedes_xyz2id(pt, rawcoords = TRUE, root = FALSE), sv)

  expect_equal(
    aedes_xyz2id(pt, rawcoords = TRUE, root = FALSE, integer64 = T),
    fafbseg::flywire_ids(sv, integer64 = T))
})
