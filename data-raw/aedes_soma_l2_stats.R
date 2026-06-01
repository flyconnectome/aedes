## Build a population L2-attribute model of what makes an L2 chunk a soma.
##
## Training data
## -------------
## Positives: every Kenyon Cell (KC) with a FlyTable soma_xyz that matches a
##   flywire_nuclei row. For each such KC we take the L2 chunk nearest the
##   recorded soma. Reliable because KCs are abundant, stereotyped, and all
##   have somas in the central brain.
##
## Negatives (hard): KCs explicitly flagged "bad" in
##   https://spelunker.cave-explorer.org/#!middleauth+https://global.daf-apis.com/nglstate/api/v1/5305742096596992
##   These are KCs with soma_xyz annotations that turned out to be wrong (e.g.
##   placed on a primary neurite rather than the soma). For each we take the
##   L2 chunk at the annotated point -- by construction NOT a real soma.
##
## Negatives (soft): a random sample of L2 chunks from `sensory` and
##   `ascending_neuron` superclass neurons. Their cell bodies lie outside the
##   central brain, so every L2 chunk inside the brain is by construction not
##   a soma.
##
## Model outputs (saved to data/aedes_soma_l2_stats.rda)
## -----------------------------------------------------
## * positive_mean / positive_cov / positive_quantiles -- multivariate stats
##   for Mahalanobis distance on the 5 shape features (log-area, log-size,
##   log-max_dt, log-mean_dt, roundness) plus per-feature P5..P95 quantiles.
## * dist_npil_density -- empirical density of signed neuropil distance (um)
##   over the full flywire_nuclei population, mixed with a small uniform
##   background. Used by the scoring as a non-parametric prior on the signed
##   distance from neuropil mesh (asymmetric, so Mahalanobis mis-specifies it).
## * dist_penalty_weight -- multiplier on the dist_npil penalty term in the
##   combined score (default 1.0).
## * metadata: feature names, transforms, training-set sizes, build date.
##
## Cache
## -----
## L2-attribute fetches go through data-raw/.soma_l2_cache/ so reruns are
## cheap. Delete the cache directory to force a fresh fetch.
##
## Run from package root:
##   Rscript data-raw/aedes_soma_l2_stats.R

suppressMessages({
  library(aedes)
  library(fafbseg)
  library(dplyr)
  library(nat)
})

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

smoke_test <- isTRUE(as.logical(Sys.getenv("AEDES_SOMA_SMOKE", "FALSE")))
# Smoke test mode trims the training set to the first 50 KCs and 200 soft-neg
# neurons so the whole pipeline runs in ~2 min for sanity-checking. Real run:
#   Rscript data-raw/aedes_soma_l2_stats.R
# Smoke test:
#   AEDES_SOMA_SMOKE=TRUE Rscript data-raw/aedes_soma_l2_stats.R

cache_dir <- if (smoke_test) "data-raw/.soma_l2_cache_smoke" else "data-raw/.soma_l2_cache"
dir.create(cache_dir, showWarnings = FALSE, recursive = TRUE)
neg_sample_per_neuron <- 10L                # L2 chunks sampled per sensory id
bad_scene_url <- "https://spelunker.cave-explorer.org/#!middleauth+https://global.daf-apis.com/nglstate/api/v1/5305742096596992"

# KDE prior on signed neuropil distance (um). The full distribution is
# strongly asymmetric (heavy left tail outside the neuropil, sharp cliff at 0,
# small right tail inside) so Mahalanobis mis-specifies it. We mix the
# empirical KDE with a small uniform background so the prior is never zero
# (real central-brain neurons can sit 0-3 um inside the neuropil).
dist_kde_support <- c(-200, 50)             # um; covers the full observed range
dist_kde_n       <- 1024L                   # grid points
dist_uniform_eps <- 0.001                   # 0.1% uniform background mass
dist_kde_chunksize <- 5000L                 # chunk size for pointsinside

cached <- function(name, fn) {
  f <- file.path(cache_dir, paste0(name, ".rds"))
  if (file.exists(f)) {
    message("[cache hit] ", name)
    readRDS(f)
  } else {
    message("[fetching]  ", name)
    out <- fn()
    saveRDS(out, f)
    out
  }
}

