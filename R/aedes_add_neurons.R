#' Add new neurons (and update existing ones) in the aedes_main flytable
#'
#' @description Brings the supplied `ids` to the current segmentation timestamp,
#'   reads the `aedes_main` table fresh, and pins both sides to the same
#'   timestamp via [aedes_sequential_update()] so that join-by-`root_id` is
#'   reliable. Rows whose `root_id` is already present are updated with any
#'   extra columns supplied via `...`; rows that are absent are appended with a
#'   `point_xyz` computed by [aedes_key_point()]. `supervoxel_id` and
#'   `serial_id` are left blank -- a server-side process fills them in from
#'   `point_xyz`.
#'
#' @details By default the function also auto-fills `soma_xyz`, `nucleus_id`
#'   and `side` for each row via [aedes_soma_position()] and
#'   [aedes_point_side()]. When the soma cascade returns no position for an id
#'   the fallback for `side` is [aedes_point_side()] on the L2 key point, and
#'   a warning naming the affected ids is issued.
#'
#'   Auto-fill columns (`soma_xyz`, `nucleus_id`, `side`, `point_xyz`) never
#'   overwrite a non-NA value on an existing row. Values passed via `...`
#'   always win over the auto-fill and always overwrite on existing rows.
#'
#' @param ids Root ids of neurons to add or update.
#' @param dryrun If `TRUE` (the default) no writes are performed; the function
#'   returns the data frames that would have been used.
#' @param ... Additional columns to set on each row (e.g. `cell_class = "KC"`).
#'   Recycled across all input ids. Values here always win over the auto-fill
#'   below.
#' @param soma If `TRUE` (the default), auto-fill `soma_xyz` and `nucleus_id`
#'   from [aedes_soma_position()].
#' @param side If `TRUE` (the default), auto-fill `side` from
#'   [aedes_point_side()] applied to the soma; falls back to the L2 key point
#'   (with a warning) for ids where the soma cascade returns nothing.
#' @param status FlyTable status. A shortlist of the common values is exposed
#'   in the signature for tab-completion. Any other value is live-checked
#'   against the vocabulary already present in `aedes_main`; unknown values
#'   error. Must be supplied unless `"status"` is removed from `required`.
#' @param required Columns that must be supplied (via `...`, or via `status` /
#'   `initials`). Defaults to `c("superclass", "status", "initials")`. Set to
#'   `character(0)` to skip the check.
#' @param initials Curator initials. Defaults to
#'   `getOption("aedes.initials")`; set once per session with
#'   `options(aedes.initials = "XY")`. Passed through `...` semantics -- an
#'   explicit `initials = ...` in `...` wins over the option.
#' @return A list. With `dryrun = TRUE` it has elements `up` (rows that would
#'   be updated) and/or `new` (rows that would be appended). With
#'   `dryrun = FALSE` only `new` is returned (so the caller can see which
#'   `point_xyz` values were chosen).
#' @export
aedes_add_neurons <- function(ids, dryrun = TRUE, ...,
                              soma = TRUE, side = TRUE,
                              status = c("adequate", "to_review",
                                         "needs_extending", "incomplete",
                                         "missing soma"),
                              required = c("superclass", "status", "initials"),
                              initials = getOption("aedes.initials")) {
  extra <- list(...)

  # Unmodified multi-value default => caller didn't supply status.
  status_shortlist <- eval(formals(aedes_add_neurons)$status)
  if (length(status) > 1L) status <- NULL
  if (!is.null(status)) {
    if (!is.character(status) || length(status) != 1L || is.na(status))
      stop("`status` must be a single non-NA string.", call. = FALSE)
    extra[["status"]] <- status
  }
  # `initials` from options if not already in `...`.
  if (is.null(extra[["initials"]]) && !is.null(initials)) {
    if (!is.character(initials) || length(initials) != 1L || is.na(initials))
      stop("`initials` must be a single non-NA string ",
           "(set via options(aedes.initials = ...) or the `initials` arg).",
           call. = FALSE)
    extra[["initials"]] <- initials
  }

  fids <- fafbseg::flywire_ids(ids, unique = TRUE)
  fids <- setdiff(fids, 0)
  # pin a single timestamp for both the supplied ids and the flytable rows
  ts <- aedes_get_version(timestamp = "now")
  ids <- with_aedes(fafbseg::flywire_latestid(fids, timestamp = ts$timestamp))

  am <- aedes_meta(expiry = 0)
  am <- aedes_sequential_update(am, version = ts$version, timestamp = ts$timestamp)

  # Validate status: fast accept if in the shortlist, else live-check against
  # the values already present in aedes_main. Case-sensitive on purpose.
  if (!is.null(extra[["status"]])) {
    st <- extra[["status"]]
    if (!st %in% status_shortlist) {
      vocab <- setdiff(unique(am$status), NA)
      if (!st %in% vocab)
        stop(sprintf(
          "status '%s' is not in the aedes_main vocabulary. Known values (%d): %s",
          st, length(vocab), paste(sort(vocab), collapse = ", ")),
          call. = FALSE)
    }
  }

  # Required-column check. `character(0)` disables entirely.
  if (length(required)) {
    miss <- setdiff(required, names(extra))
    if (length(miss))
      stop("Missing required column(s): ", paste(miss, collapse = ", "),
           ". Pass via `...`",
           if ("initials" %in% miss)
             " (or set options(aedes.initials = ...))",
           ".", call. = FALSE)
  }

  # Base input frame with caller-supplied columns.
  indf <- data.frame(root_id = ids, stringsAsFactors = FALSE)
  for (nm in names(extra)) indf[[nm]] <- extra[[nm]]

  # Split existing vs missing (order-preserving via match).
  iidx  <- match(ids, am$root_id)
  is_upd <- !is.na(iidx)
  iidf  <- am[iidx[is_upd], , drop = FALSE]

  # ---- Soma / side enrichment (computed for all ids up-front) ------------
  auto_soma_raw <- rep(NA_character_, length(ids))
  auto_nucleus  <- rep(NA_integer_,   length(ids))
  auto_side_vec <- rep(NA_character_, length(ids))
  if (soma || side) {
    sp_nm <- aedes_soma_position(ids, units = "nm",
                                 version = ts$version, timestamp = ts$timestamp)
    ok <- !is.na(sp_nm$position) & nzchar(sp_nm$position)
    if (soma) {
      if (any(ok)) {
        xyz_nm  <- nat::xyzmatrix(sp_nm$position[ok])
        auto_soma_raw[ok] <- nat::xyzmatrix2str(aedes_nm2raw(xyz_nm))
      }
      auto_nucleus <- as.integer(sp_nm$nucleus_id)
    }
    if (side && any(ok)) {
      xyz_nm <- nat::xyzmatrix(sp_nm$position[ok])
      auto_side_vec[ok] <- aedes_point_side(xyz_nm, units = "nm")
    }
  }

  # ---- Key points ---------------------------------------------------------
  # Needed for: every new row's point_xyz; update rows whose existing
  # point_xyz is empty; and (when side=TRUE) any row where the soma cascade
  # yielded no position so side must fall back to the L2 key point.
  is_str_empty <- function(x) is.na(x) | !nzchar(as.character(x))
  needs_kp <- rep(FALSE, length(ids))
  needs_kp[!is_upd] <- TRUE
  if (any(is_upd)) {
    upd_pt_empty <- is_str_empty(iidf$point_xyz)
    needs_kp[which(is_upd)[upd_pt_empty]] <- TRUE
  }
  if (side) needs_kp[is.na(auto_side_vec)] <- TRUE

  key_pts_raw <- rep(NA_character_, length(ids))
  key_pts_nm  <- matrix(NA_real_, nrow = length(ids), ncol = 3)
  if (any(needs_kp)) {
    pts_raw <- aedes_key_point(ids[needs_kp], raw = TRUE)
    key_pts_raw[needs_kp] <- nat::xyzmatrix2str(pts_raw)
    key_pts_nm[needs_kp, ] <- aedes_raw2nm(pts_raw)
  }

  # side fallback: rows still NA on side but with a computed key point.
  if (side) {
    fb <- is.na(auto_side_vec) & !is.na(key_pts_raw)
    if (any(fb)) {
      auto_side_vec[fb] <- aedes_point_side(
        key_pts_nm[fb, , drop = FALSE], units = "nm")
      fb_ids <- ids[fb]
      warning(length(fb_ids), " id(s) had no soma; side derived from ",
              "L2 key point: ",
              paste(utils::head(fb_ids, 3), collapse = ", "),
              if (length(fb_ids) > 3)
                sprintf(" (+%d more)", length(fb_ids) - 3),
              call. = FALSE)
    }
  }

  # ---- Attach auto values (caller's `...` wins) ---------------------------
  auto_cols <- character(0)
  if (soma && !"soma_xyz"   %in% names(extra)) {
    indf$soma_xyz   <- auto_soma_raw
    auto_cols <- c(auto_cols, "soma_xyz")
  }
  if (soma && !"nucleus_id" %in% names(extra)) {
    indf$nucleus_id <- auto_nucleus
    auto_cols <- c(auto_cols, "nucleus_id")
  }
  if (side && !"side" %in% names(extra)) {
    indf$side <- auto_side_vec
    auto_cols <- c(auto_cols, "side")
  }
  if (!"point_xyz" %in% names(extra)) {
    indf$point_xyz <- key_pts_raw
    auto_cols <- c(auto_cols, "point_xyz")
  }

  # ---- Assemble update / new frames ---------------------------------------
  rlist <- list()

  if (any(is_upd)) {
    updf <- cbind(iidf[, "_id", drop = FALSE],
                  indf[is_upd, , drop = FALSE])
    # Auto-fill: don't clobber non-empty existing values -- rewrite those
    # cells with the row's current value so the update is a no-op for them.
    for (col in auto_cols) {
      existing <- iidf[[col]]
      keep <- !is_str_empty(existing)
      if (any(keep)) updf[[col]][keep] <- existing[keep]
    }
    if (any(duplicated(updf[["_id"]])))
      stop("Duplicate rows to update!")
    if (!dryrun)
      fafbseg::flytable_update_rows(updf, table = "aedes_main",
                                    append_allowed = FALSE)
    else
      rlist[["up"]] <- updf
  }

  if (any(!is_upd)) {
    newdf <- indf[!is_upd, , drop = FALSE]
    if (any(is.na(newdf$point_xyz)))
      stop("Failed to compute point_xyz for ", sum(is.na(newdf$point_xyz)),
           " new id(s).", call. = FALSE)
    rlist[["new"]] <- newdf
    if (!dryrun)
      # drop root_id -- the server derives it (and supervoxel_id) from point_xyz
      fafbseg::flytable_append_rows(newdf[-1], table = "aedes_main")
  }
  rlist
}
