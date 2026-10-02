#!/bin/sh
# Make and publish Aedes synapse snapshot checkpoints. Run hourly from cron on
# the server that publishes snapshots, e.g.
#
#   17 * * * * /path/to/synsnap-cron.sh >> /path/to/synsnap-cron.log 2>&1
#
# Settings come from environment variables (keep them in a local file named by
# SYNSNAP_ENV, default ~/.synsnap-cron, rather than in this script, since the
# publish folder name is not public):
#
#   SYNSNAP_ROOT  snapshot folder (with static.parquet and a full snapshot)
#   SYNSNAP_DEST  folder served over https to publish into
#   SYNSNAP_THREADS  DuckDB threads (optional)
#
# Each run makes any missing materialisation version checkpoints, and
# 20:00 UTC ones for days without a version, from the last week, publishes
# and writes status.json in SYNSNAP_DEST. It exits with an error (so cron
# mails the output) if anything failed or the newest snapshot is more than
# 36 hours old. flock skips a run while the
# previous one is still going.
set -eu
ENVFILE="${SYNSNAP_ENV:-$HOME/.synsnap-cron}"
[ -f "$ENVFILE" ] && . "$ENVFILE"
: "${SYNSNAP_ROOT:?set SYNSNAP_ROOT}"
: "${SYNSNAP_DEST:?set SYNSNAP_DEST}"
export SYNSNAP_ROOT SYNSNAP_DEST
exec flock -n "$SYNSNAP_ROOT/.synsnap-cron.lock" Rscript -e '
  threads <- Sys.getenv("SYNSNAP_THREADS")
  if (nzchar(threads)) options(aedes.duckdb_threads = as.integer(threads))
  cat(format(Sys.time(), tz = "UTC", usetz = TRUE), "\n")
  s <- aedes:::aedes_synsnap_server(Sys.getenv("SYNSNAP_ROOT"), Sys.getenv("SYNSNAP_DEST"))
  cat("built:", if (length(s$built)) s$built else "nothing", "\n")
'
