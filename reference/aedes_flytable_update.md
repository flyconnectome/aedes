# Update ids in aedes_main table manually

Update ids in aedes_main table manually

## Usage

``` r
aedes_flytable_update(
  update.serial_ids = TRUE,
  update_dups = TRUE,
  dry_run = FALSE
)
```

## Arguments

- update.serial_ids:

  Whether to update the serial_id column uniquely defining each row

- update_dups:

  Whether to update rows with "duplicate" status (now the default) and
  also set the root_duplicated column.

- dry_run:

  Whether to show what would happen rather than doing it.

## Details

This is now part of the scripted updates on flyem but even in future it
may occasionally be useful to trigger this manually.

Expert use only: there is a scheduled job that updates root IDs on
FlyTable every 30 minutes, so this function should normally not be
needed.

The root_duplicated column will only be ticked for root_ids when there
is more than one entry *after* setting aside any rows with
status=duplicate.
