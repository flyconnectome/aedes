#' Add new neurons (and update existing ones) in the aedes_main flytable
#'
#' @description Upserts rows in the `aedes_main` FlyTable: absent `root_id`s
#'   are appended, present ones are updated with any extra columns supplied
#'   via `...` or as columns of a data.frame `ids`. This is the entry point
#'   when you have a set of neurons that
#'   may or may not already be tracked; for pure metadata edits on rows that
#'   are already present use [aedes_set_meta()], and for group assignment use
#'   [aedes_set_group()].
#'
#'   Newly appended rows get an auto-computed `point_xyz` (via
#'   [aedes_key_point()]), and their `root_id` and `supervoxel_id` are written
#'   directly rather than left for the server to backfill -- so a later add of
#'   the same neuron is recognised as an update rather than silently appended a
#'   second time (`serial_id` is assigned by FlyTable on insert). The input
#'   `ids` and a fresh read of `aedes_main` are pinned to the same segmentation
#'   timestamp so that join-by-`root_id` is reliable.
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
#'   Computing a new row's `supervoxel_id` needs a `point_xyz` (the auto key
#'   point, or one supplied by the caller). Any new id for which no key point
#'   could be computed and none was supplied is still added, but with a warning
#'   and a blank `supervoxel_id`/`point_xyz` (its `root_id` is written
#'   regardless).
#'
#'   With `group = TRUE` and `dryrun = FALSE` the freshly-added neurons are
#'   passed to [aedes_set_group()] after insertion, minting (or joining) a group
#'   for them in the same call.
#'
#'   `ids` may instead be a data.frame with a `root_id` column; its other
#'   columns are folded in as per-row metadata, exactly as if passed via `...`
#'   but with one value per id rather than a single recycled value. A column
#'   supplied in both the data.frame and `...` is an error. A data.frame column
#'   that names an auto-fill column (`soma_xyz`, `nucleus_id`, `side`,
#'   `point_xyz`) simply overrides the auto-fill for that column, the same way
#'   a `...` value would.
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
#' @param ids Root ids of neurons to add or update, or a data.frame carrying a
#'   `root_id` column plus any per-row metadata columns (see Details). Ids must
#'   be valid (non-`0`, non-`NA`) flywire ids; they are brought to the current
#'   root id before matching.
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
#' @param group If `TRUE`, group the newly-added neurons via [aedes_set_group()]
#'   immediately after insertion. Only acts when `dryrun = FALSE`; defaults to
#'   `FALSE`.
#' @return A list. With `dryrun = TRUE` it has elements `up` (rows that would
#'   be updated) and/or `new` (rows that would be appended). With
#'   `dryrun = FALSE` it has `new` (the appended rows, so the caller can see the
#'   chosen `point_xyz`/`supervoxel_id`) and, when `group = TRUE`, `group` (the
#'   [aedes_set_group()] preview).
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
#' # Add the two neurons and immediately group them together
#' aedes_add_neurons(
#'   c("648518347569414567", "648518347399768369"),
#'   dryrun = FALSE, superclass = "KC", status = "adequate", group = TRUE)
#'
#' # Skip soma/side auto-fill (e.g. neurons with no soma in the volume)
#' aedes_add_neurons("648518347569414567",
#'                   superclass = "KC", status = "missing soma",
#'                   soma = FALSE, side = FALSE)
#'
#' # Per-row metadata via a data.frame: one `class`/`cell_type` per id.
#' df <- data.frame(
#'   root_id   = c("648518347569414567", "648518347399768369"),
#'   class     = "KC",
#'   cell_type = c("KCa'b'", "KCg"),
#'   status    = "adequate",
#'   stringsAsFactors = FALSE)
#' aedes_add_neurons(df)
#' }
aedes_add_neurons <- function(ids, dryrun = TRUE, ...,
                              soma = TRUE, side = TRUE,
                              status = c("adequate", "to_review",
                                         "needs_extending", "incomplete",
                                         "missing soma"),
                              required = c("superclass", "status", "initials"),
                              initials = getOption("aedes.initials"),
                              annotator = TRUE, proofreader = FALSE,
                              wipe = FALSE, group = FALSE) {
  .aedes_reject_dry_run(...)
  extra <- list(...)
  if (!is.logical(group) || length(group) != 1L || is.na(group))
    stop("`group` must be a single TRUE/FALSE.", call. = FALSE)
  if (group && dryrun)
    warning("group=TRUE has no effect under dryrun=TRUE; ",
            "re-run with dryrun=FALSE to add and group the neurons.",
            call. = FALSE)

  # A data.frame `ids` carries `root_id` plus any per-row metadata columns.
  # Fold those extra columns into `extra` (the same slot `...` uses) so they
  # participate in the required-checks, status validation and auto-fill in
  # exactly the same way -- just one value per id rather than a recycled
  # scalar. A column supplied in both the data.frame and `...` is ambiguous.
  if (is.data.frame(ids)) {
    if (!"root_id" %in% names(ids))
      stop("A data.frame `ids` must contain a `root_id` column.", call. = FALSE)
    dfcols <- setdiff(names(ids), "root_id")
    clash <- intersect(dfcols, names(extra))
    if (length(clash))
      stop("Column(s) supplied via both the data.frame and `...`: ",
           paste(clash, collapse = ", "), ".", call. = FALSE)
    for (nm in dfcols) extra[[nm]] <- ids[[nm]]
    ids <- ids$root_id
  }

  ids <- as.character(ids)
  bad <- is.na(ids) | !grepl("^[1-9][0-9]*$", ids)
  if (any(bad))
    stop(sum(bad), " invalid id(s) (0, NA or malformed): ",
         paste(utils::head(ids[bad], 5L), collapse = ", "),
         if (sum(bad) > 5L) sprintf(" (+%d more)", sum(bad) - 5L), ".",
         call. = FALSE)
  ann_toks <- .aedes_resolve_initials(annotator,  "annotator")
  prf_toks <- .aedes_resolve_initials(proofreader, "proofreader")

  # Unmodified multi-value default => caller didn't supply status.
  status_shortlist <- eval(formals(aedes_add_neurons)$status)
  if (length(status) > 1L) status <- NULL
  if (!is.null(status)) {
    if ("status" %in% names(extra))
      stop("`status` supplied both as an argument and as a data.frame column.",
           call. = FALSE)
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
  # Columns the caller supplied (via `...` or the data.frame) suppress the
  # matching auto-fill and win outright, so skip the service calls that would
  # only feed a suppressed column.
  has_soma_xyz  <- "soma_xyz"   %in% names(extra)
  has_nucleus   <- "nucleus_id" %in% names(extra)
  has_side      <- "side"       %in% names(extra)
  has_point_xyz <- "point_xyz"  %in% names(extra)
  do_soma <- soma && !(has_soma_xyz && has_nucleus)
  do_side <- side && !has_side

  auto_soma_raw <- rep(NA_character_, length(ids))
  auto_nucleus  <- rep(NA_integer_,   length(ids))
  auto_side_vec <- rep(NA_character_, length(ids))
  if (do_soma || do_side) {
    sp_nm <- aedes_soma_position(ids, units = "nm",
                                 version = ts$version, timestamp = ts$timestamp)
    ok <- !is.na(sp_nm$position) & nzchar(sp_nm$position)
    if (do_soma) {
      if (any(ok)) {
        xyz_nm  <- nat::xyzmatrix(sp_nm$position[ok])
        auto_soma_raw[ok] <- nat::xyzmatrix2str(aedes_nm2raw(xyz_nm))
      }
      auto_nucleus <- as.integer(sp_nm$nucleus_id)
    }
    if (do_side && any(ok)) {
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
  if (!has_point_xyz) {
    needs_kp[!is_upd] <- TRUE
    if (any(is_upd)) {
      upd_pt_empty <- is_str_empty(iidf$point_xyz)
      needs_kp[which(is_upd)[upd_pt_empty]] <- TRUE
    }
  }
  if (do_side) needs_kp[is.na(auto_side_vec)] <- TRUE

  key_pts_raw <- rep(NA_character_, length(ids))
  key_pts_nm  <- matrix(NA_real_, nrow = length(ids), ncol = 3)
  if (any(needs_kp)) {
    pts_raw <- aedes_key_point(ids[needs_kp], raw = TRUE)
    key_pts_raw[needs_kp] <- nat::xyzmatrix2str(pts_raw)
    key_pts_nm[needs_kp, ] <- aedes_raw2nm(pts_raw)
  }

  # side fallback: rows still NA on side but with a computed key point.
  if (do_side) {
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
  if (soma && !has_soma_xyz) {
    indf$soma_xyz   <- auto_soma_raw
    auto_cols <- c(auto_cols, "soma_xyz")
  }
  if (soma && !has_nucleus) {
    indf$nucleus_id <- auto_nucleus
    auto_cols <- c(auto_cols, "nucleus_id")
  }
  if (side && !has_side) {
    indf$side <- auto_side_vec
    auto_cols <- c(auto_cols, "side")
  }
  if (!has_point_xyz) {
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

    # Write root_id and supervoxel_id ourselves rather than leaving both blank
    # for the server to backfill from point_xyz. Writing root_id up front means
    # a later add of the same neuron is recognised as an update rather than
    # silently appended a second time. Both derive from a point_xyz (the auto
    # key point, or one supplied by the caller); warn about -- but still add --
    # any row that has none, leaving its supervoxel_id/point_xyz blank.
    have_pt <- !is_str_empty(newdf$point_xyz)
    if (any(!have_pt)) {
      miss_ids <- newdf$root_id[!have_pt]
      warning(sum(!have_pt), " new id(s) have no point_xyz (no key point could ",
              "be computed and none was supplied); adding them with blank ",
              "supervoxel_id/point_xyz: ",
              paste(utils::head(miss_ids, 3), collapse = ", "),
              if (length(miss_ids) > 3)
                sprintf(" (+%d more)", length(miss_ids) - 3),
              call. = FALSE)
    }
    newdf$supervoxel_id <- NA_character_
    if (any(have_pt))
      newdf$supervoxel_id[have_pt] <- as.character(aedes_xyz2id(
        newdf$point_xyz[have_pt], rawcoords = TRUE, root = FALSE,
        version = ts$version, timestamp = ts$timestamp))

    # New-row merge: no existing cells, so the merged list is just the tokens.
    newdf <- .aedes_append_multiselect(
      newdf, am, list(annotator = ann_toks, proofreader = prf_toks))
    rlist[["new"]] <- newdf
    if (!dryrun) {
      fafbseg::flytable_append_rows(newdf, table = "aedes_main")
      # Group the freshly-added neurons if requested. serial_id is assigned by
      # FlyTable on insert, so a fresh read (aedes_set_group pins its own) sees
      # the new rows and can mint / join a group by root_id.
      if (isTRUE(group)) {
        gp <- aedes_set_group(newdf$root_id, dryrun = FALSE,
                              annotator = annotator, proofreader = proofreader,
                              wipe = wipe)
        rlist[["group"]] <- gp
      }
    }
  } else if (isTRUE(group) && !dryrun) {
    warning("group=TRUE but no new rows were added; nothing to group.",
            call. = FALSE)
  }
  rlist
}
