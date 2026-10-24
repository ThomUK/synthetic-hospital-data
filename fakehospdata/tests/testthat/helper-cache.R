# A cache directory seeded from the repository's own copy of the sample, so the
# tests run offline: the manifest and the sample Parquet files are copied into
# the layout fh_download() expects (<cache>/v2/sample/...).
repo_data <- function() {
  candidates <- c(
    testthat::test_path("..", "..", "..", "data", "v2"),
    file.path(Sys.getenv("FAKEHOSPDATA_REPO_DATA", unset = ""), "v2")
  )
  for (d in candidates) if (file.exists(file.path(d, "manifest.json"))) return(normalizePath(d))
  NULL
}

local_sample_cache <- function(tables = c("reference/sites", "reference/specialties", "derived/spells"), env = parent.frame()) {
  src <- repo_data()
  testthat::skip_if(is.null(src), "repository data/v2 not found")
  cache <- withr::local_tempdir(.local_envir = env)
  dir.create(file.path(cache, "v2"), recursive = TRUE)
  file.copy(file.path(src, "manifest.json"), file.path(cache, "v2", "manifest.json"))
  m <- jsonlite::fromJSON(file.path(src, "manifest.json"), simplifyVector = FALSE)
  for (t in tables) {
    for (f in m$sample[[t]]$files) {
      dest <- file.path(cache, f$path)
      dir.create(dirname(dest), showWarnings = FALSE, recursive = TRUE)
      file.copy(file.path(src, sub("^v2/", "", f$path)), dest)
    }
  }
  cache
}
