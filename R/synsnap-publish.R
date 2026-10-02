# Publishing snapshots to a folder served over https, and downloading them.
# Dataset-agnostic like R/synsnap.R. The served folder holds only finished
# files plus manifest.json, which lists them with sizes and md5s and is always
# written last.

# Files (relative paths) that make up snapshot `tag`: its root id files (a
# full snapshot) or log (a checkpoint), then meta.json, which must be placed
# last
synsnap_tag_files <- function(tag, root) {
  d <- synsnap_path(root, tag)
  data <- if (is.na(synsnap_meta(tag, root)$base))
    sort(list.files(d, pattern = "^by_.*\\.parquet$")) else "log.parquet"
  file.path(tag, c(data, "meta.json"))
}

# Hard link (or, across filesystems, copy) `src` to `dest` unless `dest` is
# already the same file. A new file is placed with a rename, so readers never
# see a partial copy.
synsnap_place <- function(src, dest) {
  if (file.exists(dest)) {
    a <- file.info(src); b <- file.info(dest)
    if (a$size == b$size && as.numeric(a$mtime) == as.numeric(b$mtime))
      return(invisible(FALSE))
  }
  dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
  tmp <- paste0(dest, ".tmp")
  unlink(tmp)
  ok <- suppressWarnings(file.link(src, tmp)) ||
    file.copy(src, tmp, copy.date = TRUE)
  if (!ok || !file.rename(tmp, dest))
    stop("Could not publish ", basename(src), call. = FALSE)
  invisible(TRUE)
}

# Publish snapshot `latest` from `root` to `dest`, with every usable
# checkpoint built on the same full snapshot, that full snapshot and the
# static files. The md5s of unchanged files are reused from the previous
# manifest. Files only listed by the manifest before the previous one are
# removed, so a client that has just read the previous manifest can still
# finish downloading.
synsnap_publish <- function(root, dest, latest = synsnap_latest(root)) {
  if (!dir.exists(dest)) stop("No folder at ", dest, call. = FALSE)
  synsnap_chain(latest, root)
  snaps <- synsnap_tags(root)
  base <- snaps$base[match(latest, snaps$tag)]
  if (is.na(base)) base <- latest
  # in time order with the full snapshot first, so parents come before
  # their children
  snaps <- snaps[snaps$usable & (snaps$tag == base | snaps$base %in% base), , drop = FALSE]
  snaps <- snaps[order(snaps$tag != base), , drop = FALSE]
  tags <- snaps$tag
  files <- c("static.parquet", "static.json",
             unlist(lapply(tags, synsnap_tag_files, root = root)))
  mf <- file.path(dest, "manifest.json")
  old <- if (file.exists(mf)) jsonlite::read_json(mf, simplifyVector = TRUE)
  if (!is.null(old)) old$keep <- as.character(unlist(old$keep))
  src <- file.path(synsnap_path(root), files)
  info <- file.info(src)
  mtime <- format(info$mtime, "%Y-%m-%dT%H:%M:%OS3Z", tz = "UTC")
  md5 <- rep(NA_character_, length(files))
  if (!is.null(old)) {
    i <- match(files, old$files$path)
    same <- !is.na(i) & old$files$size[i] %in% info$size & old$files$mtime[i] %in% mtime
    same[is.na(same)] <- FALSE
    md5[same] <- old$files$md5[i[same]]
  }
  md5[is.na(md5)] <- unname(tools::md5sum(src[is.na(md5)]))
  for (i in seq_along(files)) synsnap_place(src[i], file.path(dest, files[i]))

  manifest <- list(
    format = 2L,
    created = format_utc(Sys.time()),
    latest = latest,
    snapshots = data.frame(tag = snaps$tag, timestamp = synsnap_format_time(snaps$timestamp),
                           base = snaps$base, parent = snaps$parent, kind = snaps$kind),
    files = data.frame(path = files, size = info$size, md5 = md5, mtime = mtime),
    keep = if (!is.null(old)) setdiff(old$files$path, files) else character())
  tmp <- paste0(mf, ".tmp")
  jsonlite::write_json(manifest, tmp, auto_unbox = TRUE, pretty = TRUE, digits = NA)
  if (!file.rename(tmp, mf)) stop("Could not write ", mf, call. = FALSE)

  if (!is.null(old)) {
    gone <- setdiff(old$keep, c(files, manifest$keep))
    unlink(file.path(dest, gone))
    for (d in unique(dirname(gone)))
      if (d != "." && !length(list.files(file.path(dest, d), all.files = TRUE, no.. = TRUE)))
        unlink(file.path(dest, d), recursive = TRUE)
  }
  invisible(manifest)
}

