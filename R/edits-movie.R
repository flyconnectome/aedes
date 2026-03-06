#' Animate Aedes proofreading edits as a gif
#'
#' @importFrom graphics par plot.new plot.window rect text
#'
#' @param dat A data frame of edit operations with columns `timestamp`,
#'   `user_affiliation`, `source_x`, `source_y`, `source_z`.
#' @param name Stem used for the temporary frame directory and default gif
#'   filename.
#' @param fps Frames per second (default 10).
#' @param duration Duration in seconds (default 30).
#' @param size Point size for [rgl::points3d()].
#' @param width,height Output gif dimensions in pixels.
#' @param rotate If `TRUE`, slowly rotate the camera (half turn) over the
#'   duration. If `FALSE` (default), use a fixed frontal view.
#' @param bg Background colour (default `"white"`).
#' @param gif_file Output gif path. Defaults to `paste0(name, ".gif")`.
#' @return The output gif path, invisibly.
#' @keywords internal
#'
#' @examples
#' \dontrun{
#' # Fetch edit operations and add user metadata
#' ops <- aedes:::aedes_all_operations()
#' ops <- aedes:::add_operation_centroids(ops)
#' user_info <- googlesheets4::read_sheet(
#'   "https://docs.google.com/spreadsheets/d/1W0CLjIvgX9rl4ttqgjI3xr3zlL_hA86ZRW0-3-CGQTU/"
#' )
#' edit_dat <- ops %>% dplyr::left_join(user_info, by = c("user" = "user_id"))
#'
#' # All edits with rotation
#' aedes_edit_movie(edit_dat, name = "all_edits", rotate = TRUE)
#'
#' # Human edits only
#' edit_dat %>%
#'   dplyr::filter(user_affiliation != "auto") %>%
#'   aedes_edit_movie(name = "human_edits")
#' }
aedes_edit_movie <- function(dat, name = "aedes_frames", fps = 10,
                             duration = 30, size = 1.5, width = 800,
                             height = 600, rotate = FALSE,
                             bg = "white",
                             gif_file = paste0(name, ".gif")) {
  if (!requireNamespace("gifski", quietly = TRUE))
    stop("Package 'gifski' is required. Install with: install.packages('gifski')")

  dat <- dat %>%
    dplyr::arrange(.data$timestamp) %>%
    dplyr::mutate(
      col = dplyr::case_when(
        .data$user_affiliation == 'auto' ~ 'grey',
        grepl("Cambridge", .data$user_affiliation) ~ '#A3E1CD',
        grepl("Wei|Dacks", .data$user_affiliation) ~ '#A41034',
        TRUE ~ 'black'
      )
    )

  xyz <- aedes_raw2nm(cbind(dat$source_x, dat$source_y, dat$source_z))
  cols <- dat$col
  ts <- as.numeric(dat$timestamp)
  nframes <- fps * duration

  # Set up view from full data, capture camera state
  rgl::clear3d()
  rgl::bg3d(bg)
  rgl::points3d(xyz, col = cols, size = size)
  nat::nview3d('post')
  start_um <- rgl::par3d("userMatrix")
  start_zoom <- rgl::par3d("zoom")

  # Reset scene with locked bbox
  rgl::clear3d()
  rgl::bg3d(bg)
  rgl::par3d(userMatrix = start_um, zoom = start_zoom)
  bbox <- apply(xyz, 2, range, na.rm = TRUE)
  rgl::decorate3d(xlim = bbox[, 1], ylim = bbox[, 2], zlim = bbox[, 3],
                  box = FALSE, axes = FALSE)

  # Frame output (unique temp dir, cleaned up on exit)
  frames_dir <- tempfile(pattern = paste0(name, "_"))
  dir.create(frames_dir)
  on.exit(unlink(frames_dir, recursive = TRUE), add = TRUE)

  frame_breaks <- seq(min(ts), max(ts), length.out = nframes + 1)
  bins <- findInterval(ts, frame_breaks, rightmost.closed = TRUE)
  timestamps <- as.POSIXct(frame_breaks[-1], origin = "1970-01-01", tz = "UTC")

  for (i in seq_len(nframes)) {
    batch <- which(bins == i)
    if (length(batch) > 0)
      rgl::points3d(xyz[batch, , drop = FALSE], col = cols[batch], size = size)

    if (rotate) {
      angle <- pi * (i / nframes)
      rgl::par3d(userMatrix = rgl::rotate3d(start_um, angle, 0, 1, 0))
    }

    # Progress bar and date label
    frac <- i / nframes
    rgl::bgplot3d({
      par(mar = c(0, 0, 0, 0))
      plot.new()
      plot.window(xlim = c(0, 1), ylim = c(0, 1))
      rect(0.15, 0.02, 0.85, 0.045, col = "grey90", border = "grey50")
      rect(0.15, 0.02, 0.15 + 0.7 * frac, 0.045, col = "#A3E1CD", border = NA)
      text(0.5, 0.065, format(timestamps[i], "%Y-%m-%d"), cex = 1.2, col = "grey30")
    })

    rgl::snapshot3d(file.path(frames_dir, sprintf("frame%04d.png", i)))
    if (i %% 10 == 0) message(sprintf("Frame %d/%d", i, nframes))
  }

  pngs <- list.files(frames_dir, pattern = "\\.png$", full.names = TRUE)
  gifski::gifski(pngs, gif_file = gif_file,
                 delay = 1 / fps, width = width, height = height)
  message("Wrote: ", gif_file)
  invisible(gif_file)
}
