#' Add new neurons (and update existing ones) in the aedes_main flytable
#'
#' @description Upserts rows in the `aedes_main` FlyTable: absent `root_id`s
#'   are appended, present ones are updated with any extra columns supplied
#'   via `...`. This is the entry point when you have a set of neurons that
#'   may or may not already be tracked; for pure metadata edits on rows that
#'   are already present use [aedes_set_meta()], and for group assignment use
#'   [aedes_set_group()].
#'
#'   Newly appended rows get an auto-computed `point_xyz` (via
#'   [aedes_key_point()]); `supervoxel_id` and `serial_id` are left blank and
#'   filled in server-side from `point_xyz`. The input `ids` and a fresh read
#'   of `aedes_main` are pinned to the same segmentation timestamp so that
#'   join-by-`root_id` is reliable.
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
#'   `ids` are efficiently mapped to the latest segmentation state (with
#'   [fafbseg::flywire_latestid()]) before use, so distinct inputs (e.g.
#'   historical versions of one proofread neuron) can collapse onto the same
#'   root id. Such duplicates are dropped with a warning when every annotation
#'   column supplied via `...` is a single value recycled across all rows.
#'   However, if any `...` column carries multiple values (a vector longer than
#'   one) the collision is an error, since it may not be clear which value to
#'   keep -- supply duplicate-free `ids`, or one value per column. Note that
#'   invalid ids (`0`, `NA` or malformed) are rejected up front.
#'
#' @param ids Root ids of neurons to add or update. Must be valid (non-`0`,
#'   non-`NA`) flywire ids; they are brought to the current root id before
#'   matching.
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
#' @param initials Curator initials for the single-string `initials` column.
#'   Defaults to `getOption("aedes.initials")`; set once per session with
#'   `options(aedes.initials = "XY")`. Passed through `...` semantics -- an
#'   explicit `initials = ...` in `...` wins over the option.
#' @param annotator Multi-select `annotator` column write policy. `TRUE`
#'   (the default) appends `getOption("aedes.initials")` to the cell; `FALSE`
#'   leaves the column alone; a character vector (or comma-joined string)
#'   appends those tokens explicitly. On existing rows the tokens are merged
#'   with the current cell contents (unique, sorted).
#' @param proofreader Multi-select `proofreader` column write policy. Same
#'   accepted values as `annotator`; defaults to `FALSE` (leave the column
#'   alone).
#' @param wipe If `TRUE`, replace the target multi-select column(s) with just
#'   the new tokens instead of merging with existing cell contents. Default
#'   `FALSE` (append).
#' @return A list. With `dryrun = TRUE` it has elements `up` (rows that would
#'   be updated) and/or `new` (rows that would be appended). With
#'   `dryrun = FALSE` only `new` is returned (so the caller can see which
#'   `point_xyz` values were chosen).
#' @seealso [aedes_set_meta()] for pure metadata updates on rows already
#'   present in `aedes_main`; [aedes_set_group()] for group assignment;
#'   [aedes_key_point()], [aedes_soma_position()], [aedes_point_side()] for
#'   the auto-fill helpers.
#' @export
#' @examples
#' \dontrun{
#' # Set your curator initials once per session (used for the annotator column
#' # and the required `initials` column on new rows)
#' options(aedes.initials = "GJ")
#'
#' # Dry run first: see the frames that would be written. Two new neurons,
#' # both to be added as KC superclass. status is required; the shortlist
#' # in the signature gives tab-completion.
#' aedes_add_neurons(
#'   c("648518347569414567", "648518347399768369"),
#'   superclass = "KC", status = "adequate")
#'
#' # Commit for real
#' aedes_add_neurons(
#'   c("648518347569414567", "648518347399768369"),
#'   dryrun = FALSE, superclass = "KC", status = "adequate")
#'
#' # Skip soma/side auto-fill (e.g. neurons with no soma in the volume)
#' aedes_add_neurons("648518347569414567",
#'                   superclass = "KC", status = "missing soma",
#'                   soma = FALSE, side = FALSE)
#' }
aedes_add_neurons <- function(ids, dryrun = TRUE, ...,
                              soma = TRUE, side = TRUE,
                              status = c("adequate", "to_review",
                                         "needs_extending", "incomplete",
                                         "missing soma"),
                              required = c("superclass", "status", "initials"),
                              initials = getOption("aedes.initials"),
                              annotator = TRUE, proofreader = FALSE,
                              wipe = FALSE) {
  .aedes_reject_dry_run(...)
  ids <- as.character(ids)
  bad <- is.na(ids) | !grepl("^[1-9][0-9]*$", ids)
  if (any(bad))
    stop(sum(bad), " invalid id(s) (0, NA or malformed): ",
         paste(utils::head(ids[bad], 5L), collapse = ", "),
         if (sum(bad) > 5L) sprintf(" (+%d more)", sum(bad) - 5L), ".",
         call. = FALSE)
  extra <- list(...)
  ann_toks <- .aedes_resolve_initials(annotator,  "annotator")
  prf_toks <- .aedes_resolve_initials(proofreader, "proofreader")

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

  # pin a single timestamp for both the supplied ids and the flytable rows,
  # reading aedes_main fresh and bringing it to the same timestamp
  pin <- .aedes_pin_meta(ids)
  ids <- pin$ids
  am  <- pin$am
  ts  <- pin$ts

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
           ". Pass via `...`, e.g. `superclass = \"KC\"`",
           if ("initials" %in% miss)
             " -- for `initials` you can also set once with ",
             "options(aedes.initials = \"XY\")",
           ".", call. = FALSE)
  }

  # Base input frame with caller-supplied columns.
  indf <- data.frame(root_id = ids, stringsAsFactors = FALSE)
  for (nm in names(extra)) indf[[nm]] <- extra[[nm]]

  # Distinct input ids can resolve to one neuron after pinning to a common
  # timestamp. Dropping duplicates is only safe when every supplied column is a
  # single value recycled across all rows; if any column carries per-id values
  # we cannot know which to keep, so refuse. `ids` stays 1:1 with `indf` here
  # (pin resolves order- and length-preserving), so `keep` subsets both.
  if (anyDuplicated(ids)) {
    vec_cols <- names(extra)[lengths(extra) > 1L]
    if (length(vec_cols))
      stop("Distinct input ids resolved to the same neuron while per-id ",
           "values were supplied for column(s): ",
           paste(vec_cols, collapse = ", "),
           ". Supply duplicate-free ids, or one value per column.", call. = FALSE)
    keep <- !duplicated(ids)
    warning(sum(!keep), " duplicate id(s) dropped (distinct inputs resolving ",
            "to one neuron); ", sum(keep), " unique neuron(s) remain.",
            call. = FALSE)
    ids  <- ids[keep]
    indf <- indf[keep, , drop = FALSE]
  }

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
    upd_in <- indf[is_upd, , drop = FALSE]
    # Auto-fill: don't clobber non-empty existing values -- rewrite those cells
    # with the row's current value so the engine writes a no-op for them. This
    # no-overwrite policy is add_neurons-specific; the engine writes verbatim.
    for (col in auto_cols) {
      existing <- iidf[[col]]
      keep <- !is_str_empty(existing)
      if (any(keep)) upd_in[[col]][keep] <- existing[keep]
    }
    upd_in <- .aedes_append_multiselect(
      upd_in, am, list(annotator = ann_toks, proofreader = prf_toks),
      wipe = wipe)
    res <- .aedes_update_existing(upd_in, dryrun = dryrun, am = am, ts = ts)
    if (dryrun) rlist[["up"]] <- res$updf
  }

  if (any(!is_upd)) {
    newdf <- indf[!is_upd, , drop = FALSE]
    if (any(is.na(newdf$point_xyz)))
      stop("Failed to compute point_xyz for ", sum(is.na(newdf$point_xyz)),
           " new id(s).", call. = FALSE)
    # New-row merge: no existing cells, so the merged list is just the tokens.
    newdf <- .aedes_append_multiselect(
      newdf, am, list(annotator = ann_toks, proofreader = prf_toks))
    rlist[["new"]] <- newdf
    if (!dryrun)
      # drop root_id -- the server derives it (and supervoxel_id) from point_xyz
      fafbseg::flytable_append_rows(newdf[-1], table = "aedes_main")
  }
  rlist
}
