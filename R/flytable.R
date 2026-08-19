#' Update root_ids and supervoxel_ids from point information as necessary
#'
#' @details Note that point information will only be used if supervoxel
#'   information is missing. Therefore it is essential to delete supervoxel_id
#'   for any rows in which the point_xyz is changed.
#'
#'   By default `root_id`s are brought forward to the current segmentation state
#'   (`timestamp = 'now'`). Callers may instead pin to a specific
#'   materialisation `version` or `timestamp`.
#'
#' @param df A dataframe containing columns root_id, supervoxel_id, point_xyz.
#' @param version Optional materialisation version.
#' @param timestamp Optional CAVE timestamp. Defaults to `'now'` when both
#'   timestamp and version missing.
#' @return A new dataframe with updated ids.
#' @keywords internal
aedes_sequential_update <- function(df, version = NULL, timestamp = NULL) {
  op <- choose_aedes(set = TRUE)
  on.exit(options(op))

  if (is.null(version) && is.null(timestamp)) timestamp <- "now"
  vi <- aedes_get_version(version = version, timestamp = timestamp)

  pts_toupdate = with(df, (is.na(supervoxel_id) | supervoxel_id == 0) & !is.na(point_xyz))
  if (any(pts_toupdate)) {
    df[pts_toupdate, "supervoxel_id"] <-
      aedes_xyz2id(df$point_xyz[pts_toupdate], rawcoords = TRUE, root = FALSE,
                   version = vi$version, timestamp = vi$timestamp)
  }
  df <- df %>% dplyr::mutate(
    root_id = fafbseg::flywire_updateids(.data$root_id, svids = .data$supervoxel_id,
                                         version = vi$version,
                                         timestamp = vi$timestamp)
  )
  df
}

#' Reject a mistaken `dry_run` argument
#'
#' The standard dry-run argument across aedes (and the wider natverse) is
#' `dryrun`. Functions that also take `...` call this so a mistyped `dry_run`
#' errors clearly instead of being silently captured as a column to write.
#' @noRd
.aedes_reject_dry_run <- function(...) {
  bad <- intersect(c("dry_run", "dryRun", "dry.run"), names(list(...)))
  if (length(bad))
    stop("Use `dryrun`, not `", bad[1L], "`.", call. = FALSE)
  invisible(NULL)
}

#' Resolve an annotator/proofreader argument to the tokens to append
#'
#' Accepts `TRUE` (use `getOption("aedes.initials")`), `FALSE`/`NULL` (no-op),
#' or a character vector of one or more initials (comma-joined strings are
#' split, symmetric with how a multi-select cell reads back). Returns `NULL`
#' when nothing should be written to the column, or a non-empty character
#' vector of tokens to append.
#' @noRd
.aedes_resolve_initials <- function(x, argname) {
  if (isFALSE(x) || is.null(x)) return(NULL)
  if (isTRUE(x)) {
    ini <- getOption("aedes.initials")
    if (!is.character(ini) || length(ini) != 1L || is.na(ini) || !nzchar(ini))
      stop("`", argname, " = TRUE` needs `aedes.initials` set. Set once with ",
           "options(aedes.initials = \"XY\") or pass ", argname,
           " = \"XY\" explicitly.", call. = FALSE)
    x <- ini
  }
  if (!is.character(x))
    stop("`", argname, "` must be TRUE, FALSE, or a character vector.",
         call. = FALSE)
  toks <- unlist(strsplit(x, ",", fixed = TRUE), use.names = FALSE)
  toks <- trimws(toks[!is.na(toks) & nzchar(toks)])
  if (!length(toks))
    stop("`", argname, "` has no non-empty initials tokens.", call. = FALSE)
  unique(toks)
}

