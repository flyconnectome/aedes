test_that("aedes_partner_summary summarises downstream partners", {
  # Pin the query neuron by a stable raw coordinate (root ids drift with
  # proofreading) and resolve it to the *current* root id at test time. This is
  # the same stable handle used in test-chunkedgraph.R. The partner query then
  # runs against the latest materialisation (no version pin), since old
  # materialisation versions expire for synapse queries.
  pt <- c(24606, 12450, 5798)
  id <- try(aedes_xyz2id(pt, rawcoords = TRUE), silent = TRUE)
  skip_if(inherits(id, "try-error") || identical(id, "0"),
          "Skipping: transform service unavailable")

  ps <- try(aedes_partner_summary(id, partners = "outputs"), silent = TRUE)
  skip_if(inherits(ps, "try-error") || !is.data.frame(ps),
          "Skipping: no CAVE synapse access to aedes materialisation")

  skip_if(nrow(ps) == 0L, "Skipping: no downstream partners returned")
  expect_true(all(c("query", "post_id", "weight") %in% colnames(ps)))
  # for outputs every row shares the single query neuron as presynaptic partner
  expect_equal(unique(as.character(ps$query)), as.character(id))
  expect_true(all(ps$weight > 0))

  # threshold filters on synapse count
  strong <- try(aedes_partner_summary(id, partners = "outputs", threshold = 4),
                silent = TRUE)
  skip_if(inherits(strong, "try-error"), "Skipping: threshold query failed")
  expect_true(all(strong$weight > 4))
  expect_lte(nrow(strong), nrow(ps))
})

test_that("CAVE partner queries follow the aedes.version option", {
  got <- NULL
  local_mocked_bindings(
    aedes_get_version = function(...) list(version = 519L, timestamp = NULL),
    aedes_ids = function(ids, ...) ids)
  local_mocked_bindings(
    flywire_version = function(version, ...) version,
    flywire_latestid = function(rootids, ...) rootids,
    flywire_partner_summary = function(rootids, version, timestamp, ...)
      got <<- list(version = version, timestamp = timestamp),
    .package = "fafbseg")
  q <- function(which) withr::with_options(list(aedes.version = which), {
    aedes_partner_summary("1", method = "cave")
    got
  })
  expect_equal(q("latest"), list(version = 519L, timestamp = NULL))
  expect_equal(q(518), list(version = 519L, timestamp = NULL))
  # "now" stays a live query
  expect_equal(q("now"), list(version = NULL, timestamp = NULL))
})
