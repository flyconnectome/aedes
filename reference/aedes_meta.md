# Return metadata about Aedes neurons from FlyTable

By default `aedes_meta()` and `aedes_ids()` tell you exactly what is in
FlyTable: its rows and root ids as stored there. Unlike most aedes
functions they do not follow the `aedes.version` option (see
[`aedes_set_version()`](aedes_set_version.md)). You can still time
travel by giving a `version` (e.g. `"latest"`) or a `timestamp` (e.g.
`"now"`), which maps the root ids to that time.

## Usage

``` r
aedes_meta(
  ids = NULL,
  ignore.case = FALSE,
  fixed = FALSE,
  version = NULL,
  timestamp = NULL,
  unique = FALSE,
  translate_ids = NA,
  expiry = 0,
  refresh = FALSE,
  ...
)

aedes_ids(
  ids,
  ignore.case = FALSE,
  fixed = FALSE,
  unique = FALSE,
  version = NULL,
  timestamp = NULL,
  expiry = 0,
  refresh = FALSE,
  ...
)
```

## Arguments

- ids:

  Root IDs (character/int64), a query string like `"class:ALPN"`, a
  single string of comma/space-separated ids (`"id1, id2, id3"`) or a
  neuroglancer URL (including shortened state URLs), from which the
  visible segments are used.

- ignore.case:

  For query strings, whether to ignore case.

- fixed:

  For query strings, whether to treat queries as fixed strings rather
  than regular expressions (default FALSE).

- version:

  Optional CAVE materialisation version.

- timestamp:

  Optional CAVE timestamp.

- unique:

  Whether to drop duplicate `root_id` rows (with duplicates attached as
  an attribute).

- translate_ids:

  Whether to bring explicitly supplied `ids` forward to the requested
  `version`/`timestamp` before matching (see Details). `NA` (the
  default) decides automatically.

- expiry:

  Cache expiry in seconds passed to
  [`fafbseg::cam_meta()`](https://rdrr.io/pkg/fafbseg/man/cam_meta.html).
  Defaults to `0`, always checking for updates so you see the latest
  metadata; set a positive value to trust the cache within that window,
  or `Inf` to use the on-disk cache without checking.

- refresh:

  Logical passed to
  [`fafbseg::cam_meta()`](https://rdrr.io/pkg/fafbseg/man/cam_meta.html);
  if `TRUE` force a complete re-download of the table, ignoring any
  cache.

- ...:

  Additional arguments passed to
  [`fafbseg::cam_meta()`](https://rdrr.io/pkg/fafbseg/man/cam_meta.html).

## Value

For `aedes_meta()`, a data.frame of metadata. For `aedes_ids()`, a
vector of root IDs.

## Details

When `version` or `timestamp` are specified, root ids in the returned
data frame will be mapped to the corresponding timepoint using the
`supervoxel_id` column. When no version/timestamp is specified then ids
will be simply as returned by the flytable (which updates them every
half hour, so they can lag recent edits). If you want to be sure that
ids match the most up to date state of the segmentation possible then
you can ask for `timestamp='now'`.

For a **query string** the match happens against that mapped table, so
no further work is needed. For **explicit root `ids`** the join is by
`root_id`, so ids that are stale relative to the requested timepoint
would silently fail to match. `translate_ids` guards against this by
bringing the supplied ids forward with
[`fafbseg::flywire_latestid()`](https://rdrr.io/pkg/fafbseg/man/flywire_latestid.html)
first. The default (`NA`) turns this on only when it is both needed and
meaningful: explicit ids are supplied *and* a `version`/`timestamp` is
given. With no version/timestamp nothing is translated, since the
flytable is simply at the state of its last half-hourly update.

## Examples

``` r
if (FALSE) { # \dontrun{
aedes_meta("class:ALPN")
aedes_ids("class:ALPN")

aedes_ids("class:ALPN", timestamp='now')
aedes_ids("class:ALPN", version='latest')
} # }
```
