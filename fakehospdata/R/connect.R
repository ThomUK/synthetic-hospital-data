#' Open the dataset as a DuckDB database
#'
#' Downloads anything missing from the cache (see [fh_download()]), then
#' returns an in-memory DuckDB connection with one schema per layer
#' (`layer1`, `reference`, `derived`, `aggregate`, `answers`) and one view per
#' table, so `derived.spells` or `layer1.pas_adt_events` can be queried and
#' joined with ordinary SQL. Tables partitioned by financial year in the full
#' set are read as one view. Nested answer tables are exposed as
#' `answers.truth_spells` and so on.
#'
#' @inheritParams fh_download
#' @param ... Passed to `DBI::dbConnect()` for duckdb, for example
#'   `config = list(memory_limit = "4GB")`.
#' @return A `duckdb_connection`. Close it with
#'   `DBI::dbDisconnect(con, shutdown = TRUE)`.
#' @examples
#' \dontrun{
#' con <- fh_connect("sample")
#' DBI::dbGetQuery(con, "SELECT count(*) FROM derived.spells WHERE emergency")
#' DBI::dbListObjects(con)
#' DBI::dbDisconnect(con, shutdown = TRUE)
#' }
#' @export
fh_connect <- function(scale = c("sample", "full"), version = "v2", tables = NULL,
                       cache = fh_cache_dir(), quiet = FALSE, ...) {
  scale <- match.arg(scale)
  tabs <- fh_download(scale, version, tables, cache, quiet)
  con <- DBI::dbConnect(duckdb::duckdb(), ...)
  for (s in unique(tabs$schema)) {
    DBI::dbExecute(con, paste0("CREATE SCHEMA IF NOT EXISTS ", DBI::dbQuoteIdentifier(con, s)))
  }
  for (i in seq_len(nrow(tabs))) {
    files <- paste0("'", gsub("'", "''", tabs$files[[i]], fixed = TRUE), "'", collapse = ", ")
    DBI::dbExecute(con, paste0(
      "CREATE VIEW ", DBI::dbQuoteIdentifier(con, tabs$schema[i]), ".", DBI::dbQuoteIdentifier(con, tabs$name[i]),
      " AS SELECT * FROM read_parquet([", files, "], union_by_name = true)"
    ))
  }
  if (!quiet) message(sprintf("%d tables of the %s set attached as views", nrow(tabs), scale))
  con
}

#' Read one table into R
#'
#' @param table A table as `layer/name` or `name`, for example `"spells"`.
#' @inheritParams fh_download
#' @return A data frame.
#' @examples
#' \dontrun{
#' spells <- fh_read("spells", "sample")
#' }
#' @export
fh_read <- function(table, scale = c("sample", "full"), version = "v2", cache = fh_cache_dir(), quiet = TRUE) {
  scale <- match.arg(scale)
  con <- fh_connect(scale, version, tables = table, cache = cache, quiet = quiet)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  tabs <- fh_tables(scale, version, cache)
  tabs <- select_tables(tabs, table)
  DBI::dbGetQuery(con, paste0("SELECT * FROM ", DBI::dbQuoteIdentifier(con, tabs$schema[1]), ".", DBI::dbQuoteIdentifier(con, tabs$name[1])))
}
