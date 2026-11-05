# Generator

`fakehosp/` is the R package that generates the Fake NHS Trust synthetic
dataset (layer 1: source-system extracts). See `../docs/DESIGN.md` for what
it builds and `../docs/CALIBRATION.md` for every number it is tuned to.

## Status

Clean generator (deliverable 2) and mess injection (deliverable 3).
`generate()` applies every catalogued imperfection at the rates in
`default_mess_rates()` and records each changed row in `mess_log`
(`mess_log.csv` in the output); `generate(mess = NULL)` gives the clean
dataset. The derived layer and Parquet publication are deliverable 4.

## Running it

In a cloud session, run `setup-cloud.sh` once (R 4.3.3, data.table,
testthat and friends from the Ubuntu archive, DuckDB and Arrow for Python).
Then:

```sh
R CMD INSTALL --no-docs generator/fakehosp
Rscript generator/run.R <out_dir> [n_patients] [seed] [clean]
```

Add `clean` as the fourth argument for a run with no mess injected.

Defaults are the full scale (800,000 patients) and seed 20230401. A
20,000-patient run takes about ten seconds and is the right size for
development. Output is one CSV per table plus `manifest.json` with the seed,
parameters and row counts.

Full-scale run on the cloud container (4 cores, 15 GB): 6 min 20 s to
generate, 8 min 45 s wall clock including the CSV write, 3.7 GB of CSV,
37.9 million rows:

| Table | Rows |
| --- | --- |
| pas_patients | 800,000 |
| pas_adt_events | 2,627,292 |
| ed_attendances | 795,950 |
| ed_status_log | 3,425,580 |
| pas_referrals | 2,096,135 |
| pas_outpatient_appointments | 6,163,826 |
| pas_op_status_log | 21,030,538 |
| ris_imaging | 933,561 |
| endo_procedures | 70,250 |

The two audit logs are two thirds of the rows. Parquet will compress them
heavily; if the published set still needs trimming, the logs are the first
candidates for per-year partitioning.

From R:

```r
library(fakehosp)
g <- generate(seed = 1L, n_patients = 20000L)
g$tables$pas_adt_events      # layer-1 tables as data.tables
g$truth$spells               # the clean spells the derived layer should reproduce
write_layer1(g, "out/")
```

## Building the published dataset

```sh
python3 generator/build.py --input <run_dir> --out data [--sample 0.05] [--version v1]
```

Loads the run's CSVs into DuckDB with explicit types, writes layer 1 as
Parquet (tables over a million rows partitioned by financial year), runs
`sql/derive` then `sql/aggregate`, draws the patient sample (by hash of the
surviving MRN so it is stable across builds), reruns the same SQL on the
sample, zips the sample as CSV and writes `manifest.json`. The derived
SQL is the same for full and sample; only the layer-1 schema name is
substituted. Internal working tables are named with a leading underscore
and are not published. Rebuilding takes about 1.5 minutes on four cores
for the full set. The build ends by writing `preview/sample/` (the first
100 rows of every sample table as JSON) for the table viewer; `preview.py`
also runs on its own against a build directory or the repository's
`data/v2`.

## The ERD is built from the data

`erd.py` writes `data/<version>/erd.json` at the end of each build. Column
names and types come from the sample Parquet, row counts from the manifest,
and lineage from the `CREATE TABLE` statements in `sql/`. Relationships are
inferred by naming convention (`ALIASES` maps column names to key concepts,
`CONCEPTS` says which table holds each key) and then measured: the share of
each child column's values found in the parent key, raw and after
normalising case and punctuation. A link at or above 99.5% is drawn as a
key, a partial match as a fuzzy link with its rate, and anything under 5%
is listed as rejected rather than drawn. Primary keys are checked for
uniqueness. The hand-maintained parts are the three lists at the top of
`erd.py` and the mess-catalogue notes shown on fuzzy links; add a line to
`ALIASES` or `CONCEPTS` when a new identifier appears, and the data decides
the rest. Running it on v1 was what found the duplicate MRNs and the
clinic-code and source-setting bugs listed in `pending-changes.json`.

## Pending changes to the published data

`../pending-changes.json` lists generator changes that are not yet in the
published dataset; every page shows it through the one shared module
`../banner.js`, so the notice cannot differ between pages. Add a line there with every change to the generator, and empty the
list when the next version is built and published.

## Publishing a new version

Everything below has been done for v1, v2 and v3 from a cloud session; it
is the procedure, with timings, for the next one. The published sample
lives in the repository under `data/<version>/`; the full set is attached
to a GitHub release by the `Dataset release` workflow, which a session
cannot do itself (its token may not create releases), so the runner
rebuilds the data from the seed and uploads it.

1. **Decide the version.** A published version is immutable, so a
   regenerated dataset is the next `vN`. `pending-changes.json` lists what
   the generator has changed since the last build; that list becomes the
   new version's row in the table in `data/README.md`.
2. **Run the pipeline** from the repository root:
   `generator/publish_version.sh v3 /some/work/dir`. It installs the R
   package into a private library, generates layer 1 at full scale
   (about 9 minutes, 12 GB of RAM, 4.6 GB of CSV in the work dir), builds
   the Parquet, derived and aggregate layers, the 5% sample, the previews
   and `erd.json` (about 2 minutes), copies the sample set into
   `data/v3/`, removes `data/v2/`, runs `new_version.py v3` to point
   every path, default and the reader package at v3, and runs the JS
   tests. Run it in the background with the log in a file: it takes about
   12 minutes. Do not run anything else heavy alongside it; the generator
   peaks at 12 GB on a 15 GB machine.
