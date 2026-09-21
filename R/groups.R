#' Group aedes neurons together in FlyTable
#'
#' @description Writes only the `group` column of the `aedes_main` FlyTable,
#'   assigning a shared `group` id to a set of neurons -- the convenient way
#'   to build serial / cell-type groups and, via `join_existing`, to add
#'   neurons to a group that already exists. For editing arbitrary metadata
#'   columns use [aedes_set_meta()]; to add rows that are not yet present
#'   use [aedes_add_neurons()].
#'
#' @details By convention a group is identified by an integer equal to the
#'   smallest `serial_id` among its founding members; `NA` (an empty FlyTable
#'   cell) means ungrouped. When the selected neurons are all currently
#'   ungrouped a fresh group id is minted from `min(serial_id)`.
#'
#'   An explicit `group` must be a positive whole number small enough to be a
#'   serial_id (5 digits at present), matching what [aedes_add_neurons()]
#'   accepts. A root_id (~6e17) is therefore rejected rather than written out
#'   as a group id; to join the group of particular neurons, name them with a
#'   query instead.
#'
#'   When some selected neurons already belong to a group, `join_existing`
#'   decides what happens (see the argument). Reassigning neurons out of a group
#'   whose other members were not supplied emits a warning, since it splits that
#'   group. Only the `group` column is written, via the shared update engine that
#'   also backs [aedes_set_meta()]; the same pinned table snapshot is reused so
#'   the returned preview matches what is written.
#'
#' @param ids Neurons to group, in any form understood by [aedes_ids()]
#'   (including a query string).
#' @param group Optional explicit target. A positive whole number forces that
#'   group id; `NA` ungroups; a query string joins the group of the neurons it
#'   matches ("join-by-example"). When `NULL` (the default) the group id is
#'   derived (see Details). Zero, negative and root_id-sized ids are an error:
#'   use `NA` to ungroup.
#' @param join_existing Controls behaviour when selected neurons already belong
#'   to a group. `NA` (the default): refuse to guess -- warn (dry run) or error
#'   (live) and explain how to proceed. `TRUE`: add them to the existing group
#'   (its id is kept even if a lower `serial_id` is now available; several
#'   existing groups are merged into the smallest, with a warning). `FALSE`:
#'   ignore existing membership and mint a fresh group from `min(serial_id)`.
#' @param dryrun logical: if `TRUE` (the default) return a preview without
#'   writing to FlyTable.
#' @param annotator Multi-select `annotator` column write policy for rows that
#'   actually change group. `TRUE` (the default) appends
#'   `getOption("aedes.initials")` to the existing cell; `FALSE` leaves the
#'   column alone; a character vector (or comma-joined string) appends those
#'   tokens explicitly.
#' @param proofreader Multi-select `proofreader` column write policy. Same
#'   accepted values as `annotator`; defaults to `FALSE`.
#' @param wipe If `TRUE`, replace the target multi-select column(s) with just
#'   the new tokens instead of merging with existing cell contents. Default
#'   `FALSE` (append).
#' @param ... reserved (used to reject a mistaken `dry_run` argument).
#'
#' @returns A preview data.frame with one row per selected neuron: `root_id`,
#'   `serial_id`, `group_old`, `group_new` and `changed`. `group_old` and
#'   `group_new` are `NA` for ungrouped neurons. Returned invisibly on a live
#'   write.
#' @seealso [aedes_set_meta()] for arbitrary metadata updates;
#'   [aedes_add_neurons()] to add rows that are not yet present;
#'   [aedes_meta()] to query the same table.
#' @export
#' @examples
#' \dontrun{
#' options(aedes.initials = "GJ")
#'
#' # Mint a fresh group from a set of ungrouped neurons: the resulting
#' # `group` id is min(serial_id) of the members.
#' ids <- c("648518347569414567", "648518347399768369")
#' aedes_set_group(ids)                       # dry run: preview only
#' aedes_set_group(ids, dryrun = FALSE)       # commit
#'
#' # Add another neuron to an existing group. When some selected neurons
#' # are already grouped, join_existing is required (NA = refuse to guess).
#' aedes_set_group(c(ids, "648518347123456789"),
#'                 join_existing = TRUE, dryrun = FALSE)
#'
#' # Join by example: adopt the group of the neurons a query matches.
#' aedes_set_group("648518347999999999",
#'                 group = "type:G59_SN", dryrun = FALSE)
#'
#' # Ungroup (clears the FlyTable cell)
#' aedes_set_group(ids, group = NA, dryrun = FALSE)
#' }
aedes_set_group <- function(ids, group = NULL, join_existing = NA,
                            dryrun = TRUE,
                            annotator = TRUE, proofreader = FALSE,
                            wipe = FALSE, ...) {
  .aedes_reject_dry_run(...)
  ann_toks <- .aedes_resolve_initials(annotator,  "annotator")
  prf_toks <- .aedes_resolve_initials(proofreader, "proofreader")
  # Go via as.numeric(), not as.character(): FlyTable reports empty numeric
  # cells as NaN and as.integer("NaN") is 0 (not NA), which would make every
  # ungrouped neuron look like a member of a group "0".
  as_int <- function(x) suppressWarnings(as.integer(as.numeric(x)))

  pin <- .aedes_pin_meta(aedes_ids(ids))
  am <- pin$am
  ts <- pin$ts
  rids <- unique(pin$ids)
  if (!length(rids)) stop("No valid ids.", call. = FALSE)

  idx <- match(rids, as.character(am$root_id))
  if (anyNA(idx))
    stop("These ids are not present in aedes_main: ",
         paste(rids[is.na(idx)], collapse = ", "), call. = FALSE)

  am_group   <- as_int(am$group)
  cur_group  <- am_group[idx]
  cur_serial <- as_int(am$serial_id[idx])
  in_group <- !is.na(cur_group)
  existing_groups <- sort(unique(cur_group[in_group]))

  minserial <- suppressWarnings(min(cur_serial, na.rm = TRUE))
  if (!is.finite(minserial))
    stop("No valid serial_id among the selected neurons.", call. = FALSE)

  # ---- Determine the target group id --------------------------------------
  if (!is.null(group)) {
    if (length(group) != 1L)
      stop("`group` must be a single value.", call. = FALSE)
    # Anything that looks like a number is a group id; anything else is a query
    # naming the neurons whose group to join.
    numlike <- is.numeric(group) || grepl("^[0-9]+$", as.character(group))
    if (is.na(group)) {
      target <- NA_integer_
    } else if (numlike) {
      # Group ids are serial_id-style (5 digits at present) so they always fit
      # in an integer, whereas a root_id (~6e17) never does. Rejecting the
      # overflow keeps `group` meaning the same thing here as it does in
      # aedes_add_neurons(), rather than silently minting a bogus group.
      gint <- suppressWarnings(as.integer(group))
      if (is.na(gint))
        stop("`group` is too large to be a group id (group ids are ",
             "serial_id-style). To join the group of a particular neuron, ",
             "pass a query such as `group = \"type:G59_SN\"`, or look its ",
             "group up with aedes_meta().", call. = FALSE)
      # 0 in particular is not a group id: FlyTable records ungrouped neurons
      # as an empty cell, so unsetting must write NA rather than a literal 0,
      # which would otherwise read back as a group shared by every one of them.
      if (gint <= 0L || gint != as.numeric(group))
        stop("`group` must be a positive whole number (got ", group,
             "). Use `group = NA` to ungroup.", call. = FALSE)
      target <- gint
    } else {
      # join-by-example: adopt the group of the neuron(s) the query matches
      exg <- am_group[match(as.character(aedes_ids(group)),
                            as.character(am$root_id))]
      exg <- exg[!is.na(exg)]
      if (!length(exg))
        stop("The `group` reference neuron(s) have no group to join.",
             call. = FALSE)
      target <- min(exg)
    }
  } else if (length(existing_groups)) {
    # some selected neurons already grouped -> honour join_existing
    if (isTRUE(join_existing)) {
      target <- min(existing_groups)
      if (length(existing_groups) > 1L)
        warning("Merging groups ", paste(existing_groups, collapse = ", "),
                " into ", target, ".", call. = FALSE)
    } else if (isFALSE(join_existing)) {
      target <- minserial
      message(sum(in_group), " neuron(s) already in group(s) ",
              paste(existing_groups, collapse = ", "),
              " reassigned to new group ", target,
              " (existing membership ignored).")
    } else {
      # join_existing = NA -> refuse to guess silently
      msg <- paste0(
        sum(in_group), " selected neuron(s) already belong to group(s) ",
        paste(existing_groups, collapse = ", "), ".\n",
        "  re-run with join_existing=TRUE  to add them to group ",
        min(existing_groups), "\n",
        "  re-run with join_existing=FALSE to start a fresh group ", minserial)
      if (dryrun) {
        warning(msg, call. = FALSE)
        target <- min(existing_groups)  # preview the join
      } else {
        stop(msg, call. = FALSE)
      }
    }
  } else {
    target <- minserial
  }
  target <- as.integer(target)

  # ---- Orphan guard: warn if a reassignment splits an existing group ------
  for (g in setdiff(existing_groups, target)) {
    members <- as.character(am$root_id[which(am_group == g)])
    orphans <- setdiff(members, rids)
    if (length(orphans))
      warning("Reassigning neurons out of group ", g, " leaves ",
              length(orphans), " other member(s) behind (splitting it).",
              call. = FALSE)
  }

  # ---- Build preview + (optionally) write ---------------------------------
  new_group <- rep(target, length(rids))
  # NA-safe comparison: `target` is NA when ungrouping, and NA != x is NA.
  changed <- if (is.na(target)) in_group
             else !in_group | cur_group != target
  preview <- data.frame(
    root_id   = rids,
    serial_id = cur_serial,
    group_old = cur_group,
    group_new = new_group,
    changed   = changed,
    stringsAsFactors = FALSE)

  if (any(changed) && !dryrun) {
    updf <- data.frame(root_id = rids[changed], group = new_group[changed],
                       stringsAsFactors = FALSE)
    updf <- .aedes_append_multiselect(
      updf, am, list(annotator = ann_toks, proofreader = prf_toks), wipe = wipe)
    .aedes_update_existing(updf, dryrun = FALSE, am = am, ts = ts)
    return(invisible(preview))
  }
  preview
}
