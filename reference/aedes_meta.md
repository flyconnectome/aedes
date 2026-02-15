# Return metadata about Aedes neurons from FlyTable

Return metadata about Aedes neurons from FlyTable

## Usage

``` r
aedes_meta(
  ids = NULL,
  ignore.case = FALSE,
  fixed = FALSE,
  version = NULL,
  timestamp = NULL,
  unique = FALSE
)

aedes_ids(
  ids,
  ignore.case = FALSE,
  fixed = FALSE,
  unique = FALSE,
  version = NULL,
  timestamp = NULL
)
```

## Arguments

- ids:

  Root IDs (character/int64) or a query string like `"class:ALPN"`.

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

## Value

For `aedes_meta()`, a data.frame of metadata. For `aedes_ids()`, a
vector of root IDs.

## Details

When `version` or `timestamp` are specified, root ids in the returned
data frame will be mapped to the corresponding timepoint using the
`supervoxel_id` column. When no version/timestamp is specified then ids
will be simply as returned by the flytable (which updates them every
half hour). If you want to be sure that ids match the most up to date
state of the segmentation possible then you can ask for
`timestamp='now'`.

## Examples

``` r
if (FALSE) { # \dontrun{
aedes_meta("class:ALPN")
aedes_ids("class:ALPN")

aedes_ids("class:ALPN", timestamp='now')
aedes_ids("class:ALPN", version='latest')
} # }
```
