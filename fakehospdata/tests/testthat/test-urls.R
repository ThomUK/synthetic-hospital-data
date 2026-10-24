test_that("urls follow the Pages and release conventions", {
  expect_equal(fh_url("v2/sample/derived/spells.parquet"),
               "https://thomuk.github.io/synthetic-hospital-data/data/v2/sample/derived/spells.parquet")
  expect_equal(fh_url("v2/full/derived/spells.parquet"),
               "https://github.com/ThomUK/synthetic-hospital-data/releases/download/v2/derived__spells.parquet")
  expect_equal(fh_url("v2/full/layer1/pas_adt_events/fy2024.parquet"),
               "https://github.com/ThomUK/synthetic-hospital-data/releases/download/v2/layer1__pas_adt_events__fy2024.parquet")
  expect_equal(fakehospdata:::manifest_url("v2"), "https://thomuk.github.io/synthetic-hospital-data/data/v2/manifest.json")
})

test_that("the cache directory honours the environment variable", {
  withr::local_envvar(FAKEHOSPDATA_CACHE = "/tmp/fh-cache-test")
  expect_equal(fh_cache_dir(), "/tmp/fh-cache-test")
  withr::local_envvar(FAKEHOSPDATA_CACHE = "")
  expect_match(fh_cache_dir(), "fakehospdata")
})
