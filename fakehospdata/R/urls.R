pages_base <- "https://thomuk.github.io/synthetic-hospital-data/data/"
release_base <- "https://github.com/ThomUK/synthetic-hospital-data/releases/download/"

#' Where downloaded files are kept
#'
#' Defaults to the user cache directory for this package (see
#' [tools::R_user_dir()]); set the environment variable `FAKEHOSPDATA_CACHE`
#' to use another directory, for example on a machine where the home
#' directory is small.
#'
#' @return A directory path (created on demand by the download functions).
#' @export
fh_cache_dir <- function() {
  env <- Sys.getenv("FAKEHOSPDATA_CACHE", unset = "")
  if (nzchar(env)) env else tools::R_user_dir("fakehospdata", "cache")
}

#' The URL a dataset file is served from
#'
#' The sample is served by GitHub Pages at its path under `data/`. The full
#' set is attached to a GitHub release, one asset per file; release assets
#' cannot be nested, so an asset is named by its path under `full/` with `/`
#' replaced by `__`.
#'
#' @param path A path as listed in the manifest, such as
#'   `"v2/sample/layer1/pas_patients.parquet"` or
#'   `"v2/full/layer1/pas_adt_events/fy2024.parquet"`.
#' @return A URL.
#' @examples
#' fh_url("v2/sample/derived/spells.parquet")
#' fh_url("v2/full/layer1/pas_adt_events/fy2024.parquet")
#' @export
fh_url <- function(path) {
  parts <- strsplit(path, "/", fixed = TRUE)
  vapply(parts, function(p) {
    version <- p[1]
    scale <- p[2]
    rest <- p[-(1:2)]
    if (identical(scale, "full")) {
      paste0(release_base, version, "/", paste(rest, collapse = "__"))
    } else {
      paste0(pages_base, paste(p, collapse = "/"))
    }
  }, character(1))
}

manifest_url <- function(version) paste0(pages_base, version, "/manifest.json")
