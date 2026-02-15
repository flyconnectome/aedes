# Resolve Aedes materialisation version and timestamp

Resolve Aedes materialisation version and timestamp

## Usage

``` r
aedes_get_version(
  which = getOption("aedes.version", default = "latest"),
  version = NULL,
  timestamp = NULL
)
```

## Arguments

- which:

  Version selector; defaults to `getOption("aedes.version")`.

- version:

  Optional explicit materialisation version.

- timestamp:

  Optional explicit timestamp.

## Value

A list with `version` and `timestamp`.