# ---------------------------------------------------------------------------
# 1. Resolve bad KC root_ids from the user-curated neuroglancer scene
# ---------------------------------------------------------------------------
# Note: we ALWAYS re-resolve the xyz via aedes_xyz2id rather than trusting the
# cached `segments` field on the annotation -- the segmentation evolves and
# the cached root_id can be stale.

bad_kcs <- cached("bad_kcs", function() {
  sc <- ngl_decode_scene(bad_scene_url)
  ann <- sc$layers$bad$annotations
  pts <- t(vapply(ann, function(a) as.numeric(a$point), numeric(3)))
  colnames(pts) <- c("x", "y", "z")
  seg <- aedes_xyz2id(pts, rawcoords = TRUE)
  pts_nm <- aedes_raw2nm(pts)
  data.frame(
    root_id = as.character(seg),
    bad_position = nat::xyzmatrix2str(pts_nm),
    stringsAsFactors = FALSE
  ) %>% filter(!is.na(.data$root_id) & .data$root_id != "0")
})

message("bad KCs resolved: ", nrow(bad_kcs))

# ---------------------------------------------------------------------------
# 2. Identify population pools
# ---------------------------------------------------------------------------

all_meta <- cached("all_meta", function() aedes_meta())

# Clean positives: KCs with FT soma AND a matched nucleus, excluding the bad list
kc_train <- all_meta %>%
  filter(.data$class == "KC",
         !is.na(.data$soma_xyz), nzchar(.data$soma_xyz),
         !is.na(.data$nucleus_id),
         !.data$root_id %in% bad_kcs$root_id)

# Soft-negative pool: sensory + ascending_neuron neurons
neg_pool <- all_meta %>%
  filter(.data$superclass %in% c("sensory", "ascending_neuron"))

if (smoke_test) {
  kc_train <- kc_train[seq_len(min(50, nrow(kc_train))), , drop = FALSE]
  neg_pool <- neg_pool[seq_len(min(200, nrow(neg_pool))), , drop = FALSE]
  message("[SMOKE TEST MODE] trimmed to 50 KCs + 200 soft-negative neurons")
}

message(sprintf("training: %d KC positives, %d bad-KC hard negatives, %d soft-negative neurons",
                nrow(kc_train), nrow(bad_kcs), nrow(neg_pool)))

# ---------------------------------------------------------------------------
# 3. Helpers: fetch + score L2 attributes, find chunk closest to a target point
# ---------------------------------------------------------------------------

# Pull all L2 attributes for one root_id (with caching at the per-id level via
# fafbseg's flywire_l2attributes -> flywire_l2ids cache).
l2_attrs_for <- function(rid) {
  tryCatch(
    with_aedes(fafbseg::flywire_l2attributes(rootid = rid)),
    error = function(e) NULL
  )
}

# Return the row of `df` whose rep_coord_nm is closest to `target_nm` (length-3).
nearest_l2_row <- function(df, target_nm) {
  if (is.null(df) || !nrow(df)) return(NULL)
  xyz <- as.matrix(df[, c("rep_coord_nm_x","rep_coord_nm_y","rep_coord_nm_z")])
  d2  <- rowSums(sweep(xyz, 2, target_nm)^2)
  df[which.min(d2), , drop = FALSE]
}

# ---------------------------------------------------------------------------
# 4. Fetch positive training rows (one L2 chunk per KC, nearest the FT soma)
# ---------------------------------------------------------------------------

pos_rows <- cached("pos_rows", function() {
  out <- pbapply::pblapply(seq_len(nrow(kc_train)), function(i) {
    rid <- kc_train$root_id[i]
    target_nm <- as.numeric(aedes_raw2nm(nat::xyzmatrix(kc_train$soma_xyz[i])))
    if (!all(is.finite(target_nm))) return(NULL)
    df <- l2_attrs_for(rid)
    if (is.null(df) || !nrow(df)) return(NULL)
    row <- nearest_l2_row(df, target_nm)
    row$root_id <- rid
    row
  })
  do.call(rbind, Filter(Negate(is.null), out))
})

message("positive rows fetched: ", nrow(pos_rows))

# ---------------------------------------------------------------------------
# 5. Fetch bad-KC hard negatives (chunk at the annotated bad point)
# ---------------------------------------------------------------------------