synsnap_manifest_url <- function(url)
  if (grepl("\\.json$", url)) url else paste0(sub("/+$", "", url), "/manifest.json")

# Download the snapshots listed in the manifest at `url` into `root`, each
# after the snapshot it is built on. Existing snapshots are never changed: a
# tag already in `root` is skipped, and a different static.json is an error.
# Each file is checked against its md5 and a snapshot's meta.json is placed
# last. With `full = FALSE`, full snapshots that `root` does not have yet
# (and checkpoints built on them) are skipped. Returns the tags downloaded,
# with the skipped full snapshots as attribute "skipped".
synsnap_download <- function(url, root, full = TRUE) {
  url <- synsnap_manifest_url(url)
  m <- tryCatch({
    con <- url(url)
    on.exit(close(con))
    jsonlite::fromJSON(paste(suppressWarnings(readLines(con, warn = FALSE)), collapse = "\n"))
  }, error = function(e)
    stop("Could not read the snapshot manifest (",
         gsub(url, "<url>", conditionMessage(e), fixed = TRUE), ")", call. = FALSE))
  if (!identical(as.integer(m$format), 2L))
    stop("Unsupported snapshot manifest format", call. = FALSE)
  base <- sub("[^/]*$", "", url)
  files <- m$files
  stage <- file.path(root, ".staging", "download")
  dir.create(stage, recursive = TRUE, showWarnings = FALSE)
  get <- function(paths) {
    f <- files[match(paths, files$path), , drop = FALSE]
    message("Downloading ", paste(f$path, collapse = ", "), " (",
            format(structure(sum(f$size), class = "object_size"), units = "auto"), ")")
    tmp <- file.path(stage, f$path)
    for (i in seq_len(nrow(f))) {
      dir.create(dirname(tmp[i]), recursive = TRUE, showWarnings = FALSE)
      synsnap_fetch_source(paste0(base, f$path[i]), tmp[i], f$md5[i], method = "curl")
    }
    # in order, so meta.json/static.json go last
    for (i in seq_len(nrow(f))) {
      dest <- file.path(root, f$path[i])
      dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
      if (!file.rename(tmp[i], dest)) stop("Could not write ", dest, call. = FALSE)
    }
  }
  sj <- file.path(root, "static.json")
  if (file.exists(sj)) {
    if (!identical(unname(tools::md5sum(sj)), files$md5[files$path == "static.json"]))
      stop("The snapshots in ", root, " were built from different static data; ",
           "use a new folder", call. = FALSE)
  } else get(c("static.parquet", "static.json"))
  snaps <- m$snapshots
  # a local tag only counts if it has the same base (it may since have been
  # made a full snapshot on the server)
  local <- synsnap_tags(root)
  have <- local$tag[local$base %in% snaps$base[match(local$tag, snaps$tag)]]
  todo <- setdiff(snaps$tag, have)
  skipped <- if (!full) todo[is.na(snaps$base[match(todo, snaps$tag)])]
  todo <- setdiff(todo, skipped)
  done <- character()
  while (length(todo)) {
    i <- match(todo, snaps$tag)
    ready <- is.na(snaps$base[i]) | snaps$parent[i] %in% c(have, done)
    if (!any(ready) && !full) break
    if (!any(ready))
      stop("The published snapshots ", paste(todo, collapse = ", "),
           " need snapshots that are not published", call. = FALSE)
    for (t in todo[ready]) get(files$path[startsWith(files$path, paste0(t, "/"))])
    done <- c(done, todo[ready])
    todo <- todo[!ready]
  }
  unlink(stage, recursive = TRUE)
  invisible(structure(done, skipped = skipped))
}
