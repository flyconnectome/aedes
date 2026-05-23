## Tests for the read_aedes_neurons / aedes_root_point / aedes_soma_position
## stack. The first two tests are fully offline (synthetic neurons + the
## packaged neuropil mesh). The last test hits FlyTable + the segmentation
## service and is skipped when those are unavailable.

# linear neuron of `n` evenly spaced points from `a` to `b`
.straight_neuron <- function(a, b, n = 5) {
  ts <- seq(0, 1, length.out = n)
  coords <- t(vapply(ts, function(t) (1 - t) * a + t * b,
                     numeric(length(a))))
  swc <- data.frame(
    PointNo = seq_len(n), Label = 0L,
    X = coords[, 1], Y = coords[, 2], Z = coords[, 3],
    W = 1, Parent = c(-1L, seq_len(n - 1L))
  )
  nat::as.neuron(swc)
}


test_that("aedes_root_point with method='point' picks nearest skeleton node", {
  n <- .straight_neuron(c(0, 1e5, 1e5), c(4e4, 1e5, 1e5), n = 5)

  # target near the far end of the neuron
  expect_equal(
    aedes:::aedes_root_point(n, point = c(3.9e4, 1e5, 1e5),
                             method = "point", rval = "idx"),
    5L
  )
  # target at the start
  expect_equal(
    aedes:::aedes_root_point(n, point = c(0, 1e5, 1e5),
                             method = "point", rval = "idx"),
    1L
  )

  # rval = "neuron" actually reroots at that node
  n2 <- aedes:::aedes_root_point(n, point = c(3.9e4, 1e5, 1e5),
                                 method = "point", rval = "neuron")
  expect_equal(nat::rootpoints(n2)[1], 5L)

  # rval = "point" returns xyz of the chosen node
  pt <- aedes:::aedes_root_point(n, point = c(3.9e4, 1e5, 1e5),
                                 method = "point", rval = "point")
  expect_equal(unname(pt), c(4e4, 1e5, 1e5))
})


test_that("aedes_root_point with method='mesh' picks endpoint furthest outside the neuropil", {
  # Two endpoints both outside the neuropil mesh, but at very different depths:
  # `inside_bb` is the bounding-box centre (~15 micron outside due to mesh
  # concavity), `far_corner` is well beyond the mesh extent. Mesh method
  # selects the most-negative signed distance, i.e. furthest outside.
  bb <- apply(t(aedes_neuropil_mesh$vb[1:3, ]), 2, range)
  inside_bb  <- (bb[1, ] + bb[2, ]) / 2
  far_corner <- bb[2, ] + 2e5

  d_in  <- nat::pointsinside(matrix(inside_bb,  ncol = 3),
                             surf = aedes_neuropil_mesh, rval = "dist")
  d_out <- nat::pointsinside(matrix(far_corner, ncol = 3),
                             surf = aedes_neuropil_mesh, rval = "dist")
  expect_lt(d_out, d_in)   # far_corner is more outside than inside_bb

  n <- .straight_neuron(inside_bb, far_corner, n = 5)
  expect_equal(
    aedes:::aedes_root_point(n, mesh = aedes_neuropil_mesh,
                             method = "mesh", rval = "idx"),
    5L
  )

  # auto: when point is NULL but mesh supplied, should fall through to mesh
  expect_equal(
    aedes:::aedes_root_point(n, mesh = aedes_neuropil_mesh,
                             method = "auto", rval = "idx"),
    5L
  )

  # auto: when both supplied, the point takes precedence over the mesh
  expect_equal(
    aedes:::aedes_root_point(n, point = inside_bb,
                             mesh = aedes_neuropil_mesh,
                             method = "auto", rval = "idx"),
    1L
  )
})


test_that(".aedes_dedup_nuclei picks the largest nucleus per root_id and warns", {
  # id "A" has two candidates at *different* positions (volumes 1000 and 5000);
  # id "B" has one.
  nuc <- data.frame(
    pt_root_id  = c("A", "A", "B"),
    pt_position = c("10,10,10", "20,20,20", "30,30,30"),
    volume      = c(1000, 5000, 2000),
    stringsAsFactors = FALSE
  )
  expect_warning(
    picked <- aedes:::.aedes_dedup_nuclei(nuc),
    "1 root id\\(s\\) have >1 nucleus at distinct positions.*largest by volume.*\\bA\\b"
  )
  expect_equal(picked$root_id, c("A", "B"))
  expect_equal(picked[picked$root_id == "A", c("x","y","z")][1, , drop = TRUE],
               list(x = 20, y = 20, z = 20))
  expect_equal(picked[picked$root_id == "B", c("x","y","z")][1, , drop = TRUE],
               list(x = 30, y = 30, z = 30))
})


test_that(".aedes_dedup_nuclei silently collapses positional duplicates", {
  # Mimics the real 648518347517945383 case: two rows at the same position
  # with the same volume (bookkeeping duplicate, not a real choice).
  nuc <- data.frame(
    pt_root_id  = c("A", "A"),
    pt_position = c("488832,112816,158850", "488832,112816,158850"),
    volume      = c(775.9, 775.9),
    stringsAsFactors = FALSE
  )
  expect_silent(picked <- aedes:::.aedes_dedup_nuclei(nuc))
  expect_equal(picked$root_id, "A")
  expect_equal(c(picked$x, picked$y, picked$z), c(488832, 112816, 158850))
})


