#' Query Aedes tables in the CAVE annotation system
#'
#' @param table Table name.
#' @param datastack_name Optional datastack name. Defaults to active Aedes datastack.
#' @param ... Additional arguments passed to [fafbseg::flywire_cave_query()].
#' @inheritParams fafbseg::flywire_cave_query
#' @return A data.frame.
#' @export
#'
#' @examples
#' \dontrun{
#' aedes_cave_query(table = "aedes_main", limit = 1)
#' }
aedes_cave_query <- function(table,
                             datastack_name = NULL,
                             version = NULL,
                             timestamp = NULL,
                             live = is.null(version),
                             timetravel = FALSE,
                             filter_in_dict = NULL,
                             filter_out_dict = NULL,
                             filter_regex_dict = NULL,
                             select_columns = NULL,
                             offset = 0L,
                             limit = NULL,
                             fetch_all_rows = FALSE,
                             ...) {
  if (is.null(datastack_name)) {
    datastack_name <- choose_aedes(set = FALSE)[["fafbseg.cave.datastack_name"]]
  }

  fafbseg::flywire_cave_query(
    table = table,
    datastack_name = datastack_name,
    version = version,
    timestamp = timestamp,
    live = live,
    timetravel = timetravel,
    filter_in_dict = filter_in_dict,
    filter_out_dict = filter_out_dict,
    filter_regex_dict = filter_regex_dict,
    select_columns = select_columns,
    offset = offset,
    limit = limit,
    fetch_all_rows = fetch_all_rows,
    ...
  )
}

#' Low level access to Aedes CAVE annotation infrastructure
#'
#' @return A reticulate object wrapping the Python CAVEclient.
#' @export
#'
#' @examples
#' \dontrun{
#' fac <- aedes_cave_client()
#' fac$annotation$get_tables()
#' }
aedes_cave_client <- function() {
  with_aedes(fafbseg::flywire_cave_client())
}