bad_rows <- cached("bad_rows", function() {
  out <- lapply(seq_len(nrow(bad_kcs)), function(i) {
    rid <- bad_kcs$root_id[i]
    target_nm <- as.numeric(nat::xyzmatrix(bad_kcs$bad_position[i]))
    df <- l2_attrs_for(rid)
    if (is.null(df) || !nrow(df)) return(NULL)
    row <- nearest_l2_row(df, target_nm)
    row$root_id <- rid
    row
  })
  do.call(rbind, Filter(Negate(is.null), out))
})

message("bad-KC negative rows fetched: ", nrow(bad_rows))

# ---------------------------------------------------------------------------
# 6. Fetch soft negatives (sampled L2 chunks per sensory/ascending neuron)
# ---------------------------------------------------------------------------

soft_rows <- cached("soft_rows", function() {
  set.seed(20260524)
  # Build l2id -> root_id sample list. Cheap: flywire_l2ids is cached.
  pairs <- pbapply::pblapply(neg_pool$root_id, function(rid) {
    l2ids <- tryCatch(
      with_aedes(fafbseg::flywire_l2ids(rid, integer64 = TRUE)),
      error = function(e) NULL
    )
    if (is.null(l2ids) || !length(l2ids)) return(NULL)
    s <- sample(as.character(l2ids), min(neg_sample_per_neuron, length(l2ids)))
    data.frame(root_id = rid, l2_id = s, stringsAsFactors = FALSE)
  })
  pairs <- do.call(rbind, Filter(Negate(is.null), pairs))
  message("sampled ", nrow(pairs), " soft-negative l2_ids; fetching attrs in chunks...")
  chunks <- nat.utils::make_chunks(pairs$l2_id, chunksize = 5000L)
  attrs <- pbapply::pblapply(chunks, function(ids) {
    with_aedes(fafbseg::flywire_l2attributes(l2ids = bit64::as.integer64(ids)))
  })
  attrs <- do.call(rbind, attrs)
  attrs$l2_id_chr <- as.character(attrs$l2_id)
  attrs <- attrs %>% left_join(pairs, by = c("l2_id_chr" = "l2_id"))
  attrs$l2_id_chr <- NULL
  attrs
})

message("soft-negative rows fetched: ", nrow(soft_rows))

# ---------------------------------------------------------------------------
# 7. Build labeled feature matrix (5 shape features only; dist_npil is
#    handled separately via the empirical KDE prior below).
# ---------------------------------------------------------------------------

mesh <- aedes_neuropil_mesh
compute_features <- function(df) {
  xyz <- as.matrix(df[, c("rep_coord_nm_x","rep_coord_nm_y","rep_coord_nm_z")])
  d <- pointsinside(xyz, surf = mesh, rval = "dist")
  data.frame(
    root_id        = df$root_id,
    l2_id          = as.character(df$l2_id),
    log_area_nm2   = log1p(pmax(df$area_nm2, 0)),
    log_size_nm3   = log1p(pmax(df$size_nm3, 0)),
    log_max_dt_nm  = log1p(pmax(df$max_dt_nm, 0)),
    log_mean_dt_nm = log1p(pmax(df$mean_dt_nm, 0)),
    roundness      = ifelse(df$pca_val_0 > 0, df$pca_val_2 / df$pca_val_0, NA_real_),
    dist_npil_nm   = d,
    stringsAsFactors = FALSE
  )
}

pos_feat  <- compute_features(pos_rows)
bad_feat  <- compute_features(bad_rows)
soft_feat <- compute_features(soft_rows)

pos_feat$label  <- 1L
bad_feat$label  <- 0L
soft_feat$label <- 0L

train <- rbind(pos_feat, bad_feat, soft_feat)
train <- train[stats::complete.cases(train[, -(1:2)]), , drop = FALSE]
message("training rows after dropping NAs: ", nrow(train),
        " (", sum(train$label == 1L), " positives, ",
        sum(train$label == 0L), " negatives)")

shape_feat_names <- c("log_area_nm2", "log_size_nm3", "log_max_dt_nm",
                      "log_mean_dt_nm", "roundness")

# ---------------------------------------------------------------------------
# 8. Fit Mahalanobis population stats on the 5 shape features
# ---------------------------------------------------------------------------

pos_only <- train[train$label == 1L, shape_feat_names, drop = FALSE]
positive_mean <- colMeans(pos_only, na.rm = TRUE)
positive_cov  <- stats::cov(pos_only, use = "complete.obs")
positive_quantiles <- sapply(pos_only, stats::quantile,
                             probs = c(0.05, 0.10, 0.25, 0.5, 0.75, 0.90, 0.95),
                             na.rm = TRUE)

