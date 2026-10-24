#' Read a version's manifest
#'
#' The manifest lists every file of the sample and the full set with its row
#' count, size and checksum. It is downloaded once into the cache and read
#' from there afterwards; `refresh = TRUE` downloads it again.
#'
#' @param version Dataset version, such as `"v2"`.
#' @param cache Cache directory, see [fh_cache_dir()].
#' @param refresh Download again even if cached?
#' @return The parsed manifest as a list.
#' @export
fh_manifest <- function(version = "v2", cache = fh_cache_dir(), refresh = FALSE) {
  dest <- file.path(cache, version, "manifest.json")
  if (refresh || !file.exists(dest)) {
    dir.create(dirname(dest), showWarnings = FALSE, recursive = TRUE)
    utils::download.file(manifest_url(version), dest, mode = "wb", quiet = TRUE)
  }
  jsonlite::fromJSON(dest, simplifyVector = FALSE)
}

#' List the tables of a scale
#'
#' @param scale `"sample"` (5% of patients, served by GitHub Pages) or
#'   `"full"` (every row, from the GitHub release).
#' @inheritParams fh_manifest
#' @param manifest A manifest from [fh_manifest()]; downloaded if `NULL`.
#' @return A data frame with one row per table: `table` (`layer/name` as in
#'   the manifest), `schema` and `name` (how [fh_connect()] exposes it),
#'   `rows`, `n_files`, `bytes` and `paths` (a list column of file paths).
#' @examples
#' \dontrun{
#' fh_tables("sample")
#' }
#' @export
fh_tables <- function(scale = c("sample", "full"), version = "v2", cache = fh_cache_dir(), manifest = NULL) {
  scale <- match.arg(scale)
  m <- manifest %||% fh_manifest(version, cache)
  entries <- m[[scale]]
  is_parquet <- function(e) !is.null(e$files) && all(grepl("\\.parquet$", vapply(e$files, function(f) f$path, character(1))))
  entries <- entries[vapply(entries, is_parquet, logical(1))]   # drops the sample's CSV zip
  if (length(entries) == 0) stop("No tables listed for scale '", scale, "' in version ", version)
  tables <- names(entries)
  parts <- strsplit(tables, "/", fixed = TRUE)
  out <- data.frame(
    table = tables,
    schema = vapply(parts, `[`, character(1), 1),
    name = vapply(parts, function(p) paste(p[-1], collapse = "_"), character(1)),
    rows = vapply(entries, function(e) as.numeric(e$rows %||% NA), numeric(1)),
    n_files = vapply(entries, function(e) length(e$files), integer(1)),
    bytes = vapply(entries, function(e) sum(vapply(e$files, function(f) as.numeric(f$bytes %||% 0), numeric(1))), numeric(1)),
    stringsAsFactors = FALSE
  )
  out$paths <- lapply(entries, function(e) vapply(e$files, function(f) f$path, character(1)))
  rownames(out) <- NULL
  out
}

`%||%` <- function(x, y) if (is.null(x)) y else x