#' Append (or wipe-and-set) tokens on multi-select column(s) of an update frame
#'
#' Generic per-column merge for FlyTable multi-select cells. `values` names
#' any subset of multi-select columns and gives a character vector of tokens
#' to add. For each `updf` row, the existing cell in `am` (indexed by
#' `root_id`) is read, split on commas if a string, unioned with the new
#' tokens (sorted, deduped) and re-emitted as a comma-joined scalar. Columns
#' with `NULL` tokens are skipped; rows absent from `am` (i.e. new rows) merge
#' against empty and end up with just the new tokens.
#'
#' Empty-cell detection is generous: `NA`, the literal strings `"NA"` and
#' `"NaN"`, and empty/whitespace-only strings all count as empty (matches how
#' comma-collapsed seatable cells sometimes round-trip through CSV / pandas).
#'
#' `wipe = TRUE` replaces the cell with just the new tokens (existing content
#' ignored). `wipe = FALSE` (the default) appends.
#'
#' Output is a plain comma-joined scalar per row -- fafbseg's multi-select
#' write path (`flytable_listify_multiselect_col`) splits it back into a list
#' per cell for the JSON payload, so no `I(list(...))` wrapping is needed here.
#' @noRd
.aedes_append_multiselect <- function(updf, am, values, wipe = FALSE) {
  values <- values[!vapply(values, is.null, logical(1))]
  if (!length(values)) return(updf)
  idx <- match(as.character(updf$root_id), as.character(am$root_id))

  # Drop only actual NA and empty/whitespace-only; treat "NA"/"NaN" as data.
  # Legacy stray "NA" tokens from historical writes will sit until a caller
  # rewrites with wipe = TRUE; we never silently drop what looks like initials.
  clean <- function(x) {
    x <- as.character(x)
    x <- trimws(x[!is.na(x)])
    x[nzchar(x)]
  }
  split_cell <- function(cell) {
    if (is.list(cell)) return(clean(unlist(cell, use.names = FALSE)))
    if (length(cell) == 0L) return(character(0))
    if (length(cell) > 1L) return(clean(cell))
    cell <- as.character(cell)
    if (is.na(cell)) return(character(0))
    clean(strsplit(cell, ",", fixed = TRUE)[[1L]])
  }

  for (col in names(values)) {
    new_tokens <- clean(values[[col]])
    existing <- if (wipe || !col %in% names(am))
      rep(NA, nrow(updf)) else am[[col]][idx]
    updf[[col]] <- vapply(seq_along(existing), function(i) {
      cur <- if (wipe) character(0) else split_cell(existing[[i]])
      paste(sort(unique(c(cur, new_tokens))), collapse = ",")
    }, character(1))
  }
  updf
}

#' Pin a timestamp and read a timestamp-consistent aedes_main
#'
#' Pins a single timestamp, normalises `ids` to root ids at it, and reads
#' `aedes_main` mapped to the same timestamp -- so that join-by-`root_id` is
#' reliable. The table read relies on [aedes_meta()]'s own `version`/`timestamp`
#' mapping (which brings `root_id` forward via `supervoxel_id`); a single pinned
#' `ts` is shared with the id resolution so both sides agree. Shared by
#' [aedes_add_neurons()] and [.aedes_update_existing()].
#'
#' @param ids Root ids in any form understood by [fafbseg::flywire_ids()].
#' @return A list with `ids` (latest root ids), `am` (the mapped table) and
#'   `ts` (the pinned version/timestamp from [aedes_get_version()]).
#' @noRd
.aedes_pin_meta <- function(ids) {
  fids <- setdiff(fafbseg::flywire_ids(ids, unique = TRUE), 0)
  ts <- aedes_get_version(timestamp = "now")
  lids <- with_aedes(fafbseg::flywire_latestid(fids, timestamp = ts$timestamp))
  am <- aedes_meta(version = ts$version, timestamp = ts$timestamp, expiry = 0)
  list(ids = lids, am = am, ts = ts)
}

