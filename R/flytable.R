sequential_update <- function(df) {
  op <- choose_aedes(set = TRUE)
  on.exit(options(op))

  pts_toupdate = with(df, (is.na(supervoxel_id) | supervoxel_id == 0) & !is.na(point_xyz))
  if (any(pts_toupdate)) {
    df[pts_toupdate, "supervoxel_id"] <-
      with(df[pts_toupdate, , drop = FALSE],
           fafbseg::flywire_xyz2id(point_xyz, rawcoords = TRUE, root = FALSE,
                                   voxdims = c(16, 16, 45), method = "cloud"))
  }
  df <- df %>% dplyr::mutate(
    root_id = fafbseg::flywire_updateids(root_id, svids = supervoxel_id)
  )
  df
}

aedes_flytable_update <- function(update.serial_ids = TRUE, update_dups = TRUE, dry_run = FALSE) {
  aedes_main = fafbseg::flytable_query("select `_id`, root_id, supervoxel_id, point_xyz, serial_id, root_duplicated, status from aedes_main")
  cands <- if (update_dups) {
    dplyr::select(aedes_main, `_id`, root_id, supervoxel_id, point_xyz, root_duplicated, status)
  } else {
    aedes_main %>%
      dplyr::filter(status != "duplicate" | is.na(status)) %>%
      dplyr::select(`_id`, root_id, supervoxel_id, point_xyz)
  }

  updated = sequential_update(cands)
  if (update_dups) {
    updated <- updated %>%
      dplyr::mutate(good_status = is.na(status) | status != "duplicate") %>%
      dplyr::add_count(root_id, good_status) %>%
      dplyr::mutate(root_duplicated = dplyr::case_when(
        good_status ~ n > 1,
        TRUE ~ FALSE
      )) %>%
      dplyr::select(-n, -good_status)
  }
  changed_cells = (updated != cands) | (is.na(cands) & !is.na(updated))
  changed_rows = rowSums(changed_cells, na.rm = TRUE) > 0
  n_changed = sum(changed_rows)
  if (n_changed > 0) {
    if (dry_run)
      message("dry run: there are ", n_changed, " changed aedes seatable rows.")
    else {
      message("Updating ", n_changed, " aedes seatable rows.")
      fafbseg::flytable_update_rows(updated[changed_rows, , drop = FALSE], table = "aedes_main")
    }
  }

  missing_serial = aedes_main %>%
    dplyr::select(`_id`, serial_id) %>%
    dplyr::filter(is.na(serial_id))
  if (isTRUE(nrow(missing_serial) > 0)) {
    if (isFALSE(update.serial_ids)) {
      message("Not updating ", nrow(missing_serial), " aedes serial_ids.")
      return(invisible(FALSE))
    }
    last_serial = max(aedes_main$serial_id, na.rm = TRUE)
    missing_serial$serial_id = seq_len(nrow(missing_serial)) + last_serial
    if (dry_run)
      message("dry run: there are ", nrow(missing_serial), " aedes serial_ids to update.")
    else {
      message("Updating ", nrow(missing_serial), " aedes serial_ids.")
      fafbseg::flytable_update_rows(missing_serial, table = "aedes_main")
    }
  }
  invisible(TRUE)
}

write_info <- function(anndf, dir) {
  dir = normalizePath(dir)
  if (!file.exists(dir))
    dir.create(dir, recursive = TRUE)
  finalf = file.path(dir, "info")
  f <- tempfile(pattern = "info")
  if (!file.exists(finalf)) {
    update = TRUE
    oldmd5 = NA
  } else {
    update = NA
    oldmd5 = tools::md5sum(finalf)
  }
  fafbseg::write_nginfo(anndf, f = f, sep = "_")
  if (!isTRUE(update)) {
    newmd5 = tools::md5sum(f)
    update = !isTRUE(newmd5 == oldmd5)
  }
  if (update) {
    message("New version of info file has been written")
    file.copy(f, finalf, overwrite = TRUE)
  } else {
    message("info file unchanged")
  }
}
