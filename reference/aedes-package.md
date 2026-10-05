# aedes: Support Access to the Aedes Connectome Dataset

Access to the in progress Aedes aegypti dataset. Organised as a thin
wrapper around the fafbseg package. Includes support for adding aedes as
a dataset supported by coconatfly.

## Package Options

- `aedes.version` Default materialisation selector used by
  [`aedes_get_version`](aedes_get_version.md) (and, transitively,
  everything that pins a timestamp –
  [`aedes_partner_summary`](aedes_partner_summary.md),
  [`aedes_use_snapshot`](aedes_use_snapshot.md) and the coconatfly
  functions). [`aedes_meta`](aedes_meta.md) and
  [`aedes_ids`](aedes_meta.md) do not use it: by default they return
  exactly what is in FlyTable. Accepts `"now"` (set when the package
  loads, unless already set), `"latest"`, an integer materialisation
  version or an explicit timestamp. Set with
  [`aedes_set_version`](aedes_set_version.md) or
  `options(aedes.version = ...)`, e.g. in your `.Rprofile`.

- `aedes.initials` Curator initials used to auto-fill the single-string
  `initials` column and, when `annotator = TRUE` / `proofreader = TRUE`,
  appended to the corresponding multi-select column. Consumed by
  [`aedes_add_neurons`](aedes_add_neurons.md),
  [`aedes_set_meta`](aedes_set_meta.md) and
  [`aedes_set_group`](aedes_set_group.md). Set once per session with
  `options(aedes.initials = "XY")`.

## See also

Useful links:

- <https://github.com/flyconnectome/aedes>

- <https://flyconnectome.github.io/aedes/>

- Report bugs at <https://github.com/flyconnectome/aedes/issues>

## Author

**Maintainer**: Gregory Jefferis <jefferis@gmail.com>
([ORCID](https://orcid.org/0000-0002-0587-9355))

Authors:

- Gregory Jefferis <jefferis@gmail.com>
  ([ORCID](https://orcid.org/0000-0002-0587-9355))
