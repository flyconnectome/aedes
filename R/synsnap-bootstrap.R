# Building a first snapshot on a fresh host: download the source edgelist,
# then look up the root of every supervoxel at one time. Dataset-agnostic like
# R/synsnap.R; aedes supplies the url, the CAVE access (ctx) and verification.

# Download `url` (gs://bucket/object or https://...) to `dest` and check its
# md5 (hex, or base64 as GCS reports it). Uses `gcloud storage cp` (parallel
# sliced download, resumable) when `gcloud` is available, otherwise the curl
# command line tool, resuming a partial download. The url is never printed and
# the tools run silently, since it may point at data that should not be
# advertised.
synsnap_fetch_source <- function(url, dest, md5,
                                 method = c("auto", "gcloud", "curl"),
                                 gcloud = Sys.which("gcloud")) {
  method <- match.arg(method)
  if (method == "auto") method <- if (nzchar(gcloud)) "gcloud" else "curl"
  if (file.exists(dest) && synsnap_md5_ok(dest, md5)) return(invisible(dest))
  part <- paste0(dest, ".part")
  status <- if (method == "gcloud")
    system2(gcloud, c("storage", "cp", shQuote(url), shQuote(part)),
            stdout = FALSE, stderr = FALSE)
  else system2("curl", c("-fsSL", "-C", "-", "-o", shQuote(part),
                         shQuote(synsnap_https_url(url))),
               stdout = FALSE, stderr = FALSE)
  if (!identical(as.integer(status), 0L))
    stop("Download failed (", method, " exit status ", status, ")", call. = FALSE)
  if (!synsnap_md5_ok(part, md5)) {
    unlink(part)
    stop("Downloaded file has the wrong md5", call. = FALSE)
  }
  if (!file.rename(part, dest)) stop("Could not write ", dest, call. = FALSE)
  invisible(dest)
}

synsnap_https_url <- function(url)
  sub("^gs://", "https://storage.googleapis.com/", url)

synsnap_md5_ok <- function(f, md5) {
  if (!grepl("^[0-9a-f]{32}$", md5))
    md5 <- paste(as.character(jsonlite::base64_dec(md5)), collapse = "")
  identical(unname(tools::md5sum(f)), md5)
}

# md5 (base64) of a GCS object: from the x-goog-hash header, which needs no
# credentials for a public object, otherwise via gcloud
synsnap_gcs_md5 <- function(url, gcloud = Sys.which("gcloud")) {
  res <- try(httr::HEAD(synsnap_https_url(url)), silent = TRUE)
  if (!inherits(res, "try-error") && httr::status_code(res) == 200) {
    h <- strsplit(httr::headers(res)[["x-goog-hash"]], ",\\s*")[[1]]
    md5 <- sub("^md5=", "", grep("^md5=", h, value = TRUE))
    if (length(md5) == 1) return(md5)
  }
  if (!nzchar(gcloud))
    stop("Could not read the md5 of the source file", call. = FALSE)
  md5 <- suppressWarnings(system2(gcloud, c("storage", "objects", "describe",
                                            shQuote(url), "--format='value(md5_hash)'"),
                                  stdout = TRUE, stderr = FALSE))
  if (length(md5) != 1 || !nzchar(md5))
    stop("Could not read the md5 of the source file", call. = FALSE)
  md5
}

# Call f(), retrying after errors with increasing waits (seconds)
synsnap_retry <- function(f, wait = c(30, 120, 600)) {
  for (i in seq_len(length(wait) + 1)) {
    res <- tryCatch(f(), error = function(e) e)
    if (!inherits(res, "error")) return(res)
    if (i > length(wait)) stop(res)
    message("Retrying in ", wait[i], " s after error: ", conditionMessage(res))
    Sys.sleep(wait[i])
  }
}