# ---------------------------------------------------------------------------
# 9. Empirical KDE prior on signed neuropil distance (um).
# Built from the full flywire_nuclei population (so ~100k+ data points).
# ---------------------------------------------------------------------------

nucleus_neuropil_distance <- function(fn,
                                      mesh = aedes::aedes_neuropil_mesh,
                                      chunksize = dist_kde_chunksize,
                                      cl = NULL) {
  xyz <- nat::xyzmatrix(fn$pt_position)
  chunks <- nat.utils::make_chunks(seq_len(nrow(xyz)), chunksize = chunksize)
  dist <- unlist(pbapply::pblapply(
    chunks,
    function(i) {
      nat::pointsinside(xyz[i, , drop = FALSE], surf = mesh, rval = "dist")
    },
    cl = cl
  ), use.names = FALSE)
  fn %>%
    mutate(
      dist_npil_nm = dist,
      dist_npil_um = dist / 1000,
      npil_side = case_when(
        .data$dist_npil_nm > 0 ~ "inside",
        .data$dist_npil_nm < 0 ~ "outside",
        TRUE ~ "surface"
      )
    ) %>%
    mutate(across(ends_with("position"), ~ nat::xyzmatrix2str(.x)))
}

fnd <- cached("nucleus_dist", function() {
  fn <- with_aedes(fafbseg::flywire_nuclei(rawcoords = FALSE))
  nucleus_neuropil_distance(fn, mesh = mesh, chunksize = dist_kde_chunksize,
                            cl = NULL)
})

message("nucleus neuropil-distance rows: ", nrow(fnd))

dist_um <- fnd$dist_npil_um
dist_um <- dist_um[is.finite(dist_um)]
dist_um <- dist_um[dist_um >= dist_kde_support[1] & dist_um <= dist_kde_support[2]]

kde <- stats::density(
  dist_um,
  from = dist_kde_support[1], to = dist_kde_support[2],
  n = dist_kde_n
)

# Mix KDE with a flat uniform background so density is never zero (real
# central-brain neurons sit 0-3 um inside the neuropil; pure-KDE would
# under-weight them in the right tail).
uniform_density <- 1 / diff(dist_kde_support)
y_mixed <- (1 - dist_uniform_eps) * kde$y + dist_uniform_eps * uniform_density
y_max   <- max(y_mixed)

dist_npil_density <- list(
  x = kde$x,                       # um, grid
  y = y_mixed,                     # mixed density (KDE + uniform background)
  y_max = y_max,
  support = dist_kde_support,      # um, [min, max]
  uniform_density = uniform_density,
  uniform_eps = dist_uniform_eps,
  n = length(dist_um)
)

message(sprintf("dist_npil KDE built from %d nuclei (support %.0f..%.0f um, eps=%g)",
                length(dist_um), dist_kde_support[1], dist_kde_support[2],
                dist_uniform_eps))

# ---------------------------------------------------------------------------
# 10. Save
# ---------------------------------------------------------------------------

aedes_soma_l2_stats <- list(
  feature_names      = shape_feat_names,
  feature_transforms = list(
    log_area_nm2   = "log1p(area_nm2)",
    log_size_nm3   = "log1p(size_nm3)",
    log_max_dt_nm  = "log1p(max_dt_nm)",
    log_mean_dt_nm = "log1p(mean_dt_nm)",
    roundness      = "pca_val_2 / pca_val_0"
  ),
  positive_mean       = positive_mean,
  positive_cov        = positive_cov,
  positive_quantiles  = positive_quantiles,
  dist_npil_density   = dist_npil_density,
  dist_penalty_weight = 1.0,
  n_positive          = sum(train$label == 1L),
  n_negative          = sum(train$label == 0L),
  training_set = list(
    positives_source      = "KCs with FT soma_xyz + nucleus_id match",
    hard_negatives_source = bad_scene_url,
    soft_negatives_source = "random L2 chunks from sensory + ascending_neuron",
    soft_neg_sample_per_neuron = neg_sample_per_neuron,
    dist_prior_source     = "empirical KDE over flywire_nuclei dist_npil_um + uniform background"
  ),
  build_date = Sys.Date()
)

usethis::use_data(aedes_soma_l2_stats, overwrite = TRUE)
message("saved data/aedes_soma_l2_stats.rda")
