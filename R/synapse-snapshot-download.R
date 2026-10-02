#' Download or publish Aedes synapse snapshots
#'
#' @description `aedes_download_snapshot()` downloads the newest published
#'   synapse snapshots into your snapshot folder; select one with
#'   [aedes_use_snapshot()] to use it. The first download fetches the static data (about
#'   1.7 GB) and a full snapshot (about 0.6 GB); later ones usually just fetch
#'   a few small checkpoints.
#'
#'   `aedes_publish_snapshot()` is for whoever maintains the snapshots: it
#'   makes the newest snapshot in `root`, and the earlier checkpoints it is
#'   built on, available for download from a folder served over https.
#'
#' @details Snapshots are published with a `manifest.json` that lists every
#'   file with its size and md5. A download only fetches snapshots that are
#'   not already in `root` (snapshots never change once made), checks each
#'   file's md5 and places a snapshot's `meta.json` last, so an interrupted
#'   download is never mistaken for a snapshot; just run it again. Downloads
#'   use the `curl` command line tool and resume partial files.
#'
#'   Publishing hard links the files into `dest` when it is on the same
#'   filesystem as `root` (otherwise they are copied), so it takes no extra
#'   space. It includes the static data, the full snapshot that `snapshot` is
#'   built on and every complete checkpoint built on that full snapshot (see
#'   [aedes_update_snapshot()]). `manifest.json` is written last. Files that are
#'   no longer listed are removed one publish later, so that a client that has
#'   just read the previous manifest can still finish.
#'
#' @param url The address of the published snapshots (the folder or its
#'   `manifest.json`). The default (`NULL`) uses the `aedes.snapshot_url`
#'   option if set, and otherwise the standard address, which needs access to
#'   the aedes CAVE datastack to work out.
#' @param root The local snapshot folder. Defaults to [aedes_snapshot_root()].
#' @return `aedes_download_snapshot()`: the tags downloaded, invisibly.
#'   `aedes_publish_snapshot()`: the manifest, invisibly.
#' @seealso [aedes_use_snapshot()], [aedes_update_snapshot()],
#'   [aedes_build_snapshot()]
#' @export
#' @examples
#' \dontrun{
#' aedes_download_snapshot()
#' }
aedes_download_snapshot <- function(url = NULL,
                                    root = aedes_snapshot_root(create = TRUE)) {
  if (is.null(url)) url <- aedes_snapshot_url()
  tags <- synsnap_download(url, root)
  message(if (length(tags)) paste("Downloaded synapse snapshot(s)",
                                  paste(tags, collapse = ", "))
          else "Synapse snapshots are already up to date")
  message("Use aedes_use_snapshot() to query them")
  invisible(tags)
}

#' @rdname aedes_download_snapshot
#' @param dest The folder to publish into.
#' @param snapshot The snapshot to publish; `"latest"` (the default) for the
#'   newest one in `root`.
#' @export
aedes_publish_snapshot <- function(dest, root = aedes_snapshot_root(),
                                   snapshot = "latest") {
  if (identical(snapshot, "latest")) snapshot <- synsnap_latest(root)
  synsnap_publish(root, dest, snapshot)
}

# Fetch newly published checkpoints into `root` if the last check was more
# than `hours` ago. A new full snapshot is only announced, since it is large.
# The time of the last check is kept in `root`, so new sessions don't check
# again straight away. Quiet unless something is downloaded or checks have
# been failing for over a day. Returns the tags downloaded.
aedes_snapshot_refresh <- function(root,
                                   hours = getOption("aedes.snapshot_check_hours", 6)) {
  if (!is.finite(hours) || !dir.exists(root) || !nrow(synsnap_tags(root)))
    return(invisible(character()))
  f <- file.path(root, ".last_check.json")
  st <- if (file.exists(f)) tryCatch(jsonlite::read_json(f), error = function(e) NULL)
  now <- Sys.time()
  if (!is.null(st$time) &&
      as.numeric(now) - as.numeric(synsnap_parse_time(st$time)) < hours * 3600)
    return(invisible(character()))
  res <- tryCatch(synsnap_download(aedes_snapshot_url(), root, full = FALSE),
                  error = function(e) e)
  failed <- inherits(res, "error")
  since <- if (failed) st$failing_since %||% synsnap_format_time(now)
  jsonlite::write_json(c(list(time = synsnap_format_time(now)),
                         if (!is.null(since)) list(failing_since = since)),
                       f, auto_unbox = TRUE)
  if (failed) {
    if (as.numeric(now) - as.numeric(synsnap_parse_time(since)) > 86400)
      message("Could not check for new synapse snapshots since ", since, ": ",
              conditionMessage(res))
    return(invisible(character()))
  }
  if (length(attr(res, "skipped")))
    message("A new full synapse snapshot is available (about 0.6 GB); ",
            "fetch it with aedes_download_snapshot()")
  invisible(as.character(res))
}

# Address of the published snapshots: the aedes.snapshot_url option, or the
# standard one. Its folder name is a hash of the L2 ids of a fixed root id, so
# working it out needs access to the aedes chunkedgraph (done once a session).
aedes_snapshot_url <- function() {
  url <- getOption("aedes.snapshot_url")
  if (!is.null(url) && nzchar(url)) return(url)
  aedes_snapshot_url_cave()
}

aedes_snapshot_url_cave <- memoise::memoise(function() {
  l2 <- tryCatch(
    with_aedes(fafbseg::flywire_l2ids("648518347624785674", integer64 = TRUE)),
    error = function(e) stop("Could not work out the snapshot address, which ",
                             "needs access to the aedes CAVE datastack: ",
                             conditionMessage(e), call. = FALSE))
  paste0("https://flyemdev.mrc-lmb.cam.ac.uk/flyconnectome/aedes/",
         synsnap_l2_hash(l2), "/snapshot")
})

# sha256 of the unique ids in numeric order as decimal strings, one per line
# with no final newline
synsnap_l2_hash <- function(l2) {
  l2 <- sort(unique(bit64::as.integer64(l2)))
  digest::digest(paste(as.character(l2), collapse = "\n"), algo = "sha256",
                 serialize = FALSE)
}
