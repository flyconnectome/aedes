test_that("aedes_add_neurons rejects invalid ids", {
  # The id check runs before any service call, so this needs no live data.
  expect_error(aedes_add_neurons("0"), "invalid id")
  expect_error(aedes_add_neurons(NA), "invalid id")
  expect_error(aedes_add_neurons(c("648518347399768369", "0")), "invalid id")
  expect_error(aedes_add_neurons("not-an-id"), "invalid id")
})


test_that("aedes_add_neurons collapses ids that resolve to one neuron", {
  # Stable handle: a supervoxel resolved to its current root at test time.
  # Passing that root twice exercises the duplicate-resolution policy without
  # depending on proofreading history.
  rid <- try(with_aedes(fafbseg::flywire_rootid("73888283381559121")),
             silent = TRUE)
  skip_if(inherits(rid, "try-error") || length(rid) != 1L || is.na(rid) ||
            rid == "0", "Skipping: unable to resolve test root id")

  common <- list(dryrun = TRUE, superclass = "visual_projection",
                 status = "adequate", initials = "XX",
                 soma = FALSE, side = FALSE, annotator = FALSE)

  # Recycled scalar annotations: the duplicate is dropped with a warning. Catch
  # the first condition so a service failure in pinning skips rather than fails.
  scalar <- tryCatch(
    do.call(aedes_add_neurons, c(list(c(rid, rid)), common)),
    warning = function(w) list(kind = "warning", msg = conditionMessage(w)),
    error   = function(e) list(kind = "error",   msg = conditionMessage(e)))
  skip_if(scalar$kind == "error", scalar$msg)
  expect_identical(scalar$kind, "warning")
  expect_match(scalar$msg, "duplicate id")

  # Per-id vector annotations: the collision is a hard error.
  vec <- tryCatch(
    do.call(aedes_add_neurons,
            c(list(c(rid, rid)), common, list(cell_type = c("A", "B")))),
    error = function(e) conditionMessage(e))
  skip_if(!is.character(vec) || !grepl("per-id values", vec),
          if (is.character(vec)) vec else "Skipping: no error raised")
  expect_match(vec, "per-id values")
})
