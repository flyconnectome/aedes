#' Predict the group of aedes neurons using type or group information
#'
#' @description Returns a numeric group id for each neuron, preferring its cell
#'   type, then its curated `group`, then its NBLAST cluster, and finally its
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
#'   has the form `CNNNNN` (where `NNNNN` is the smallest `serial_id` in the
#'   cluster); the leading `C` is dropped. All other `nblast_group` values are
#'   ignored, so a cluster can be struck out by prefixing it with `X` (e.g.
#'   `XC12345`) without deleting it.
#'   * neurons with none of these fall back to their own `serial_id`.
#'
#' @param x A data.frame with `type`, `group`, `nblast_group` and `serial_id`
#'   columns, such as
#'   returned by [aedes_meta()] or a partner table from
#'   [coconatfly::cf_partners()] / [coconatfly::multi_connection_table()]
#'   (where these columns describe the partner neurons). Alternatively neuron
#'   ids in any form understood by [aedes_meta()].
#' @param badtypes Values of the type column (after removing any trailing `?`)
#'   that are too broad or uninformative to define a group.
#'
#' @returns A numeric vector of group ids with one element per row of `x`.
#' @seealso [aedes_set_group()], [aedes_meta()]
#' @export
#' @examples
#' \dontrun{
#' library(coconatfly)
#' x <- multi_connection_table(cf_ids(aedes = "/type:MBON.+"),
#'   partners = c("in", "out"), threshold = 5, group = FALSE)
#' x$pgroup <- aedes_predict_group(x)
#' cf_cosine_plot(x, group = "pgroup")
#' }
aedes_predict_group <- function(x,
                                badtypes = c(NA, "", "undefined", "KCx", "LHN")) {
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
           # only CNNNNN clusters count; anything else (e.g. X-prefixed
           # struck-out clusters or legacy plain ids) is ignored
           .nblast = as.numeric(ifelse(grepl("^C[0-9]+$", .data$nblast_group),
                                       sub("^C", "", .data$nblast_group),
                                       NA_character_)),
           .type = sub("\\?$", "", .data$type),
           .type = ifelse(.data$.type %in% badtypes, NA_character_, .data$.type)) %>%
    dplyr::group_by(.data$.type) %>%
    mutate(.tgroup = if (is.na(.data$.type[1])) NA_real_ else min(.data$.sid)) %>%
    dplyr::ungroup() %>%
    mutate(.pg = dplyr::coalesce(.data$.tgroup, .data$.grp, .data$.nblast,
                                 .data$.sid)) %>%
    dplyr::pull(.data$.pg)
}
