# Package index

## Dataset setup

Point fafbseg / cave at the Aedes segmentation.

- [`choose_aedes()`](choose_aedes.md) [`with_aedes()`](choose_aedes.md)
  : Choose or temporarily use the Aedes autosegmentation
- [`register_aedes_coconat()`](register_aedes_coconat.md) : Register
  Aedes dataset for coconatfly

## Metadata and id resolution

Query the FlyTable annotations and pick a materialisation.

- [`aedes_meta()`](aedes_meta.md) [`aedes_ids()`](aedes_meta.md) :
  Return metadata about Aedes neurons from FlyTable
- [`aedes_get_version()`](aedes_get_version.md) : Resolve Aedes
  materialisation version and timestamp
- [`aedes_set_version()`](aedes_set_version.md) : Set default version
  selection for Aedes helpers

## Coordinates

Convert between raw and nm, query supervoxels, mirror through the brain.

- [`aedes_voxdims()`](aedes_voxdims.md)
  [`aedes_nm2raw()`](aedes_voxdims.md)
  [`aedes_raw2nm()`](aedes_voxdims.md) : Handle raw and nm calibrated
  Aedes coordinates
- [`aedes_xyz2id()`](aedes_xyz2id.md) : Find Aedes root or supervoxel
  (leaf) IDs for XYZ locations
- [`aedes_mirror()`](aedes_mirror.md) : Mirror Aedes neurons or points
  to the opposite side of the brain
- [`aedes_point_side()`](aedes_point_side.md) : Predict the L/R side of
  points in Aedes space

## Reading neurons

Pull skeletons and pick annotation points.

- [`read_aedes_neurons()`](read_aedes_neurons.md) : Read Aedes L2
  skeletons
- [`aedes_soma_position()`](aedes_soma_position.md) : Look up the soma
  position for one or more Aedes neurons
- [`aedes_soma_side()`](aedes_soma_side.md) : Predict the L/R side of
  Aedes neurons
- [`aedes_key_point()`](aedes_key_point.md) : Find a good "key" point on
  a neuron to associate with annotations

## Editing the aedes_main table

Bulk add or update FlyTable rows.

- [`aedes_add_neurons()`](aedes_add_neurons.md) : Add new neurons (and
  update existing ones) in the aedes_main flytable

## Low level CAVE access

- [`aedes_cave_client()`](aedes_cave_client.md) : Low level access to
  Aedes CAVE annotation infrastructure
- [`aedes_cave_query()`](aedes_cave_query.md) : Query Aedes tables in
  the CAVE annotation system

## Datasets

- [`aedes_neuropil_mesh`](aedes_neuropil_mesh.md) : Mesh of the Aedes
  neuropil
- [`aedes_soma_l2_stats`](aedes_soma_l2_stats.md) : Population
  L2-attribute model for soma identification