test_that(".aedes_dedup_nuclei handles a mix of positional and real duplicates", {
  # id "A" has a real choice between (10,10,10) and (20,20,20); the (20,20,20)
  # row also appears twice (bookkeeping dup that should be collapsed).
  # id "B" has only a single positional duplicate (collapsed, no warning).
  nuc <- data.frame(
    pt_root_id  = c("A", "A", "A", "B", "B"),
    pt_position = c("10,10,10", "20,20,20", "20,20,20",
                    "30,30,30", "30,30,30"),
    volume      = c(1000, 5000, 5000, 2000, 2000),
    stringsAsFactors = FALSE
  )
  expect_warning(
    picked <- aedes:::.aedes_dedup_nuclei(nuc),
    "1 root id\\(s\\) have >1 nucleus at distinct positions.*\\bA\\b"
  )
  expect_equal(sort(picked$root_id), c("A", "B"))
  # A's larger (volume 5000) nucleus wins
  expect_equal(picked[picked$root_id == "A", c("x","y","z")][1, , drop = TRUE],
               list(x = 20, y = 20, z = 20))
})


test_that(".aedes_dedup_nuclei falls back to first row when no volume column", {
  nuc <- data.frame(
    pt_root_id  = c("A", "A"),
    pt_position = c("10,10,10", "20,20,20"),
    stringsAsFactors = FALSE
  )
  expect_warning(
    picked <- aedes:::.aedes_dedup_nuclei(nuc),
    "picking the first match"
  )
  expect_equal(picked$root_id, "A")
  expect_equal(c(picked$x, picked$y, picked$z), c(10, 10, 10))
})


test_that(".aedes_dedup_nuclei is a no-op for unique inputs", {
  nuc <- data.frame(
    pt_root_id  = c("A", "B"),
    pt_position = c("10,10,10", "30,30,30"),
    volume      = c(1000, 2000),
    stringsAsFactors = FALSE
  )
  expect_silent(picked <- aedes:::.aedes_dedup_nuclei(nuc))
  expect_equal(picked$root_id, c("A", "B"))
})


test_that("aedes_soma_position returns the expected FlyTable soma for a known id", {
  id <- "648518347399768369"
  # Recorded FlyTable soma_xyz for this neuron (raw voxel coords, 16/16/45 nm).
  expected_raw <- c(16231, 4747, 3051)
  expected_nm  <- aedes_raw2nm(matrix(expected_raw, ncol = 3))[1, ]

  sp_raw <- try(aedes_soma_position(id, units = "raw"), silent = TRUE)
  skip_if(inherits(sp_raw, "try-error") || is.na(sp_raw$source[1]),
          "Skipping: no FlyTable access for test id")

  expect_equal(sp_raw$source, "flytable")
  expect_equal(unname(unlist(sp_raw[, c("x", "y", "z")])), expected_raw)

  # nm units should match the raw round-trip
  sp_nm <- aedes_soma_position(id)
  expect_equal(sp_nm$source, "flytable")
  expect_equal(unname(unlist(sp_nm[, c("x", "y", "z")])), unname(expected_nm))
})


test_that("aedes_soma_position silently collapses real nucleus-table positional duplicates", {
  # Pin a stable handle rather than the root_id, which changes as the
  # segmentation is edited. We use the nucleus position (nm) and resolve to
  # the current root via aedes_xyz2id(); the pt_supervoxel_id
  # 75928357816244469 would work equivalently via fafbseg::flywire_rootid().
  # At the time of writing this point sat inside root 648518347517945383,
  # whose nucleus table had two rows at the same position, same volume.
  pt <- c(488832, 112816, 158850)
  rid <- try(aedes_xyz2id(pt, rawcoords = FALSE), silent = TRUE)
  skip_if(inherits(rid, "try-error") || !is.character(rid) ||
          !nzchar(rid) || identical(rid, "0"),
          "Skipping: unable to resolve test point to a root id")

  sp_probe <- try(aedes_soma_position(rid, method = "nucleus"), silent = TRUE)
  skip_if(inherits(sp_probe, "try-error") || is.na(sp_probe$source[1]),
          "Skipping: nucleus lookup unavailable for this supervoxel")

  # Real assertion: lookup is silent (no dedup warning) and returns finite xyz.
  expect_warning(
    sp <- aedes_soma_position(rid, method = "nucleus"),
    regexp = NA
  )
  expect_equal(sp$source, "nucleus")
  expect_true(all(is.finite(unlist(sp[, c("x","y","z")]))))
})


test_that("read_aedes_neurons reroots 648518347399768369 near its FlyTable soma", {
  id <- "648518347399768369"
  expected_nm <- aedes_raw2nm(matrix(c(16231, 4747, 3051), ncol = 3))[1, ]

  ns <- try(read_aedes_neurons(id, OmitFailures = FALSE), silent = TRUE)
  skip_if(inherits(ns, "try-error") || length(ns) == 0L,
          "Skipping: l2skel/FlyTable service unavailable for test id")

  expect_length(ns, 1L)
  expect_true("soma_source" %in% colnames(ns[, , drop = FALSE]))
  expect_equal(ns[, "soma_source"][1], "flytable")

  # Rerooted root should land near the recorded soma. l2skel node spacing is
  # ~1 micron; allow a generous 10 micron tolerance.
  rp <- nat::rootpoints(ns[[1]])[1]
  root_xyz <- nat::xyzmatrix(ns[[1]])[rp, ]
  d <- sqrt(sum((root_xyz - expected_nm)^2))
  expect_lt(d, 10000)
})
