#' Download a scale of the dataset into the cache
#'
#' Fetches every file of the chosen scale that is not already in the cache
#' with the size the manifest records. The sample is about 130 MB; the full
#' set is about 1.1 GB. Files already present are skipped, so re-running is
#' cheap and an interrupted download resumes where it stopped.
#'
#' @inheritParams fh_tables
#' @param tables Optional character vector of tables to fetch, as
#'   `layer/name` (for example `"derived/spells"`) or just `name`; default
#'   all.
#' @param quiet Suppress progress messages?
#' @return A data frame of the tables fetched (see [fh_tables()]) with a
#'   `files` list column of local paths, invisibly.
#' @examples
#' \dontrun{
#' fh_download("sample")
#' fh_download("full", tables = c("derived/spells", "derived/patients"))
#' }
#' @export
fh_download <- function(scale = c("sample", "full"), version = "v2", tables = NULL,
                        cache = fh_cache_dir(), quiet = FALSE) {
  scale <- match.arg(scale)
  m <- scale_manifest(scale, version, cache)
  tabs <- fh_tables(scale, version, cache, manifest = m)
  tabs <- select_tables(tabs, tables)
  files <- do.call(rbind, lapply(tabs$table, function(t) {
    f <- m[[scale]][[t]]$files
    data.frame(path = vapply(f, function(x) x$path, character(1)),
               bytes = vapply(f, function(x) as.numeric(x$bytes %||% NA), numeric(1)),
               stringsAsFactors = FALSE)
  }))
  files$dest <- file.path(cache, files$path)
  have <- file.exists(files$dest) & (is.na(files$bytes) | file.size(files$dest) == files$bytes)
  todo <- files[!have, , drop = FALSE]
  if (nrow(todo) > 0) {
    if (!quiet) message(sprintf("Downloading %d file%s (%.0f MB) to %s", nrow(todo), if (nrow(todo) == 1) "" else "s",
                                sum(todo$bytes, na.rm = TRUE) / 1e6, cache))
    for (i in seq_len(nrow(todo))) {
      dir.create(dirname(todo$dest[i]), showWarnings = FALSE, recursive = TRUE)
      tmp <- paste0(todo$dest[i], ".part")
      utils::download.file(fh_url(todo$path[i]), tmp, mode = "wb", quiet = TRUE)
      if (!is.na(todo$bytes[i]) && file.size(tmp) != todo$bytes[i]) {
        unlink(tmp)
        stop("Downloaded size of ", todo$path[i], " (", file.size(tmp), " bytes) does not match the manifest (", todo$bytes[i], ")")
      }
      check_parquet(tmp, todo$path[i])
      file.rename(tmp, todo$dest[i])
      if (!quiet && (i %% 10 == 0 || i == nrow(todo))) message(sprintf("  %d of %d files", i, nrow(todo)))
    }
  }
  tabs$files <- lapply(tabs$paths, function(p) file.path(cache, p))
  invisible(tabs)
}

select_tables <- function(tabs, tables) {
  if (is.null(tables)) return(tabs)
  keep <- tabs$table %in% tables | tabs$name %in% tables
  missing <- setdiff(tables, c(tabs$table, tabs$name))
  if (length(missing) > 0) stop("Unknown table(s): ", paste(missing, collapse = ", "))
  tabs[keep, , drop = FALSE]
}

#' Fail early on a truncated or non-Parquet download by reading its metadata
#' @noRd
check_parquet <- function(file, path) {
  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  ok <- tryCatch({
    DBI::dbGetQuery(con, paste0("SELECT count(*) AS n FROM parquet_metadata('", gsub("'", "''", file, fixed = TRUE), "')"))
    TRUE
  }, error = function(e) FALSE)
  if (!ok) {
    unlink(file)
    stop("Downloaded file ", path, " is not a readable Parquet file")
  }
}
