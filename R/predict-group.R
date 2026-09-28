#' Predict the group of aedes neurons using type or group information
#'
#' @description Returns a numeric group id for each neuron, preferring its cell
#'   type, then its curated `group`, then its NBLAST cluster and optionally its
#'   own `serial_id`. This is
#'   intended for grouping partner neurons in connectivity clustering, e.g. with
#'   [coconatfly::cf_cosine_plot()].
#'
#' @details All returned ids are `serial_id` values, so they share one
#'   namespace:
#'
#'   * typed neurons get the smallest `serial_id` among the rows in `x` with
#'   the same type (so type-derived ids depend on which rows are supplied).
#'   A trailing `?` is removed before grouping, so e.g. `KC4?` joins `KC4`.
#'   Types listed in `badtypes` are ignored.
#'   * untyped neurons use their `group` column (itself the smallest
#'   `serial_id` of the group's founding members, see [aedes_set_group()]).
#'   A `group` of `0` is treated as ungrouped.
#'   * neurons with no type or group use their `nblast_group` cluster when this
#'   has the form `CNNNNN` or `NNNNN` (where `NNNNN` is the smallest
#'   `serial_id` in the cluster); any leading `C` is dropped. Surrounding
#'   whitespace and a trailing `?` are ignored, so `" C12345?"` is read as
#'   `12345`. All other `nblast_group` values are ignored, so a cluster can be
#'   struck out by prefixing it with `X` (e.g. `XC12345`) without deleting it.
#'   * neurons with none of these get `NA`, so that coconatfly drops them as
#'   partners, just as it does for `group = "group"`. When `singletons = TRUE`
#'   they instead fall back to their own `serial_id`, i.e. each becomes a
#'   group of one.
#'
#'   Once [register_aedes_coconat()] has been called, coconatfly metadata for
#'   aedes neurons includes the result as a `pgroup` column, so you can use
#'   `group = "pgroup"` directly in coconatfly functions (see examples).
#'
#' @param x A data.frame with `type`, `group`, `nblast_group` and `serial_id`
#'   columns, such as
#'   returned by [aedes_meta()] or a partner table from
#'   [coconatfly::cf_partners()] / [coconatfly::multi_connection_table()]
#'   (where these columns describe the partner neurons). Alternatively neuron
#'   ids in any form understood by [aedes_meta()].
#' @param badtypes Values of the type column (after removing any trailing `?`)
#'   that are too broad or uninformative to define a group.
#' @param singletons Whether neurons without a type, group or NBLAST cluster
#'   should fall back to their own `serial_id` (default `FALSE`, returning
#'   `NA`). Singleton groups keep connectivity to individual partner neurons
#'   (like `group = FALSE`) but can never match across hemispheres, so they
#'   tend to pull left/right homologues apart.
#'
#' @returns A numeric vector of group ids with one element per row of `x`
#'   (`NA` for ungroupable neurons unless `singletons = TRUE`).
#' @seealso [aedes_set_group()], [aedes_meta()]
#' @export
#' @examples
#' \dontrun{
#' library(coconatfly)
#' x <- multi_connection_table(cf_ids(aedes = "/type:MBON.+"),
#'   partners = c("in", "out"), threshold = 5, group = FALSE)
#' x$pgroup <- aedes_predict_group(x)
#' cf_cosine_plot(x, group = "pgroup")
#'
#' # coconatfly metadata for aedes neurons already includes a pgroup column
#' cf_cosine_plot(cf_ids(aedes = "/type:MBON.+"), group = "pgroup")
#' }
aedes_predict_group <- function(x,
                                badtypes = c(NA, "", "undefined", "KCx", "LHN"),
                                singletons = FALSE) {
  if (!is.data.frame(x))
    x <- aedes_meta(x)
  missing_cols <- setdiff(c("type", "group", "nblast_group", "serial_id"),
                          colnames(x))
  if (length(missing_cols))
    stop("x is missing column(s): ", paste(missing_cols, collapse = ", "))

  x %>%
    mutate(.sid = as.numeric(.data$serial_id),
           # 0 is not a valid group id; coconatfly partner tables can report
           # ungrouped neurons as "0" rather than NA
           .grp = dplyr::na_if(as.numeric(.data$group), 0),
           .nblast = parse_nblast_group(.data$nblast_group),
           .type = sub("\\?$", "", .data$type),
           .type = ifelse(.data$.type %in% badtypes, NA_character_, .data$.type)) %>%
    dplyr::group_by(.data$.type) %>%
    mutate(.tgroup = if (is.na(.data$.type[1])) NA_real_ else min(.data$.sid)) %>%
    dplyr::ungroup() %>%
    mutate(.pg = dplyr::coalesce(.data$.tgroup, .data$.grp, .data$.nblast,
                                 if (isTRUE(singletons)) .data$.sid
                                 else NA_real_)) %>%
    dplyr::pull(.data$.pg)
}

# Parse nblast_group values of the form CNNNNN or NNNNN (NNNNN being a
# serial_id) into numbers. Surrounding whitespace and a trailing ? are removed
# first. Anything else (e.g. X-prefixed struck-out clusters) becomes NA.
parse_nblast_group <- function(x) {
  x <- sub("\\?$", "", trimws(as.character(x)))
  x <- trimws(x)
  ok <- grepl("^C?[0-9]+$", x)
  as.numeric(ifelse(ok, sub("^C", "", x), NA_character_))
}
