## Regenerate data/aedes_neuropil_mesh.rda
##
## The mesh comes from segment 3 ("neuropil") of the precomputed source
##   https://flyem.mrc-lmb.cam.ac.uk/flyconnectome/aedes_brain/
## referenced (as the layer named "aedes_neuropil") in the neuroglancer scene
##   https://spelunker.cave-explorer.org/#!middleauth+https://global.daf-apis.com/nglstate/api/v1/5351862369779712
##
## The endpoint serves @type neuroglancer_legacy_mesh; cloudvolume's normal
## image-volume reader fails ("KeyError: 'scales'"), so we use
## malevnc:::read_neuroglancer_mesh() to decode the fragment directly.
##
## Run from the package root:
##   Rscript data-raw/aedes_neuropil_mesh.R

mesh_root <- "https://flyem.mrc-lmb.cam.ac.uk/flyconnectome/aedes_brain"
segment   <- 3L

# The manifest at "<seg>:0" lists fragment file names; for this dataset segment
# 3 is a single fragment also named "3".
manifest <- jsonlite::fromJSON(paste0(mesh_root, "/", segment, ":0"))
stopifnot(length(manifest$fragments) >= 1)

frags <- lapply(
  manifest$fragments,
  function(f) malevnc:::read_neuroglancer_mesh(paste0(mesh_root, "/", f))
)

if (length(frags) == 1L) {
  aedes_neuropil_mesh <- frags[[1]]
} else {
  # concatenate vertex/face blocks with index offsets
  verts <- do.call(cbind, lapply(frags, function(m) m$vb[1:3, , drop = FALSE]))
  offs  <- c(0, cumsum(vapply(frags, function(m) ncol(m$vb), integer(1))))
  faces <- do.call(cbind, lapply(seq_along(frags),
                                 function(i) frags[[i]]$it + offs[i]))
  aedes_neuropil_mesh <- rgl::tmesh3d(vertices = verts, indices = faces,
                                      homogeneous = FALSE)
}

# coordinates are nm
usethis::use_data(aedes_neuropil_mesh, overwrite = TRUE)
