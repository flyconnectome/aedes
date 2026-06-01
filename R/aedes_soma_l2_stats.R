#' Population L2-attribute model for soma identification
#'
#' Statistics learned from a KC-based training set, used by
#' [aedes_soma_position()] (when the cascade falls through to `"l2+mesh"` /
#' `"l2"` / `"mesh"`) to score how soma-like each L2 chunk of a neuron is.
#'
#' The score combines two terms:
#' \describe{
#'   \item{shape}{Squared Mahalanobis distance of the L2 chunk's five shape
#'     features (`log_area_nm2`, `log_size_nm3`, `log_max_dt_nm`,
#'     `log_mean_dt_nm`, `roundness = pca_val_2 / pca_val_0`) versus the KC
#'     positive population (`positive_mean`, `positive_cov`). Smaller =
#'     closer to a typical KC soma.}
#'   \item{dist_npil penalty}{`-2 * log(f_hat(d_um) / max(f_hat))` where
#'     `f_hat` is the empirical KDE of signed neuropil distance over the full
#'     `flywire_nuclei()` population, mixed with a small uniform background so
#'     no value is hard-rejected (real central-brain neurons sit 0-3 um inside
#'     the neuropil). Weight controlled by `dist_penalty_weight`.}
#' }
#' Combined as `soma_score = mahal_shape + dist_penalty_weight * dist_penalty`
#' (lower = more soma-like).
#'
#' @format A `list` with elements:
#' \describe{
#'   \item{feature_names}{Character vector of the 5 shape features used in
#'     the Mahalanobis distance.}
#'   \item{feature_transforms}{Named list documenting the raw -> feature
#'     transforms (mostly `log1p`).}
#'   \item{positive_mean, positive_cov}{Mean vector and covariance matrix of
#'     the positive (KC) training set in feature space.}
#'   \item{positive_quantiles}{Per-feature P5..P95 quantiles for diagnostics.}
#'   \item{dist_npil_density}{List with `x` (um grid), `y` (mixed density),
#'     `y_max`, `support`, `uniform_density`, `uniform_eps`, `n` -- the KDE
#'     prior on signed neuropil distance.}
#'   \item{dist_penalty_weight}{Multiplier on the distance-penalty term.}
#'   \item{n_positive, n_negative}{Training set sizes.}
#'   \item{training_set}{Provenance of positives / negatives / distance prior.}
#'   \item{build_date}{Date the dataset was built.}
#' }
#'
#' @seealso [aedes_soma_position()]; `data-raw/aedes_soma_l2_stats.R` for the
#'   build script.
#' @name aedes_soma_l2_stats
#' @docType data
"aedes_soma_l2_stats"
