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