#' Update existing aedes_main rows from a data.frame of column values
#'
#' @description Shared write engine for updating rows that already exist in
#'   `aedes_main`. Resolves `df$root_id` to the table `_id` in a
#'   timestamp-consistent snapshot and updates exactly the supplied columns on
#'   the matching rows.
#'
#' @details Update-only: ids absent from the table are returned in `missing`
#'   rather than appended -- the caller decides what to do with them. Values are
#'   written verbatim (caller-supplied values always win); any no-overwrite
#'   policy is the caller's responsibility, applied to `df` before calling.
#'
#' @param df A data.frame with a `root_id` column plus the columns to write.
#' @param dryrun If `TRUE` (default) assemble and return the update frame
#'   without writing.
#' @param on_dup What to do when a `root_id` appears more than once among the
#'   matched rows: `"error"` (default) or `"first"` (keep the first occurrence).
#' @param am,ts Optional pre-pinned table and version (see [.aedes_pin_meta()]).
#'   When both are supplied `df$root_id` is assumed already at `ts` and is not
#'   re-resolved (avoids a second table read).
#' @return A list with `updf` (rows written / to write, keyed by `_id`) and
#'   `missing` (root_ids not found in the table).
#' @noRd
.aedes_update_existing <- function(df, dryrun = TRUE, on_dup = c("error", "first"),
                                   am = NULL, ts = NULL) {
  on_dup <- match.arg(on_dup)
  if (!is.data.frame(df) || !"root_id" %in% names(df))
    stop("`df` must be a data.frame with a `root_id` column.", call. = FALSE)
  if (is.null(am) || is.null(ts)) {
    pin <- .aedes_pin_meta(df$root_id)
    df$root_id <- pin$ids
    am <- pin$am
    ts <- pin$ts
  }
  df$root_id <- as.character(df$root_id)
  idx <- match(df$root_id, as.character(am$root_id))
  found <- !is.na(idx)
  missing <- unique(df$root_id[!found])

  df_found <- df[found, , drop = FALSE]
  idx <- idx[found]
  dups <- unique(df_found$root_id[duplicated(df_found$root_id)])
  if (length(dups)) {
    if (on_dup == "error")
      stop("Duplicated root_id(s) in the update set: ",
           paste(utils::head(dups, 5L), collapse = ", "),
           if (length(dups) > 5L) sprintf(" (+%d more)", length(dups) - 5L),
           call. = FALSE)
    keep <- !duplicated(df_found$root_id)
    df_found <- df_found[keep, , drop = FALSE]
    idx <- idx[keep]
  }

  updf <- df_found
  updf[["_id"]] <- am[["_id"]][idx]
  updf <- updf[c("_id", setdiff(names(updf), "_id"))]
  rownames(updf) <- NULL
  if (any(duplicated(updf[["_id"]])))
    stop("Multiple root_ids map to the same aedes_main row (`_id`).", call. = FALSE)

  if (!dryrun && nrow(updf) > 0L)
    fafbseg::flytable_update_rows(updf, table = "aedes_main", append_allowed = FALSE)
  list(updf = updf, missing = missing)
}

