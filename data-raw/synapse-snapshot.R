# Build a local synapse snapshot (see ?aedes_synapse_snapshot) from the
# 260226_v3 synapse edgelist and a supervoxel -> root map at CAVE
# materialisation v513, then check it against the map's root counts and CAVE.
#
# Inputs (not in the package):
#   edgelist  final_edgelist-260226_v3-zstd15-sorted.feather
#   svdir     folder of chunk-*.feather files with columns sv, root_id covering
#             every presyn_basin / postsyn_basin, plus root_counts_v513.feather
#   root      output folder, which becomes aedes.synapse_snapshot_root
devtools::load_all()
suppressPackageStartupMessages(library(dplyr, warn.conflicts = FALSE))
datadir <- getOption("aedes.synapse_source_dir", "~/projects/2025aedes/data")
root <- getOption("aedes.synapse_snapshot_root", file.path(datadir, "syn_snapshot"))
edgelist <- file.path(datadir, "final_edgelist-260226_v3-zstd15-sorted.feather")
svdir <- file.path(datadir, "svid_root_v513")
tag <- "v513"
timestamp <- "2026-09-25 14:12:26 UTC"

tm <- function(expr, what) {
  t <- system.time(expr)
  message(format(Sys.time(), "%H:%M:%S "), what, ": ", round(t[["elapsed"]]), " s")
}
dir.create(root, showWarnings = FALSE)
if (!file.exists(file.path(root, "static.parquet")))
  tm(synsnap_build_static(edgelist, root), "static.parquet")
if (!file.exists(file.path(root, tag, "meta.json")))
  tm(synsnap_build(tag, list.files(svdir, "^chunk-.*\\.feather$", recursive = TRUE,
                                   full.names = TRUE),
                   timestamp = timestamp, root = root), tag)

# ---- checks ----
con <- synsnap_con()
n <- DBI::dbGetQuery(con, sprintf("SELECT count(*) AS n, count(DISTINCT id) AS nid,
  sum((pre_root = 0)::INT) AS pre0, sum((post_root = 0)::INT) AS post0 FROM (%s)",
  synsnap_rows_sql(tag, root)))
print(n)
stopifnot(n$n == 111253775, n$nid == n$n)

# output counts agree with root_counts_v513
rc <- arrow::read_feather(file.path(svdir, "root_counts_v513.feather"))
top <- rc |> slice_head(n = 1e4) |> filter(npre > 0)
tm(np <- synsnap_query(top$root_id, "pre", tag = tag, root = root) |>
     group_by(root_id = pre_root) |> summarise(npre = sum(weight)), "npre for top 10k")
stopifnot(isTRUE(all.equal(
  np$npre[match(as.character(top$root_id), as.character(np$root_id))], top$npre)))

# DNaa07_R partners against CAVE, both directions
rid <- "648518347528069964"
cave <- function(col, other) with_aedes(fafbseg::flywire_cave_query(
  "synapses_v2", version = 513, filter_in_dict = setNames(list(rid), col),
  select_columns = c("id", col, other))) |>
  count(partner = as.character(.data[[other]]), name = "cave")
local <- function(partners) synsnap_partner_summary(
  rid, partners, tag = tag, root = root, remove_autapses = FALSE) |>
  select(partner = 2, local = weight)
chk <- list(
  outputs = full_join(cave("pre_pt_root_id", "post_pt_root_id"), local("outputs"), by = "partner"),
  inputs = full_join(cave("post_pt_root_id", "pre_pt_root_id"), local("inputs"), by = "partner"))
for (d in names(chk)) {
  x <- filter(chk[[d]], partner != "0")
  message(d, ": ", nrow(x), " partners, ", sum(x$cave, na.rm = TRUE), " synapses, mismatches ",
          sum(is.na(x$cave) | is.na(x$local) | x$cave != x$local))
}
