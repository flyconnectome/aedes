# Save a new local synapse snapshot at the current time, e.g. from a daily cron
# job: Rscript data-raw/synapse-snapshot-update.R
# Rebases when the delta exceeds `max_delta` rows, so that deltas stay small.
devtools::load_all(quiet = TRUE)
root <- getOption("aedes.synapse_snapshot_root")
max_delta <- 5e6
s <- aedes_synapse_snapshot_update(root = root, set = FALSE)
f <- file.path(root, s$tag, "delta.parquet")
n <- arrow::open_dataset(f)$num_rows
message(format(Sys.time()), " saved ", s$tag, " with ", n, " changed synapses")
if (n > max_delta) {
  synsnap_rebase(s$tag, root)
  message("rebased ", s$tag)
}
