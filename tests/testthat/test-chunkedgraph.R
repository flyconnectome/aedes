test_that("aedes_xyz2id auto matches cloudvolume for ids", {
  pt <- c(24606, 12450, 5798)

  # root ids
  got <- try(aedes_xyz2id(pt, rawcoords = TRUE, method = "auto", version=333), silent = TRUE)
  skip_if(inherits(got, "try-error"), "Skipping: transform service unavailable")

  expect_equal(got, '648518347566403105')
  # check string input can work as well
  expect_equal(aedes_xyz2id('24606, 12450, 5798', rawcoords = TRUE, version=333), got)
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

test_that("aedes_supervoxels preserves length when chunks fail", {
  pt <- c(24606, 12450, 5798)
  sv1 <- try(aedes_xyz2id(pt, rawcoords = TRUE, root = FALSE), silent = TRUE)
  skip_if(inherits(sv1, "try-error"), "Skipping: transform service unavailable")

  # 5 copies of same point plus one bad point, with chunksize=2 to force
  # multiple chunks and ensure a failure doesn't shift results
  pts <- rbind(
    matrix(pt, ncol = 3),
    matrix(c(0, 0, 0), ncol = 3),
    matrix(rep(pt, 4), ncol = 3, byrow = TRUE)
  )
  res <- suppressWarnings(
    aedes:::aedes_supervoxels(pts, chunksize = 2L)
  )
  expect_length(res, nrow(pts))
  expect_equal(unname(res[1]), sv1)
  expect_equal(unname(res[3:6]), rep(sv1, 4))
})

test_that("aedes_supervoxels returns correct length even when a chunk errors", {
  fake_svone <- function(pts, ...) {
    # fail for any point where x == -1
    if (any(pts[, 1] == -1))
      stop("simulated failure")
    rep("123", nrow(pts))
  }
  local_mocked_bindings(
    aedes_supervoxels_one = fake_svone,
    .package = "aedes"
  )
  # rows 3-4 will always fail since x == -1
  pts <- matrix(c(
    1, 1, 1,
    1, 1, 1,
    -1, 1, 1,
    -1, 1, 1,
    1, 1, 1,
    1, 1, 1
  ), ncol = 3, byrow = TRUE)
  res <- suppressMessages(suppressWarnings(
    aedes:::aedes_supervoxels(pts, chunksize = 2L)
  ))
  # must always return exactly nrow(pts) values
  expect_length(res, 6L)
  # good rows get "123", failed rows stay "0"
  expect_equal(unname(res), c("123", "123", "0", "0", "123", "123"))
})
