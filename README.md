# Synthetic Hospital Data

![Fake NHS Trust: a glass hospital with floating table schemas and charts](docs/images/fake-nhs-trust.png)

**Status: v2 published.** The sample is in `data/v2/`, the full set is on
the [v2 release](https://github.com/ThomUK/synthetic-hospital-data/releases/tag/v2),
and the [project page](https://thomuk.github.io/synthetic-hospital-data/)
[table viewer](https://thomuk.github.io/synthetic-hospital-data/viewer/)
and [ERDs](https://thomuk.github.io/synthetic-hospital-data/erd/) are live. The browser SQL console and the R helper package are still to come.

A seeded, reproducible synthetic dataset mimicking the data domain of a
single fictional English acute trust, built in three layers so that the
difference between *event* data, *derived entity* data and *aggregated* data
can be explored and taught with real SQL.

- [`docs/DESIGN.md`](docs/DESIGN.md) — the trust, the source systems, the
  tables in each layer, volumes, hosting and the generator.
- [`docs/MESS-CATALOGUE.md`](docs/MESS-CATALOGUE.md) — every kind of data
  mess the generator injects, where, at what rate, how to detect it and what
  it teaches.
- [`docs/CALIBRATION.md`](docs/CALIBRATION.md) — every volume and
  distribution traced to its public source.
- [`data/README.md`](data/README.md) — where the data is, how to read it
  from Python and R, versioning.
- [`generator/README.md`](generator/README.md) — the R package, the DuckDB
  build, the release workflow.
- [`viewer/`](viewer/) — the table viewer: an index of every table with
  counts, sizes and download links, and the first 100 rows of each. Pure JS;
  `node tests/engine.test.mjs` from `viewer/`.
- [`erd/`](erd/) — entity relationship diagrams, one per layer, generated
  from the data by `generator/erd.py`. Pure JS; `node tests/engine.test.mjs`
  from `erd/`.
- [`sql/`](sql/) — the derive and aggregate SQL the build runs.

Nothing in this folder is real. Every NHS number is prefixed `fake_`, the
trust, sites, wards, staff and patients are invented, and the distributions
are plausible rather than measured.
