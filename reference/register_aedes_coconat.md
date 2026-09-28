# Register Aedes dataset for coconatfly

Register `aedes` dataset adapters for use with
[coconatfly](https://natverse.org/coconatfly).

## Usage

``` r
register_aedes_coconat(showerror = TRUE)
```

## Arguments

- showerror:

  Logical; when `FALSE`, return invisibly if dependencies are missing.

## Value

Invisible `NULL`.

## Details

The aedes dataset is continually evolving. You three two main choices
for how to handle this.

1.  use a specific numeric version (aka materialisation) of the
    segmentation.

2.  use the latest materialisation version (`version='latest'`)

3.  map ids to the current time (`version='now'`)

Option 2 is the default since this can make queries somewhat faster and
stable but note that 'latest' can be several days old.

Metadata returned for aedes neurons includes a `pgroup` column from
[`aedes_predict_group()`](aedes_predict_group.md), which can be used to
group partner neurons when clustering by connectivity, e.g.
`cf_cosine_plot(ids, group = "pgroup")`. See
[`vignette("connectivity-clustering")`](../articles/connectivity-clustering.md)
for a worked example.

## Examples

``` r
if (FALSE) { # \dontrun{
register_aedes_coconat()
cf_meta(cf_ids(aedes="/class:MBON.*"))
aedes_set_version('now')
cf_meta(cf_ids(aedes="/class:MBON.*"))

# cluster a group of neurons by connectivity, grouping partner neurons by
# their curated group (partners without one are dropped) ...
cf_cosine_plot(cf_ids(aedes = "group:36155"), group = "group",
  labRow = "{side}_{serial_id}")
# ... or by predicted group (type, then group, then nblast cluster), so that
# far fewer partners are lost
cf_cosine_plot(cf_ids(aedes = "group:36155"), group = "pgroup",
  labRow = "{side}_{serial_id}")
} # }
```