# Supervoxel -> root map at `timestamp` for every pre_sv and post_sv in
# static.parquet, looked up with ctx$rootid in chunks of `chunksize`
# supervoxels. Each chunk is saved to <cache>/chunk-NNNNN.parquet as soon as it
# is done, so an interrupted lookup resumes where it stopped. Returns the chunk
# files (columns sv, root_id).
synsnap_lookup_svmap <- function(root, timestamp, ctx, cache, chunksize = 1e6,
                                 wait = c(30, 120, 600)) {
  timestamp <- format(synsnap_parse_time(timestamp), "%Y-%m-%d %H:%M:%OS6 UTC",
                      tz = "UTC")
  dir.create(cache, recursive = TRUE, showWarnings = FALSE)
  info <- list(timestamp = timestamp, chunksize = chunksize)
  fi <- file.path(cache, "lookup.json")
  if (file.exists(fi)) {
    old <- jsonlite::read_json(fi, simplifyVector = TRUE)
    if (!identical(old$timestamp, info$timestamp) || old$chunksize != chunksize)
      stop("Supervoxel lookup in ", cache, " is for a different timestamp or chunksize",
           call. = FALSE)
  } else jsonlite::write_json(info, fi, auto_unbox = TRUE, digits = NA)

  con <- synsnap_con()
  svs <- file.path(cache, "svs.parquet")
  if (!file.exists(svs)) {
    st <- synsnap_sql_str(synsnap_path(root, file = "static.parquet"))
    synsnap_write(con, sprintf(
      "SELECT sv, ((row_number() OVER (ORDER BY sv) - 1) // %d)::INTEGER AS chunk
       FROM (SELECT pre_sv AS sv FROM %s UNION SELECT post_sv FROM %s) ORDER BY sv",
      as.integer(chunksize), st, st), svs)
  }
  svs <- synsnap_sql_str(svs)
  n <- DBI::dbGetQuery(con, sprintf(
    "SELECT count(*) AS n, max(chunk) + 1 AS chunks FROM %s", svs))
  files <- file.path(cache, sprintf("chunk-%05d.parquet", seq_len(n$chunks) - 1L))
  todo <- which(!file.exists(files))
  if (length(todo))
    message("Looking up roots for ", format(n$n, big.mark = ","), " supervoxels: ",
            length(todo), " of ", n$chunks, " chunks to do")
  T <- synsnap_parse_time(timestamp)
  for (i in todo) {
    t0 <- Sys.time()
    sv <- DBI::dbGetQuery(con, sprintf(
      "SELECT sv FROM %s WHERE chunk = %d ORDER BY sv", svs, i - 1L))$sv
    r <- synsnap_retry(function() ctx$rootid(sv, T), wait = wait)
    if (length(r) != length(sv))
      stop("Root lookup returned ", length(r), " ids for ", length(sv),
           " supervoxels", call. = FALSE)
    local({
      nm <- synsnap_register(con, data.frame(sv = sv, root_id = bit64::as.integer64(r)))
      synsnap_write(con, paste("SELECT sv, root_id FROM", nm), files[i])
    })
    message(format(Sys.time(), "%H:%M:%S"), " chunk ", i, "/", n$chunks, ": ",
            round(as.numeric(difftime(Sys.time(), t0, units = "secs"))), " s")
  }
  files
}

# Full snapshot `tag` at `timestamp`, built from scratch by looking up the
# root of every supervoxel in static.parquet (see synsnap_lookup_svmap()). The
# lookup is cached in <root>/.staging/<tag>.svmap until the snapshot is in
# place, so rerunning after a failure only repeats unfinished chunks. See
# synsnap_stage() for `verify`.
synsnap_build_from_lookup <- function(tag, timestamp, root, ctx, verify = NULL,
                                      chunksize = 1e6, by_post = FALSE, ...) {
  if (file.exists(file.path(synsnap_path(root), tag, "meta.json")))
    stop("Synapse snapshot '", tag, "' already exists", call. = FALSE)
  cache <- file.path(synsnap_path(root), ".staging", paste0(tag, ".svmap"))
  files <- synsnap_lookup_svmap(root, timestamp, ctx, cache, chunksize = chunksize, ...)
  synsnap_build(tag, files, timestamp, root, by_post = by_post, verify = verify)
  unlink(cache, recursive = TRUE)
  invisible(tag)
}
