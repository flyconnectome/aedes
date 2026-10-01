# Publishing snapshots to a folder served over https, and downloading them.
# Dataset-agnostic like R/synsnap.R. The served folder holds only finished
# files plus manifest.json, which lists them with sizes and md5s and is always
# written last.

# Files (relative paths) that make up snapshot `tag`: its data files, then
# meta.json, which must be placed last
synsnap_tag_files <- function(tag, root) {
  d <- synsnap_path(root, tag)
  data <- sort(list.files(d, pattern = "\\.parquet$"))
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

# Publish the newest snapshot in `root` (`tags`), its full base when it is a
# delta, and the static files to `dest`. The md5s of unchanged files are
# reused from the previous manifest. Files only listed by the manifest before
# the previous one are removed, so a client that has just read the previous
# manifest can still finish downloading.
synsnap_publish <- function(root, dest, tags = synsnap_latest(root)) {
  if (!dir.exists(dest)) stop("No folder at ", dest, call. = FALSE)
  bases <- vapply(tags, function(t) {
    b <- synsnap_meta(t, root)$base
    if (is.na(b)) NA_character_ else as.character(b)
  }, "")
  tags <- unique(c(stats::na.omit(bases), tags))
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

  snaps <- synsnap_tags(root)
  snaps <- snaps[snaps$tag %in% tags, , drop = FALSE]
  manifest <- list(
    format = 1L,
    created = format_utc(Sys.time()),
    latest = tags[length(tags)],
    snapshots = data.frame(tag = snaps$tag, timestamp = format_utc(snaps$timestamp, 6),
                           base = snaps$base),
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

# Download the snapshots listed in the manifest at `url` into `root`. Existing
# snapshots are never changed: a tag already in `root` is skipped, and a
# different static.json is an error. Each file is checked against its md5 and
# a snapshot's meta.json is placed last. Returns the tags downloaded.
synsnap_download <- function(url, root) {
  url <- synsnap_manifest_url(url)
  m <- tryCatch({
    con <- url(url)
    on.exit(close(con))
    jsonlite::fromJSON(paste(readLines(con, warn = FALSE), collapse = "\n"))
  }, error = function(e)
    stop("Could not read the snapshot manifest (",
         gsub(url, "<url>", conditionMessage(e), fixed = TRUE), ")", call. = FALSE))
  if (!identical(as.integer(m$format), 1L))
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
  have <- synsnap_tags(root)$tag
  todo <- setdiff(m$snapshots$tag, have)
  # bases before the deltas that need them
  todo <- todo[order(!is.na(m$snapshots$base[match(todo, m$snapshots$tag)]))]
  for (t in todo) get(files$path[startsWith(files$path, paste0(t, "/"))])
  unlink(stage, recursive = TRUE)
  invisible(todo)
}
