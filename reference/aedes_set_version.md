# Set default version selection for Aedes helpers

Set default version selection for Aedes helpers

## Usage

``` r
aedes_set_version(which = c("now", "latest"))
```

## Arguments

- which:

  One of `"now"` or `"latest"`, or a materialisation version (number) or
  timestamp (`POSIXct`).

## Details

The package sets `"now"` when it loads, unless the `aedes.version`
option is already set (e.g. in your `.Rprofile`).

`"now"` is the time of the outermost call to an aedes, coconat or
coconatfly function, so that all the steps of e.g.
`cf_cosine_plot(cf_ids(aedes = "/type:MBON.+"))` see the same time. To
use one time across several calls, set a fixed time, e.g.
`aedes_set_version(Sys.time())`.
