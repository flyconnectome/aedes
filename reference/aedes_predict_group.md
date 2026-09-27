# Predict the group of aedes neurons using type or group information

Returns a numeric group id for each neuron, preferring its cell type,
then its curated `group`, and finally its own `serial_id`. This is
intended for grouping partner neurons in connectivity clustering, e.g.
with
[`coconatfly::cf_cosine_plot()`](https://natverse.org/coconatfly/reference/cf_cosine_plot.html).

## Usage

``` r
aedes_predict_group(x, badtypes = c(NA, "", "undefined", "KCx", "LHN"))
```

## Arguments

- x:

  A data.frame with `type`, `group` and `serial_id` columns, such as
  returned by [`aedes_meta()`](aedes_meta.md) or a partner table from
  [`coconatfly::cf_partners()`](https://natverse.org/coconatfly/reference/cf_partners.html)
  /
  [`coconatfly::multi_connection_table()`](https://natverse.org/coconatfly/reference/cf_cosine_plot.html)
  (where these columns describe the partner neurons). Alternatively
  neuron ids in any form understood by [`aedes_meta()`](aedes_meta.md).

- badtypes:

  Values of the type column (after removing any trailing `?`) that are
  too broad or uninformative to define a group.

## Value

A numeric vector of group ids with one element per row of `x`.

## Details

All returned ids are `serial_id` values, so they share one namespace:

- typed neurons get the smallest `serial_id` among the rows in `x` with
  the same type (so type-derived ids depend on which rows are supplied).
  A trailing `?` is removed before grouping, so e.g. `KC4?` joins `KC4`.
  Types listed in `badtypes` are ignored.

- untyped neurons use their `group` column (itself the smallest
  `serial_id` of the group's founding members, see
  [`aedes_set_group()`](aedes_set_group.md)). A `group` of `0` is
  treated as ungrouped.

- neurons with neither fall back to their own `serial_id`.

## See also

[`aedes_set_group()`](aedes_set_group.md),
[`aedes_meta()`](aedes_meta.md)

## Examples

``` r
if (FALSE) { # \dontrun{
library(coconatfly)
x <- multi_connection_table(cf_ids(aedes = "/type:MBON.+"),
  partners = c("in", "out"), threshold = 5, group = FALSE)
x$pgroup <- aedes_predict_group(x)
cf_cosine_plot(x, group = "pgroup")
} # }
```
