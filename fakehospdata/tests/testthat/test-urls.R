test_that("urls follow the Pages and release conventions", {
  expect_equal(fh_url("v3/sample/derived/spells.parquet"),
               "https://thomuk.github.io/synthetic-hospital-data/data/v3/sample/derived/spells.parquet")
  expect_equal(fh_url("v3/full/derived/spells.parquet"),
               "https://github.com/ThomUK/synthetic-hospital-data/releases/download/v3/derived__spells.parquet")
  expect_equal(fh_url("v3/full/layer1/pas_adt_events/fy2024.parquet"),
               "https://github.com/ThomUK/synthetic-hospital-data/releases/download/v3/layer1__pas_adt_events__fy2024.parquet")
  expect_equal(fakehospdata:::manifest_url("v3"), "https://thomuk.github.io/synthetic-hospital-data/data/v3/manifest.json")
})

test_that("the cache directory honours the environment variable", {
  withr::local_envvar(FAKEHOSPDATA_CACHE = "/tmp/fh-cache-test")
  expect_equal(fh_cache_dir(), "/tmp/fh-cache-test")
  withr::local_envvar(FAKEHOSPDATA_CACHE = "")
  expect_match(fh_cache_dir(), "fakehospdata")
})

test_that("the release manifest has its own url and cache file", {
  expect_equal(fakehospdata:::release_base, "https://github.com/ThomUK/synthetic-hospital-data/releases/download/")
})