#' Update ids in aedes_main table manually
#'
#' @param update.serial_ids Whether to update the serial_id column uniquely
#'   defining each row. This is off by default as the serial_id is
#'   auto-incremented by the server.
#' @param update_dups Whether to update rows with "duplicate" status (now the
#'   default) and also set the root_duplicated column.
#' @param dry_run Whether to show what would happen rather than doing it.
#'
#' @details This is now part of the scripted updates on flyem but even in future
#'   it may occasionally be useful to trigger this manually.
#'
#'   Expert use only: there is a scheduled job that updates root IDs on FlyTable
#'   every 30 minutes, so this function should normally not be needed.
#'
#'   The root_duplicated column will only be ticked for root_ids when there is
#'   more than one entry \emph{after} setting aside any rows with
#'   status=duplicate.
#'
#' @return Invisibly, a list describing what was (or, under `dry_run`, would be)
#'   written: `updated`, a data frame of changed `aedes_main` rows (`_id`,
#'   `root_id`, `supervoxel_id`, `root_duplicated`), and `serial_ids`, a data
#'   frame of `_id` + newly assigned `serial_id` (or `NULL` when no serial ids
#'   were assigned, e.g. the default `update.serial_ids = FALSE`).
#' @keywords internal
aedes_flytable_update <- function(update.serial_ids = FALSE, update_dups = TRUE, dry_run = FALSE) {
  aedes_main = fafbseg::flytable_query("select `_id`, root_id, supervoxel_id, point_xyz, serial_id, root_duplicated, status from aedes_main")
  cands <- if (update_dups) {
    dplyr::select(aedes_main, dplyr::all_of(c("_id", "root_id", "supervoxel_id", "point_xyz", "root_duplicated", "status")))
  } else {
    aedes_main %>%
      dplyr::filter(.data$status != "duplicate" | is.na(.data$status)) %>%
      dplyr::select(dplyr::all_of(c("_id", "root_id", "supervoxel_id", "point_xyz")))
  }

  updated = aedes_sequential_update(cands)
  if (update_dups) {
    # unchecked checkbox cells come back as NA; treat as FALSE so unchanged
    # rows don't all read as "changed" against the computed logical column.
    rd <- as.logical(cands$root_duplicated)
    rd[is.na(rd)] <- FALSE
    cands$root_duplicated <- rd
    updated <- updated %>%
      dplyr::mutate(good_status = is.na(.data$status) | .data$status != "duplicate") %>%
      dplyr::group_by(.data$root_id, .data$good_status) %>%
      dplyr::mutate(n = dplyr::n()) %>%
      dplyr::ungroup() %>%
      dplyr::mutate(root_duplicated = dplyr::case_when(
        # NA root_ids are not a real group -- we don't know their identity, so
        # never flag them as duplicated (they'll only be written to clear a
        # previously-set TRUE).
        is.na(.data$root_id) ~ FALSE,
        .data$good_status ~ .data$n > 1,
        TRUE ~ FALSE
      )) %>%
      dplyr::select(-dplyr::all_of(c("n", "good_status")))
  }
  changed_cells = (updated != cands) | (is.na(cands) & !is.na(updated))
  changed_rows = rowSums(changed_cells, na.rm = TRUE) > 0
  n_changed = sum(changed_rows)
  # Only write the columns this function can actually change. In particular the
  # human-curated `status` (and `point_xyz`) columns are never in the payload,
  # so they are never rewritten -- even for rows updated for other reasons.
  mutable <- intersect(c("_id", "root_id", "supervoxel_id", "root_duplicated"),
                       names(updated))
  toupdate <- updated[changed_rows, mutable, drop = FALSE]
  if (n_changed > 0) {
    if (dry_run)
      message("dry run: there are ", n_changed, " changed aedes seatable rows.")
    else {
      message("Updating ", n_changed, " aedes seatable rows.")
      fafbseg::flytable_update_rows(toupdate, table = "aedes_main")
    }
  }

  serial_toupdate = NULL
  missing_serial = aedes_main %>%
    dplyr::select(dplyr::all_of(c("_id", "serial_id"))) %>%
    dplyr::filter(is.na(.data$serial_id))
  if (isTRUE(nrow(missing_serial) > 0)) {
    if (isFALSE(update.serial_ids)) {
      message("Not updating ", nrow(missing_serial), " aedes serial_ids.")
    } else {
      last_serial = max(as.integer(aedes_main$serial_id), na.rm = TRUE)
      # check how many digits and zero pad if necessary
      tn=table(nchar(aedes_main$serial_id))
      ndigits=names(which.max(tn))
      formatstr=paste0('%0', ndigits, 'd')
      missing_serial$serial_id = sprintf(
        formatstr,
        seq_len(nrow(missing_serial)) + last_serial)
      serial_toupdate = missing_serial
      if (dry_run)
        message("dry run: there are ", nrow(missing_serial), " aedes serial_ids to update.")
      else {
        message("Updating ", nrow(missing_serial), " aedes serial_ids.")
        fafbseg::flytable_update_rows(missing_serial, table = "aedes_main")
      }
    }
  }
  invisible(list(updated = toupdate, serial_ids = serial_toupdate))
}

#' Write annotations to neuroglancer info file
#'
#' @param anndf Annotation data frame
#' @param dir Output directory
#' @noRd
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
