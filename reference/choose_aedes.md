# Choose or temporarily use the Aedes autosegmentation

Choose or temporarily use the Aedes autosegmentation

## Usage

``` r
choose_aedes(set = TRUE, url = NULL, datastack_name = NULL)

with_aedes(expr, url = NULL, datastack_name = NULL)
```

## Arguments

- set:

  Whether to set Aedes as default for `fafbseg` flywire functions.

- url:

  Neuroglancer scene URL. Defaults to `aedes_scene()`.

- datastack_name:

  Optional CAVE datastack name; inferred from `url` if `NULL`.

- expr:

  Expression to evaluate while Aedes is the active dataset.

## Value

A named list of option values (or previous options when `set=TRUE`).
