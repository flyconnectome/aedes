# Set default version selection for Aedes helpers

Set default version selection for Aedes helpers

## Usage

``` r
aedes_set_version(which = c("now", "latest"))
```

## Arguments

- which:

  One of `"now"` or `"latest"` (or explicit selector).

## Details

The package sets `"now"` when it loads, unless the `aedes.version`
option is already set (e.g. in your `.Rprofile`).
