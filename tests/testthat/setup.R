# no automatic checks for new snapshots, except where a test turns them on
withr::local_options(aedes.snapshot_check_hours = Inf,
                     .local_envir = testthat::teardown_env())
