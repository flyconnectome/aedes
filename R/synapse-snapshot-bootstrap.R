#' Build the synapse snapshot from scratch
#'
#' @description Builds a complete local synapse snapshot on a new machine:
#'   downloads the edgelist behind the CAVE synapse table, converts it to
#'   `static.parquet`, then looks up the root ids of every synapse at a
#'   materialisation version to make the snapshot `v<version>`. This takes a
#'   few hours and needs about 25 GB of free space while it runs (2 GB after).
#'
#' @details The source file (a 22 GB csv) is found from the description of the
#'   CAVE synapse table, so you need access to the aedes CAVE datastack. It is
#'   downloaded with `gcloud storage cp` when the Google Cloud CLI is installed
#'   (fastest), otherwise with `curl`, and checked against its md5. It is
#'   deleted once `static.parquet` has been written unless `keep_source =
#'   TRUE`. `static.json` records the CAVE table name and md5 of the source
#'   file.
#'
#'   Root ids are looked up at the time of the materialisation `version`: by
#'   default the newest available version that does not expire within a day.
#'   The lookup is saved in chunks as it goes, so if it is interrupted (or the
#'   server fails) just run `aedes_synapse_snapshot_bootstrap()` again with the
#'   same `version` to carry on. Nothing is visible as a snapshot until it is
#'   complete and has been checked: the synapses of `n_verify` neurons of
#'   different sizes are compared with a CAVE query at the same version, and a
#'   snapshot with any difference is moved to `<root>/.failed` instead.
#'
#'   Later snapshots are built as small deltas against this one by
#'   [aedes_synapse_snapshot_update()].
#'
#' @param root Folder for the snapshot (created if needed).
#' @param version A CAVE materialisation version; `NULL` for the newest one
#'   that is available for at least a day.
#' @param keep_source Whether to keep the downloaded source file (in
#'   `<root>/.staging`).
#' @param n_verify Number of neurons to compare with CAVE.
#' @param by_post Whether to also write a copy of the root ids sorted by
#'   postsynaptic root (see [aedes_synapse_data()]).
#' @return The snapshot tag, invisibly.
#' @seealso [aedes_synapse_snapshot()], [aedes_synapse_snapshot_update()]
#' @export
#' @examples
#' \dontrun{
#' aedes_synapse_snapshot_bootstrap()
#' aedes_synapse_snapshot()
#' }
aedes_synapse_snapshot_bootstrap <- function(root = aedes_synapse_snapshot_root(create = TRUE),
                                             version = NULL, keep_source = FALSE,
                                             n_verify = 20, by_post = FALSE) {
  v <- aedes_synsnap_version(version)
  tag <- paste0("v", v$version)
  if (tag %in% synsnap_tags(root)$tag) {
    message("Synapse snapshot ", tag, " already exists")
    return(invisible(tag))
  }
  if (!file.exists(file.path(root, "static.json"))) {
    src <- aedes_synsnap_source()
    stage <- file.path(root, ".staging")
    dir.create(stage, recursive = TRUE, showWarnings = FALSE)
    csv <- file.path(stage, "source.csv")
    synsnap_step("Downloading source edgelist", synsnap_fetch_source(src$url, csv, src$md5))
    synsnap_step("Writing static.parquet", synsnap_build_static(
      csv, root, format = "csv", overwrite = TRUE,
      meta = list(source_table = src$table, source_md5 = src$md5)))
    if (!keep_source) unlink(csv)
  }
  synsnap_step(paste("Building snapshot", tag), synsnap_build_from_lookup(
    tag, v$timestamp, root, aedes_synsnap_ctx(), by_post = by_post,
    verify = function(stage) aedes_synsnap_verify(stage, root, v$version, n = n_verify)))
  invisible(tag)
}

synsnap_step <- function(what, expr) {
  message(format(Sys.time(), "%H:%M:%S "), what)
  t <- system.time(expr)
  message(format(Sys.time(), "%H:%M:%S "), what, ": done in ",
          round(t[["elapsed"]] / 60, 1), " min")
}

# CAVE table name, url and md5 (base64) of the source edgelist. The url comes
# from the table description and must never be printed or saved: see
# synsnap_fetch_source().
aedes_synsnap_source <- function(client = aedes_cave_client()) {
  table <- client$materialize$synapse_table
  desc <- client$materialize$get_table_metadata(table)$description
  url <- regmatches(desc, gregexpr("gs://[^[:space:]\"'<>]+", desc))[[1]]
  if (length(url) != 1)
    stop("Could not find the source file in the description of CAVE table ",
         table, call. = FALSE)
  list(table = table, url = url, md5 = synsnap_gcs_md5(url))
}

