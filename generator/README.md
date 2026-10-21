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

## Publishing

The 5% sample is committed under `data/<version>/` with `manifest.json`.
The full set goes to a GitHub release through the
`Synthetic hospital dataset release` workflow
(`.github/workflows/synthetic-hospital-release.yml`, run by hand from the
Actions tab with the version as input). The runner installs the same
toolchain, regenerates layer 1 from the seed, builds, runs
`check_manifest.py` against the committed manifest (every row count must
match, checksums are reported) and uploads one asset per Parquet file with
`publish_release.sh`. A cloud session's token cannot create releases, which
is why the runner does it; the same script works locally with a personal
token.

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
| `publish_release.sh` | attaches the full set to a GitHub release |
| `setup-cloud.sh` | toolchain install for cloud sessions |

## Toolchain note

CRAN is unreachable from the cloud container and the Ubuntu archive has no
`arrow` or `duckdb` for R, so the package writes CSV and the Parquet
conversion, derived layer and aggregates run in Python DuckDB (deliverable 4).
