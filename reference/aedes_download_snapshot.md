# Download or publish Aedes synapse snapshots

`aedes_download_snapshot()` downloads the newest published synapse
snapshot into your snapshot folder and selects it with
[`aedes_use_snapshot()`](aedes_use_snapshot.md). The first download
fetches the static data (about 1.7 GB) and a full snapshot (about 0.6
GB); later ones usually just fetch a small delta.

`aedes_publish_snapshot()` is for whoever maintains the snapshots: it
makes the newest snapshot in `root` available for download from a folder
served over https.

## Usage

``` r
aedes_download_snapshot(
  url = getOption("aedes.snapshot_url"),
  root = aedes_snapshot_root(create = TRUE),
  set = TRUE
)

aedes_publish_snapshot(dest, root = aedes_snapshot_root(), snapshot = "latest")
```

## Arguments

- url:

  The address of the published snapshots (the folder or its
  `manifest.json`). Defaults to the `aedes.snapshot_url` option.

- root:

  The local snapshot folder. Defaults to
  [`aedes_snapshot_root()`](aedes_snapshot_root.md).

- set:

  Whether to select a snapshot with
  [`aedes_use_snapshot()`](aedes_use_snapshot.md) afterwards.

- dest:

  The folder to publish into.

- snapshot:

  The snapshot to publish; `"latest"` (the default) for the newest one
  in `root`.

## Value

`aedes_download_snapshot()`: the tags downloaded, invisibly.
`aedes_publish_snapshot()`: the manifest, invisibly.

## Details

Snapshots are published with a `manifest.json` that lists every file
with its size and md5. A download only fetches snapshots that are not
already in `root` (snapshots never change once made), checks each file's
md5 and places a snapshot's `meta.json` last, so an interrupted download
is never mistaken for a snapshot; just run it again. Downloads use the
`curl` command line tool and resume partial files.

Publishing hard links the files into `dest` when it is on the same
filesystem as `root` (otherwise they are copied), so it takes no extra
space. It includes the static data, the newest snapshot and, when that
is a delta, its full base. `manifest.json` is written last. Files that
are no longer listed are removed one publish later, so that a client
that has just read the previous manifest can still finish.

## See also

[`aedes_use_snapshot()`](aedes_use_snapshot.md),
[`aedes_update_snapshot()`](aedes_update_snapshot.md),
[`aedes_build_snapshot()`](aedes_build_snapshot.md)

## Examples

``` r
if (FALSE) { # \dontrun{
# the url is given to you by the snapshot maintainer
options(aedes.snapshot_url = "https://...")
aedes_download_snapshot()
} # }
```
