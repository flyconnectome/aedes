# Low level access to Aedes CAVE annotation infrastructure

Low level access to Aedes CAVE annotation infrastructure

## Usage

``` r
aedes_cave_client()
```

## Value

A reticulate object wrapping the Python CAVEclient.

## Examples

``` r
if (FALSE) { # \dontrun{
acc <- aedes_cave_client()
#
acc$annotation$get_tables()
# summary of materialisations
acc$materialize$get_versions_metadata() %>% dplyr::bind_rows()
} # }
```