# version and timestamp of a materialisation version: the given one or the
# newest valid, available one with at least `min_life` before it expires
aedes_synsnap_version <- function(version = NULL, min_life = as.difftime(1, units = "days"),
                                  client = aedes_cave_client()) {
  vv <- dplyr::bind_rows(lapply(client$materialize$get_versions_metadata(), function(m)
    data.frame(version = m$version, timestamp = m$time_stamp, expires = m$expires_on,
               ok = isTRUE(m$valid) && identical(m$status, "AVAILABLE"))))
  if (is.null(version)) {
    vv <- vv[vv$ok & vv$expires > Sys.time() + min_life, ]
    if (!nrow(vv)) stop("No CAVE materialisation version is available", call. = FALSE)
    return(as.list(vv[which.max(vv$version), c("version", "timestamp")]))
  }
  vv <- vv[vv$version == version, ]
  if (!nrow(vv) || !vv$ok)
    stop("CAVE materialisation version ", version, " is not available", call. = FALSE)
  as.list(vv[c("version", "timestamp")])
}

# Compare the synapses of `n` roots of a snapshot with CAVE at `version`, both
# as outputs and inputs. Roots are spread from the one with most output
# synapses to ones with a handful. Synapse ids must match exactly. The
# materialised root ids in CAVE are occasionally stale for neurons edited just
# before the version was made, so synapses whose roots differ are checked again
# against the chunkedgraph at the snapshot time; any difference there is an
# error.
aedes_synsnap_verify <- function(tag, root, version, n = 20, ctx = aedes_synsnap_ctx()) {
  con <- synsnap_con()
  counts <- DBI::dbGetQuery(con, sprintf(
    "SELECT pre_root AS root_id, count(*) AS n FROM (%s) WHERE pre_root != 0
     GROUP BY pre_root ORDER BY n DESC, root_id", synsnap_rows_sql(tag, root)))
  ranks <- unique(round(exp(seq(0, log(nrow(counts)), length.out = n))))
  roots <- counts$root_id[ranks]
  i64 <- bit64::as.integer64
  cave_rows <- function(filter) {
    d <- aedes_cave_query("synapses_v2", version = version, fetch_all_rows = TRUE,
                          filter_in_dict = filter,
                          select_columns = c("id", "pre_pt_root_id", "post_pt_root_id"))
    data.frame(id = as.integer(d$id), cpre = i64(d$pre_pt_root_id),
               cpost = i64(d$post_pt_root_id))
  }
  local_rows <- function(d) data.frame(id = d$id, pre = d$pre_root, post = d$post_root)
  cave <- local <- NULL
  for (side in c("pre", "post")) {
    cave <- rbind(cave, cave_rows(stats::setNames(list(as.character(roots)),
                                                  paste0(side, "_pt_root_id"))))
    local <- rbind(local, local_rows(dplyr::collect(dplyr::filter(
      synsnap_tbl(tag, root), .data[[paste0(side, "_root")]] %in% roots))))
  }
  message("Checked ", nrow(cave), " synapses against CAVE")
  # a synapse can be on a query root on one side only when root ids differ
  ids <- setdiff(local$id, cave$id)
  if (length(ids)) cave <- rbind(cave, cave_rows(list(id = ids)))
  ids <- setdiff(cave$id, local$id)
  if (length(ids)) local <- rbind(local, local_rows(dplyr::collect(dplyr::filter(
    synsnap_tbl(tag, root), .data$id %in% ids))))
  m <- merge(unique(cave), unique(local), by = "id", all = TRUE)
  missing <- sum(is.na(m$cpre) | is.na(m$pre))
  if (missing)
    stop(missing, " synapse ids differ from CAVE version ", version, call. = FALSE)
  differ <- m$id[m$cpre != m$pre | m$cpost != m$post]
  if (length(differ)) {
    st <- dplyr::collect(dplyr::filter(synsnap_tbl(tag, root, static = TRUE),
                                       .data$id %in% differ))
    T <- synsnap_parse_time(synsnap_meta(tag, root)$timestamp)
    bad <- sum(ctx$rootid(st$pre_sv, T) != st$pre_root |
                 ctx$rootid(st$post_sv, T) != st$post_root)
    if (bad)
      stop(bad, " synapses have root ids that differ from the chunkedgraph",
           call. = FALSE)
    message(length(differ), " synapses with stale root ids in CAVE version ",
            version, " match the chunkedgraph")
  }
  invisible(TRUE)
}
