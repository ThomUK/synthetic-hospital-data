test_that("fh_connect exposes cached tables as DuckDB views by layer", {
  skip_if_not_installed("duckdb")
  cache <- local_sample_cache()
  con <- fh_connect("sample", tables = c("sites", "specialties", "derived/spells"), cache = cache, quiet = TRUE)
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))
  expect_equal(DBI::dbGetQuery(con, "SELECT count(*) AS n FROM reference.sites")$n, 2)
  expect_equal(DBI::dbGetQuery(con, "SELECT count(*) AS n FROM reference.specialties")$n, 20)
  n <- DBI::dbGetQuery(con, "SELECT count(*) AS n FROM derived.spells")$n
  expect_equal(n, fh_tables("sample", cache = cache)$rows[fh_tables("sample", cache = cache)$table == "derived/spells"])
  joined <- DBI::dbGetQuery(con, "SELECT count(*) AS n FROM derived.spells s JOIN reference.specialties p ON p.tfc = s.tretspef_first")
  expect_true(joined$n > 0)
  expect_equal(nrow(fh_read("sites", "sample", cache = cache)), 2)
})
