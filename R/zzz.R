.onLoad <- function(libname, pkgname) {
  if (is.null(getOption("aedes.version")))
    options(aedes.version = "now")
  invisible()
}

.onAttach <- function(libname, pkgname) {
  v <- getOption("aedes.version")
  packageStartupMessage(
    "aedes: default version is ", format(v),
    "; change with aedes_set_version()")
}
