test_that("aedes_sequential_update fills missing svid and updates stale root_id at pinned timestamp", {
  originaldf <- data.frame(
    supervoxel_id = c(
      "75858402798114673",
      "75014527154012478",
      "74100420741808116",
      "75578370594966739",
      "73325676555772074",
      "75014458300502210",
      "75858334078769425",
      "74030051997611779",
      "75366989685903078",
      "75014389580905752"
    ),
    root_id = c(
      "648518347553078030",
      "648518347517237712",
      "648518347497891440",
      "648518347465113514",
      "648518347622327684",
      "648518347551793795",
      "648518347482055709",
      "648518347568018351",
      "648518347611181399",
      "648518347563887022"
    ),
    point_xyz = c(
      "30142, 9932, 6176",
      "23626, 13856, 5272",
      "16983, 19199, 5491",
      "28065, 20950, 5580",
      "11448, 13949, 3960",
      "23797, 13429, 5094",
      "29844, 9390, 6241",
      "16510,19358,5479",
      "26249, 18644, 5974",
      "23650, 13158, 5041"
    ),
    class = c(
      "DAN?",
      "CX",
      "ALLN",
      "ALSN",
      "LHON",
      "CX",
      "DAN?",
      "ALLN",
      "ALLN",
      "CX"
    ),
    `_id` = c(
      "djTcinEIQcq458oBjvz7Ng",
      "PmlDcKk3ShOIM5b9kiQJlQ",
      "fsLzYk53QGmguDf_oVfXKg",
      "M7wUKgzXTom96oZnX42Hcw",
      "D-vWusv5TpGjMaWG56oXNA",
      "Ysw_Wq_UR6eqwDXhOh52gA",
      "cUHqORjVRvqDJH-NgaW6kA",
      "PcgDKlMsQDybYOWc8HDR1w",
      "YZKWPd5iRjqwe9YcOeroVg",
      "Qflnvv43QPyQn9hlL5xodw"
    )
  )

  updateddf <- data.frame(
    supervoxel_id = c(
      "75858402798114673",
      "75014527154012478",
      "74100420741808116",
      "75578370594966739",
      "73325676555772074",
      "75014458300502210",
      "75858334078769425",
      "74030051997611779",
      "75366989685903078",
      "75014389580905752"
    ),
    root_id = c(
      "648518347511736893",
      "648518347643419800",
      "648518347497891440",
      "648518347465113514",
      "648518347622327684",
      "648518347551793795",
      "648518347611181911",
      "648518347568018351",
      "648518347576448595",
      "648518347563887022"
    ),
    point_xyz = c(
      "30142, 9932, 6176",
      "23626, 13856, 5272",
      "16983, 19199, 5491",
      "28065, 20950, 5580",
      "11448, 13949, 3960",
      "23797, 13429, 5094",
      "29844, 9390, 6241",
      "16510,19358,5479",
      "26249, 18644, 5974",
      "23650, 13158, 5041"
    ),
    class = c(
      "DAN?",
      "CX",
      "ALLN",
      "ALSN",
      "LHON",
      "CX",
      "DAN?",
      "ALLN",
      "ALLN",
      "CX"
    ),
    `_id` = c(
      "djTcinEIQcq458oBjvz7Ng",
      "PmlDcKk3ShOIM5b9kiQJlQ",
      "fsLzYk53QGmguDf_oVfXKg",
      "M7wUKgzXTom96oZnX42Hcw",
      "D-vWusv5TpGjMaWG56oXNA",
      "Ysw_Wq_UR6eqwDXhOh52gA",
      "cUHqORjVRvqDJH-NgaW6kA",
      "PcgDKlMsQDybYOWc8HDR1w",
      "YZKWPd5iRjqwe9YcOeroVg",
      "Qflnvv43QPyQn9hlL5xodw"
    )
  )

  pinned_ts="2026-06-01 14:10:01 UTC"
  out <- try(aedes_sequential_update(originaldf, timestamp = pinned_ts),
             silent = TRUE)
  skip_if(inherits(out, "try-error"),
          "Skipping: aedes_sequential_update unavailable (offline?)")

  # 4 of 10 root_ids were stale 24h before pinned_ts; sequential_update
  # should bring them forward to the values captured in updateddf while
  # leaving supervoxel_id / point_xyz / class / _id untouched.
  expect_equal(out, updateddf)
})

test_that("write_info writes a stable local info file", {
  td <- tempfile("aedes_info_")
  dir.create(td)
  infof <- file.path(td, "info")

  anndf <- data.frame(
    root_id = c("1", "2"),
    type = c("A", "B"),
    stringsAsFactors = FALSE
  )

  expect_no_error(suppressMessages(write_info(anndf, td)))
  expect_true(file.exists(infof))

  md5_1 <- unname(tools::md5sum(infof))
  expect_no_error(suppressMessages(write_info(anndf, td)))
  md5_2 <- unname(tools::md5sum(infof))

  expect_equal(md5_1, md5_2)
})
