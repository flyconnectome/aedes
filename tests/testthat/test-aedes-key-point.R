test_id <- "648518347399768369"

test_that("key_point_from_neuron picks a finite point on a stored L2 skeleton", {
  f <- system.file("extdata",
                   "test_l2skel_648518347399768369.rds",
                   package = "aedes")
  expect_true(nzchar(f) && file.exists(f))
  n <- readRDS(f)
  expect_s3_class(n, "neuron")

  pt <- key_point_from_neuron(n, reroot = TRUE)
  expect_length(as.numeric(pt), 3L)
  expect_true(all(is.finite(pt)))

  # the chosen nm xyz must lie within the bounding box of the input neuron
  xyz <- nat::xyzmatrix(n)
  bb <- apply(xyz, 2, range)
  pt3 <- as.numeric(pt)
  expect_true(all(pt3 >= bb[1, ] & pt3 <= bb[2, ]))

  # rerooting onto the furthest endpoint should be deterministic for the
  # same input, and (typically) different from no-reroot when the original
  # root is itself a branch-bearing node.
  pt_again <- key_point_from_neuron(n, reroot = TRUE)
  expect_equal(pt_again, pt)
})

test_that("aedes_key_point returns a raw-space point for a known id", {
  pt <- try(aedes_key_point(test_id), silent = TRUE)
  skip_if(inherits(pt, "try-error") || any(is.na(pt)),
          "Skipping: L2 skeleton unavailable")

  m <- if (is.matrix(pt)) pt else matrix(pt, nrow = 1)
  expect_equal(dim(m), c(1L, 3L))
  expect_true(all(is.finite(m)))
  # raw aedes voxel coords are positive; tighter bounds would bake in the
  # current 16,16,45 nm voxel size, which isn't what we're testing here.
  expect_true(all(m > 0))

  # raw=FALSE returns nm; should differ from raw
  pt_nm <- try(aedes_key_point(test_id, raw = FALSE), silent = TRUE)
  skip_if(inherits(pt_nm, "try-error") || any(is.na(pt_nm)),
          "Skipping: L2 skeleton unavailable for raw=FALSE branch")
  m_nm <- if (is.matrix(pt_nm)) pt_nm else matrix(pt_nm, nrow = 1)
  expect_false(isTRUE(all.equal(as.numeric(m), as.numeric(m_nm))))
})
