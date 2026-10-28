# Live aedes_main (every status, mapped to now) for the write-path tests, which
# pick their neurons by status rather than pinning root ids (both drift with
# proofreading and annotation). Skips when FlyTable is unreachable.
#   single: neurons with exactly one row, which is usable
#   only:   neurons whose only rows are duplicate/bad_nucleus/not_a_neuron
#   mixed:  neurons with both a usable and an unusable row
live_aedes_main <- function() {
  am <- try(suppressWarnings(
    aedes_meta(timestamp = "now", drop_status = character(0))), silent = TRUE)
  testthat::skip_if(inherits(am, "try-error"), "aedes_meta() unavailable")
  am$root_id <- as.character(am$root_id)
  am <- am[!is.na(am$root_id) & am$root_id != "0", , drop = FALSE]
  am$unusable <- .aedes_is_unusable(am$status)
  ok <- unique(am$root_id[!am$unusable])
  bad <- unique(am$root_id[am$unusable])
  n <- table(am$root_id)
  list(am = am, single = intersect(ok, names(n)[n == 1L]),
       only = setdiff(bad, ok), mixed = intersect(bad, ok))
}

# The usable aedes_main row for each of `ids`
live_usable_row <- function(live, ids) {
  am <- live$am[!live$am$unusable, , drop = FALSE]
  am[match(ids, am$root_id), , drop = FALSE]
}
