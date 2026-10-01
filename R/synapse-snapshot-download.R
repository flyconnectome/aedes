#' Download or publish Aedes synapse snapshots
#'
#' @description `aedes_download_snapshot()` downloads the newest published
#'   synapse snapshot into your snapshot folder and selects it with
#'   [aedes_use_snapshot()]. The first download fetches the static data (about
#'   1.7 GB) and a full snapshot (about 0.6 GB); later ones usually just fetch a
#'   small delta.
#'
#'   `aedes_publish_snapshot()` is for whoever maintains the snapshots: it
#'   makes the newest snapshot in `root` available for download from a folder
#'   served over https.
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
#'   space. It includes the static data, the newest snapshot and, when that is
#'   a delta, its full base. `manifest.json` is written last. Files that are
#'   no longer listed are removed one publish later, so that a client that has
#'   just read the previous manifest can still finish.
#'
#' @param url The address of the published snapshots (the folder or its
#'   `manifest.json`). The default (`NULL`) uses the `aedes.snapshot_url`
#'   option if set, and otherwise the standard address, which needs access to
#'   the aedes CAVE datastack to work out.
#' @param root The local snapshot folder. Defaults to [aedes_snapshot_root()].
#' @param set Whether to select a snapshot with [aedes_use_snapshot()]
#'   afterwards.
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
                                    root = aedes_snapshot_root(create = TRUE),
                                    set = TRUE) {
  if (is.null(url)) url <- aedes_snapshot_url()
  tags <- synsnap_download(url, root)
  message(if (length(tags)) paste("Downloaded synapse snapshot(s)",
                                  paste(tags, collapse = ", "))
          else "Synapse snapshots are already up to date")
  if (set) aedes_use_snapshot(root = root)
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

# Address of the published snapshots: the aedes.snapshot_url option, or the
# standard one. Its folder name is a hash of the L2 ids of a fixed root id, so
# working it out needs access to the aedes chunkedgraph.
aedes_snapshot_url <- function() {
  url <- getOption("aedes.snapshot_url")
  if (!is.null(url) && nzchar(url)) return(url)
  l2 <- tryCatch(
    with_aedes(fafbseg::flywire_l2ids("648518347624785674", integer64 = TRUE)),
    error = function(e) stop("Could not work out the snapshot address, which ",
                             "needs access to the aedes CAVE datastack: ",
                             conditionMessage(e), call. = FALSE))
  paste0("https://flyemdev.mrc-lmb.cam.ac.uk/flyconnectome/aedes/",
         synsnap_l2_hash(l2), "/snapshot")
}

# sha256 of the unique ids in numeric order as decimal strings, one per line
# with no final newline
synsnap_l2_hash <- function(l2) {
  l2 <- sort(unique(bit64::as.integer64(l2)))
  digest::digest(paste(as.character(l2), collapse = "\n"), algo = "sha256",
                 serialize = FALSE)
}
