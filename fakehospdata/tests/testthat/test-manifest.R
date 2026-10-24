test_that("fh_tables lists both scales with schema and name", {
  cache <- local_sample_cache()
  s <- fh_tables("sample", cache = cache)
  f <- fh_tables("full", cache = cache)
  expect_true(all(c("table", "schema", "name", "rows", "n_files", "bytes", "paths") %in% names(s)))
  expect_setequal(unique(s$schema), c("layer1", "reference", "derived", "aggregate", "answers"))
  expect_equal(s$name[s$table == "answers/truth/spells"], "truth_spells")
  expect_true(f$n_files[f$table == "layer1/pas_adt_events"] > 1)
  expect_equal(f$rows[f$table == "layer1/pas_patients"], 805246)
  expect_true(all(startsWith(unlist(f$paths), "v2/full/")))
})

test_that("fh_download skips files already in the cache and rejects unknown tables", {
  cache <- local_sample_cache()
  got <- fh_download("sample", tables = c("sites", "derived/spells"), cache = cache, quiet = TRUE)
  expect_equal(nrow(got), 2)
  expect_true(all(file.exists(unlist(got$files))))
  expect_error(fh_download("sample", tables = "no_such_table", cache = cache), "Unknown table")
})
