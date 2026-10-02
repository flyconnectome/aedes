# Unattended checkpoints for the server that publishes snapshots (run from
# cron, see inst/scripts/synsnap-cron.sh). Dataset-agnostic like R/synsnap.R.

# Checkpoints that should exist at `now`: one at the exact time of each
# materialisation version (tag v<N>) in `versions` (a data.frame with
# version, timestamp), and one every `every` seconds, `at` seconds after
# midnight UTC (tag rYYYYmmddTHHMMSS), unless there is a version checkpoint in
# the `every` seconds before it. So with a new version each day, the regular
# ones only fill in days without one; the default of 20:00 UTC leaves a few
# hours for a late version (aedes versions are at about 14:12 UTC). Each is
# made once it is at least `settle` seconds old, so that its edits are all
# visible. Both go back `catchup` seconds (but not before the oldest
# snapshot), so a failed or missed run is filled in by the next one.
# Returns a data.frame of tag, timestamp (text), kind, version for those that
# are missing, oldest first.
synsnap_server_todo <- function(root, now, versions = NULL, every = 86400,
                                at = 20 * 3600, settle = 3600,
                                catchup = 7 * 86400) {
  now <- as.numeric(now)
  last <- floor((now - settle - at) / every) * every + at
  slots <- .POSIXct(seq(last - floor(catchup / every) * every, last, by = every),
                    tz = "UTC")
  todo <- data.frame(tag = format(slots, "r%Y%m%dT%H%M%S", tz = "UTC"),
                     timestamp = synsnap_format_time(slots), kind = "regular",
                     version = NA_integer_)
  if (NROW(versions)) {
    vt <- as.numeric(versions$timestamp)
    keep <- vt >= now - catchup & vt <= now - settle
    if (any(keep))
      todo <- rbind(todo, data.frame(
        tag = paste0("v", versions$version[keep]),
        timestamp = synsnap_format_time(versions$timestamp[keep]),
        kind = "version", version = as.integer(versions$version[keep])))
  }
  have <- synsnap_tags(root, all = TRUE)
  if (!nrow(have)) stop("No synapse snapshots in ", root, call. = FALSE)
  vt <- c(as.numeric(synsnap_parse_time(todo$timestamp[todo$kind == "version"])),
          as.numeric(have$timestamp[have$kind %in% "version"]))
  st <- as.numeric(synsnap_parse_time(todo$timestamp))
  covered <- todo$kind == "regular" &
    vapply(st, function(t) any(vt > t - every & vt <= t), logical(1))
  todo <- todo[!covered, , drop = FALSE]
  todo <- todo[!todo$tag %in% have$tag & synsnap_parse_time(todo$timestamp) >=
                 min(have$timestamp), , drop = FALSE]
  todo <- todo[order(synsnap_parse_time(todo$timestamp)), , drop = FALSE]
  rownames(todo) <- NULL
  todo
}

# Make the missing checkpoints (see synsnap_server_todo()), each from the
# newest usable snapshot at or before its time, then publish to `dest` (if
# given) and write status.json there (or in `root`). A failed checkpoint
# does not stop the others. Errors at the end if any failed or if the newest
# usable snapshot is more than `max_age` seconds old, so cron reports it.
synsnap_server_update <- function(root, ctx, dest = NULL, versions = NULL,
                                  every = 86400, at = 20 * 3600,
                                  settle = 3600, catchup = 7 * 86400,
                                  overlap = 600, max_age = 36 * 3600) {
  now <- ctx$now()
  todo <- synsnap_server_todo(root, now, versions, every = every, at = at,
                              settle = settle, catchup = catchup)
  built <- character()
  errors <- character()
  for (i in seq_len(nrow(todo))) {
    T <- todo$timestamp[i]
    res <- tryCatch({
      from <- synsnap_at(root, synsnap_parse_time(T), tol = 0)
      if (is.null(from)) stop("no snapshot is as old as ", T, call. = FALSE)
      synsnap_update(from, todo$tag[i], T, root, ctx, kind = todo$kind[i],
                     version = if (!is.na(todo$version[i])) todo$version[i],
                     overlap = overlap)
      NULL
    }, error = function(e) conditionMessage(e))
    if (is.null(res)) built <- c(built, todo$tag[i])
    else errors <- c(errors, paste0(todo$tag[i], ": ", res))
  }
  if (!is.null(dest)) {
    res <- tryCatch({synsnap_publish(root, dest); NULL},
                    error = function(e) conditionMessage(e))
    if (!is.null(res)) errors <- c(errors, paste0("publish: ", res))
  }
  tags <- synsnap_tags(root)
  latest <- if (nrow(tags)) tags[nrow(tags), ]
  age <- if (!is.null(latest)) as.numeric(now) - as.numeric(latest$timestamp)
  if (is.null(age) || age > max_age)
    errors <- c(errors, sprintf("newest snapshot is %s",
                                if (is.null(age)) "missing"
                                else sprintf("%.1f hours old", age / 3600)))
  status <- list(
    time = synsnap_format_time(now), ok = !length(errors), built = built,
    errors = errors, latest = if (!is.null(latest)) latest$tag,
    latest_timestamp = if (!is.null(latest)) synsnap_format_time(latest$timestamp))
  sf <- file.path(if (is.null(dest)) synsnap_path(root) else dest, "status.json")
  jsonlite::write_json(status, paste0(sf, ".tmp"), auto_unbox = TRUE, pretty = TRUE)
  file.rename(paste0(sf, ".tmp"), sf)
  if (length(errors))
    stop("Synapse snapshot update failed:\n", paste(errors, collapse = "\n"),
         call. = FALSE)
  invisible(status)
}
