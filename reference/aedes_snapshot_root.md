# Folder for local Aedes synapse snapshots

Returns the folder that the synapse snapshot functions use when no
`root` is given.

## Usage

``` r
aedes_snapshot_root(create = FALSE)
```

## Arguments

- create:

  Whether to create the folder (and any missing parent folders) if it
  does not exist yet.

## Value

The path to the folder, with `~` expanded.

## Details

The folder is the first of:

1.  the `aedes.synapse_snapshot_root` option, if set;

2.  `~/projects/2025aedes/data/syn_snapshot`, if it holds a snapshot
    (`static.parquet`);

3.  `syn_snapshot` in the user data folder for the package (see
    [`rappdirs::user_data_dir()`](https://rappdirs.r-lib.org/reference/user_data_dir.html)).

## See also

[`aedes_use_snapshot()`](aedes_use_snapshot.md)

## Examples

``` r
aedes_snapshot_root()
#> [1] "/home/runner/.local/share/rpkg-aedes/syn_snapshot"
```
