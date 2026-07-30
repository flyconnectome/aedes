## Build the bundled Aedes <-> Drosophila (FlyWire) thin-plate spline registrations.
##
## Where the registration comes from
## --------------------------------
## The whole-brain warp is built in a separate analysis repo,
## https://github.com/flyconnectome/2025aedes, not here. There, cognate neuron
## pairs (same cell type identified in both datasets) are brought into a shared
## frame by a whole-brain affine, warped pair by pair with Deformetrica, and the
## displacements of every pair that moved are combined into one dense composite
## thin-plate spline. That repo emits, per direction:
##
##   deform/output/wb_fafb2aedes_composite_tps_<YYYYMMDD>.rds   FlyWire -> Aedes
##   deform/output/wb_aedes2fafb_composite_tps_<YYYYMMDD>.rds   Aedes -> FlyWire
##
## plus an undated copy of each meaning "latest". Those carry ~16k landmark
## PAIRS and are far too heavy to ship or to use interactively (see below).
##
## What this script does
## ---------------------
## 1. reads the latest composite TPS for each direction from the 2025aedes repo
## 2. thins it to `n_landmarks` control points, sampled SPATIALLY EVENLY but
##    more densely where the field actually varies (see "Sampling" below)
## 3. converts nm -> microns, matching the convention of the bundled
##    aedes_aedesSym_1000_tps.rds registration
## 4. PRECOMPUTES the spline coefficients with Morpho::computeTransform(), and
##    ships that rather than the raw landmark pairs
## 5. writes inst/extdata/{aedes_flywire,flywire_aedes}_<n>_tps.rds
##
## Why precomputed coefficients
## ----------------------------
## A thin-plate spline must solve a dense (n+4)^2 system before it can transform
## anything, and Morpho::tps3d() re-solves on EVERY call. Measured on this data:
## at 8000 landmarks a bare tps3d() call costs 72.5 s whereas applying
## precomputed coefficients costs 0.71 s -- 102x faster, bit-identical output.
## At the full 16118 landmarks the system is numerically singular
## (reciprocal condition number 2e-16) and the raw form costs ~610 s per call.
##
## Why both directions rather than inverting one
## ---------------------------------------------
## A thin-plate spline refitted the other way round is NOT the inverse of the
## forward map. Round-tripping a point through nat::reglist(swap = TRUE) here
## costs a median of 9.4 um (p95 32 um) -- comparable to the registration's own
## residual. Two small files are cheaper than that error.
##
## Sampling
## --------
## The composite TPS anchors are wildly non-uniform: dense in the central brain
## where cognate pairs cluster, sparse in the optic lobes. Sampling at random
## thins the sparse regions in proportion and throws away exactly the coverage
## that is hardest to replace. Instead we bin the source points, and give each
## bin a quota proportional to the LOCAL VARIABILITY of the displacement inside
## it, with a floor of one so no occupied bin is emptied. Variability rather
## than magnitude: the displacement carries the whole inter-brain offset, which
## is large everywhere and perfectly smooth, so magnitude would just re-measure
## a constant.
##
## Run from package root:
##   Rscript data-raw/aedes_flywire_tps.R
##   AEDES_DEFORM_REPO=/path/to/2025aedes Rscript data-raw/aedes_flywire_tps.R

suppressMessages({
  library(Morpho)
  library(nat)
})

deform_repo <- Sys.getenv("AEDES_DEFORM_REPO", "../2025aedes")
n_landmarks <- as.integer(Sys.getenv("AEDES_TPS_N", "3000"))
alpha <- 3 # how hard to favour high-variability regions
stopifnot(dir.exists(deform_repo), is.finite(n_landmarks), n_landmarks > 4)

# ---------------------------------------------------------------------------
# Adaptive thinning: even in space, denser where the field varies
# ---------------------------------------------------------------------------

thin_landmarks <- function(refmat, tarmat, n, alpha = 3) {
  d <- tarmat - refmat
  rng <- apply(refmat, 2, range)
  nb <- max(2L, ceiling((n / 2)^(1 / 3)))
  bin <- vapply(1:3, function(i) {
    b <- floor((refmat[, i] - rng[1, i]) / max(1e-9, diff(rng[, i])) * nb)
    pmin(pmax(b, 0), nb - 1)
  }, numeric(nrow(refmat)))
  occ <- split(seq_len(nrow(refmat)), bin[, 1] + nb * bin[, 2] + nb * nb * bin[, 3])
  spread <- vapply(occ, function(ix) {
    if (length(ix) < 2) 0 else sum(apply(d[ix, , drop = FALSE], 2, stats::var))
  }, numeric(1))
  s <- sqrt(spread)
  ref_s <- stats::median(s[s > 0])
  if (!is.finite(ref_s) || ref_s == 0) ref_s <- 1
  w <- 1 + alpha * (s / ref_s)
  quota <- pmin(lengths(occ), pmax(1L, as.integer(floor(n * w / sum(w)))))
  # top up to the requested budget: flooring the per-bin share leaves us short,
  # and we would rather the filename reflect what the file actually contains
  while (sum(quota) < n && any(lengths(occ) > quota)) {
    room <- lengths(occ) > quota
    add <- pmin(
      lengths(occ) - quota,
      pmax(1L, as.integer(round((n - sum(quota)) * w * room / sum(w[room]))))
    )
    add[!room] <- 0L
    if (!any(add > 0)) break
    quota <- quota + pmin(add, n - sum(quota))
  }
  keep <- unlist(
    Map(function(ix, q) if (length(ix) <= q) ix else sample(ix, q), occ, quota),
    use.names = FALSE
  )
  sort(unique(keep))
}

# ---------------------------------------------------------------------------
# Build one direction
# ---------------------------------------------------------------------------

build_one <- function(src_file, out_file) {
  message("reading ", src_file)
  b <- readRDS(src_file)
  r <- b$reg
  set.seed(42)
  keep <- thin_landmarks(r$refmat, r$tarmat, n_landmarks, alpha = alpha)
  # nm -> microns, matching aedes_aedesSym_1000_tps.rds
  ref <- r$refmat[keep, , drop = FALSE] / 1e3
  tar <- r$tarmat[keep, , drop = FALSE] / 1e3
  message(sprintf(
    "  %d of %d landmarks kept; precomputing coefficients...",
    length(keep), nrow(r$refmat)
  ))
  cf <- Morpho::computeTransform(tar, ref, type = "tps", lambda = r$lambda)
  # nat::xform() dispatches on "tpsreg"; Morpho::applyTransform on "tpsCoeff"
  class(cf) <- c("tpsreg", class(cf))
  attr(cf, "source") <- basename(src_file)
  attr(cf, "created") <- as.character(Sys.Date())
  saveRDS(cf, out_file, compress = "xz")
  message(sprintf(
    "  wrote %s (%.0f KiB)", out_file, file.info(out_file)$size / 1024
  ))
  invisible(cf)
}

dir.create("inst/extdata", showWarnings = FALSE, recursive = TRUE)
out <- file.path("inst", "extdata")

# The composite TPS is stored by the DIRECTION IT MAPS. `wb_fafb2aedes` takes
# FlyWire points into Aedes space, so it is the one to load when to = "aedes".
build_one(
  file.path(deform_repo, "deform/output/wb_aedes2fafb_composite_tps.rds"),
  file.path(out, sprintf("aedes_flywire_%d_tps.rds", n_landmarks))
)
build_one(
  file.path(deform_repo, "deform/output/wb_fafb2aedes_composite_tps.rds"),
  file.path(out, sprintf("flywire_aedes_%d_tps.rds", n_landmarks))
)

message("done")
