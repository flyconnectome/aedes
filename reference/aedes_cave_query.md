# Query Aedes tables in the CAVE annotation system

Query Aedes tables in the CAVE annotation system

## Usage

``` r
aedes_cave_query(
  table,
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
  ...
)
```

## Arguments

- table:

  Table name.

- datastack_name:

  Optional datastack name. Defaults to active Aedes datastack.

- version:

  An optional CAVE materialisation version number. See details and
  examples.

- timestamp:

  An optional timestamp as a string or POSIXct, interpreted as UTC when
  no timezone is specified.

- live:

  Whether to use live query mode, which updates any root ids to their
  current value (or to another `timestamp` when provided). Values of
  `TRUE` or `1` select CAVE's *Live* mode, while `2` selects `Live live`
  mode which gives access even to annotations that are not part of a
  materialisation version. See section **Live and Live Live queries**
  for details.

- timetravel:

  Whether to interpret `version`/`timestamp` as a defined point in the
  past to which the very *latest* annotations will be sent back in time,
  recalculating root ids as necessary.

- filter_in_dict, filter_out_dict, filter_regex_dict:

  Optional arguments consisting of key value lists that restrict the
  returned rows (keeping only matches or filtering out matches).
  Commonly used to selected rows for specific neurons. See examples and
  CAVE documentation for details.

- select_columns:

  Either a character vector naming columns or a python dict (required if
  the query involves multiple tables).

- offset:

  a 0-indexed row number, allows you to page through long results (but
  see section **CAVE Row Limits** for some caveats)

- limit:

  whether to limit the number of rows per query (`NULL` implies no
  client side limit but there is typically a server side limit of
  500,000 rows).

- fetch_all_rows:

  Whether to fetch all rows of a query that exceeds limit (default
  `FALSE`). See section **CAVE Row Limits** for some caveats.

- ...:

  Additional arguments passed to
  [`fafbseg::flywire_cave_query()`](https://rdrr.io/pkg/fafbseg/man/flywire_cave_query.html).

## Value

A data.frame.

## Examples

``` r
if (FALSE) { # \dontrun{
aedes_cave_query(table = "aedes_main", limit = 1)
} # }
```