3. **Check the result.** `git status` should show `data/v3/` added,
   `data/v2/` deleted, and small edits to the files that name the version
   (`index.html`, `viewer/app.js`, `erd/app.js`, `README.md`,
   `data/README.md`, `CLAUDE.md`, `.github/workflows/release.yml`,
   `generator/build.py`, the `fakehospdata` defaults and tests,
   `pending-changes.json` now empty for v3). Then run the R tests:
   `cd generator/fakehosp && R_LIBS_USER=<work>/rlib Rscript -e 'testthat::test_dir("tests/testthat")'`
   (about 5 minutes). The reader package's tests (`testthat::test_local(".")`
   in `fakehospdata/`) need the `duckdb` R package, which the cloud
   container cannot install (no CRAN access, not in the Ubuntu archive), so
   run those locally; `new_version.py` has already pointed their fixtures
   at the new version.
4. **Commit and push** as `Claude <noreply@anthropic.com>` to `main`. The
   Pages workflow deploys the site with the new data within two minutes;
   `banner.js` stops showing the out-of-sync notice because the pending
   list is empty.
5. **Release the full set.** Run the `Dataset release` workflow
   (`.github/workflows/release.yml`) with `version=v3`: from the Actions
   tab, or `gh workflow run release.yml -f version=v3`, or the GitHub MCP
   `actions_run_trigger` tool. The runner installs the same toolchain,
   regenerates from the seed, builds, runs `check_manifest.py` against the
   committed `data/v3/manifest.json` (every row count must match or the
   job fails; checksums are reported only, because Parquet bytes differ
   between machines) and uploads one asset per Parquet file with
   `publish_release.sh`, plus the rebuilt manifest. About 10 minutes.
6. **Verify**: the release page lists 77 assets of about 1 GB; download
   one asset and query it; the project page, viewer and ERD page load the
   new version.

Things that have gone wrong before, so you do not repeat them: the
runner's R library is read-only without `sudo` (the workflow has it); the
Pages site had to be enabled once in the repository settings before the
deploy workflow could run; a full run that fails late is usually a mess
step tripping on an edge case the small test runs never hit (the first v2
run failed on an unparseable date), so read the tail of `run.log`; the
Python build's default `--version` and every page path are updated by
`new_version.py`, not by hand; and `data/<version>/` must never be edited
after it is pushed.

The R package needs a library the session can write to: `R_LIBS_USER` set
to a directory under the scratchpad, as the script does. CRAN is not
reachable from the cloud container; the R dependencies come from the
Ubuntu archive (`r-cran-*`, see `setup-cloud.sh`) and Python DuckDB from
PyPI. The full set itself stays in the work dir and is never committed.

## Tests

```sh
cd generator/fakehosp && Rscript -e 'testthat::test_dir("tests/testthat")'
```

The suite checks determinism (same seed, identical output), fake NHS
number check digits, the calibrated annual volumes within tolerance, ED
conversion and four-hour performance, imaging source mix and waits, ADT
structure (one A01 per spell, A03 only for closed spells, ordering),
cross-system identifier integrity, ECDS timestamp ordering, the DID hard
validations, the endoscopy vendor formats, no activity after death, and the
CSV writer.

## Layout

| Path | What |
| --- | --- |
| `fakehosp/R/config.R` | annual volumes at full scale and the seasonal, weekday and time-of-day indices |
| `fakehosp/R/reference.R` | sites, wards, specialties, consultants, clinics, exam catalogue, national code lists |
| `fakehosp/R/population.R` | patients, identifiers, activity weights |
| `fakehosp/R/ed.R` | ED attendances (ECDS-shaped) and the tracking-board log |
| `fakehosp/R/outpatients.R` | referrals, RTT pathways, appointments, appointment audit log |
| `fakehosp/R/admissions.R` | spells, ward stays, episodes, ADT events |
| `fakehosp/R/imaging.R` | CT, MRI and ultrasound requests and exams |
| `fakehosp/R/endoscopy.R` | the endoscopy vendor export |
| `fakehosp/R/generate.R` | orchestration, deaths, post-death activity reassignment |
| `fakehosp/R/write.R` | CSV writer and manifest |
| `fakehosp/inst/extdata/` | ECDS code lists (from the ETOS) and NICIP-to-SNOMED map (from DID Annex 1) |
| `run.R` | command-line entry point |
| `build.py` | Parquet conversion, derived and aggregate SQL, sample, manifest (Python DuckDB) |
| `check_manifest.py` | compares a rebuilt manifest with the committed one |
| `preview.py` | 100-row JSON previews of every sample table for the table viewer; run by `build.py` |
| `erd.py` | `erd.json` for the ERD page: columns from the Parquet, links inferred by name and measured against the data, lineage parsed from `sql/`; run by `build.py` |
| `publish_release.sh` | attaches the full set to a GitHub release; run by the release workflow |
| `publish_version.sh` | the whole session-side pipeline for a new version: install, generate, build, stage `data/vN`, bump, test |
| `new_version.py` | points every version reference at the new version and rolls `pending-changes.json` into the version table |
| `setup-cloud.sh` | toolchain install for cloud sessions |

## Toolchain note

CRAN is unreachable from the cloud container and the Ubuntu archive has no
`arrow` or `duckdb` for R, so the package writes CSV and the Parquet
conversion, derived layer and aggregates run in Python DuckDB (deliverable 4).
