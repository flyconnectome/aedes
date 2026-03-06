# Animate Aedes proofreading edits as a gif

Animate Aedes proofreading edits as a gif

## Usage

``` r
aedes_edit_movie(
  dat,
  name = "aedes_frames",
  fps = 10,
  duration = 30,
  size = 1.5,
  width = 800,
  height = 600,
  rotate = FALSE,
  bg = "white",
  gif_file = paste0(name, ".gif")
)
```

## Arguments

- dat:

  A data frame of edit operations with columns `timestamp`,
  `user_affiliation`, `source_x`, `source_y`, `source_z`.

- name:

  Stem used for the temporary frame directory and default gif filename.

- fps:

  Frames per second (default 10).

- duration:

  Duration in seconds (default 30).

- size:

  Point size for
  [`rgl::points3d()`](https://dmurdoch.github.io/rgl/dev/reference/primitives.html).

- width, height:

  Output gif dimensions in pixels.

- rotate:

  If `TRUE`, slowly rotate the camera (half turn) over the duration. If
  `FALSE` (default), use a fixed frontal view.

- bg:

  Background colour (default `"white"`).

- gif_file:

  Output gif path. Defaults to `paste0(name, ".gif")`.

## Value

The output gif path, invisibly.

## Examples

``` r
if (FALSE) { # \dontrun{
# Fetch edit operations and add user metadata
ops <- aedes:::aedes_all_operations()
ops <- aedes:::add_operation_centroids(ops)
user_info <- googlesheets4::read_sheet(
  "https://docs.google.com/spreadsheets/d/1W0CLjIvgX9rl4ttqgjI3xr3zlL_hA86ZRW0-3-CGQTU/"
)
edit_dat <- ops %>% dplyr::left_join(user_info, by = c("user" = "user_id"))

# All edits with rotation
aedes_edit_movie(edit_dat, name = "all_edits", rotate = TRUE)

# Human edits only
edit_dat %>%
  dplyr::filter(user_affiliation != "auto") %>%
  aedes_edit_movie(name = "human_edits")
} # }
```
