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

## Examples

``` r
if (FALSE) { # \dontrun{
register_aedes_coconat()

aedes_set_version('now')
ades
} # }
```
