# Update root_ids and supervoxel_ids from point information as necessary

Update root_ids and supervoxel_ids from point information as necessary

## Usage

``` r
aedes_sequential_update(df)
```

## Arguments

- df:

  A dataframe containing columns root_id, supervoxel_id, point_xyz

## Value

A new dataframe with updated ids

## Details

Note that point information will only be used if supervoxel information
is missing. Therefore it is essential to delete supervoxel_id for any
rows in which the point_xyz is changed.
