test_that(".aedes_neck_side_xy splits on the tilted neck midline", {
  # midline x = 15456 + 0.328 * y: x 19884 at y 13500, 21524 at y 18500
  expect_identical(.aedes_neck_side_xy(c(19500, 20300), c(13500, 13500)),
                   c("R", "L"))
  expect_identical(.aedes_neck_side_xy(c(21000, 22000), c(18500, 18500)),
                   c("R", "L"))
  expect_identical(.aedes_neck_side_xy(c(NA, 20000), c(15000, NA)),
                   c(NA_character_, NA_character_))
})

test_that(".aedes_neck_point uses the lowest slab and rejects short neurons", {
  xyz <- rbind(c(100, 10, 0), c(300, 30, 40), c(200, 20, 20),
               c(900, 90, 900))
  expect_equal(.aedes_neck_point(xyz, slab = 50), c(200, 20, 20))
  expect_true(all(is.na(.aedes_neck_point(xyz[4, , drop = FALSE]))))
  expect_true(all(is.na(.aedes_neck_point(matrix(numeric(0), ncol = 3)))))
})

test_that("aedes_neck_side finds the right neck side for a live AN", {
  # L2 node inside an AN entering the right side of the neck (2026-10-07)
  id <- try(aedes_xyz2id(c(19175, 15697, 200), rawcoords = TRUE),
            silent = TRUE)
  skip_if(inherits(id, "try-error"), "Skipping: unable to reach CAVE")
  ns <- try(aedes_neck_side(id), silent = TRUE)
  skip_if(inherits(ns, "try-error"), "Skipping: unable to reach L2 cache")
  expect_identical(ns$side, "R")
  expect_match(ns$neck_xyz, "^[0-9]+,[0-9]+,[0-9]+$")
})
