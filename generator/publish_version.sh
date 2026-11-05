#!/usr/bin/env bash
# Build and stage a new published data version, end to end, in a session.
#
#   generator/publish_version.sh v3 [work_dir]
#
# Runs from the repository root. Needs R 4.3+ with data.table, jsonlite,
# withr, cli, checkmate, digest, lubridate (Ubuntu: r-cran-*), and Python 3
# with duckdb and pyarrow. Takes about 12 minutes and 12 GB of RAM for the
# full 800,000-patient run; the work_dir needs about 7 GB free.
#
# Steps: install the R package into a private library, generate layer 1 at
# full scale (about 9 min), build Parquet + derived + aggregate + sample +
# previews + erd.json (about 2 min), copy the sample set into data/<version>,
# delete the previous data/v* directory, point every reference at the new
# version (new_version.py), run the JS tests. It does NOT commit, push or
# release: see generator/README.md, "Publishing a new version", for those.
set -euo pipefail
version="${1:?usage: generator/publish_version.sh vN [work_dir]}"
work="${2:-${TMPDIR:-/tmp}/fakehosp-$version}"
cd "$(dirname "$0")/.."
[[ "$version" =~ ^v[0-9]+$ ]] || { echo "version must look like v3"; exit 1; }
[ -d "data/$version" ] && { echo "data/$version already exists; a published version is immutable"; exit 1; }
mkdir -p "$work/rlib" "$work/run"
export R_LIBS_USER="$work/rlib"
echo "$(date +%T) installing fakehosp into $R_LIBS_USER"
R CMD INSTALL --no-docs -l "$R_LIBS_USER" generator/fakehosp > "$work/install.log" 2>&1 || { tail -20 "$work/install.log"; exit 1; }
echo "$(date +%T) generating layer 1 at full scale into $work/run (about 9 minutes)"
Rscript generator/run.R "$work/run" > "$work/run.log" 2>&1 || { tail -30 "$work/run.log"; exit 1; }
grep -E "Peak R heap|generated_at" "$work/run.log" | head -2
echo "$(date +%T) building $version into $work/build (about 2 minutes)"
rm -rf "$work/build" "$work/build.duckdb"
python3 generator/build.py --input "$work/run" --out "$work/build" --version "$version" --db "$work/build.duckdb" > "$work/build.log" 2>&1 || { tail -30 "$work/build.log"; exit 1; }
rm -f "$work/build.duckdb"
tail -1 "$work/build.log"
echo "$(date +%T) staging data/$version (sample, previews, manifest, erd.json)"
mkdir -p "data/$version"
cp -r "$work/build/$version/sample" "$work/build/$version/preview" "data/$version/"
cp "$work/build/$version/manifest.json" "$work/build/$version/erd.json" "data/$version/"
for d in data/v*/; do d="${d%/}"; [ "$d" = "data/$version" ] || { echo "removing previous $d"; git rm -r -q "$d"; }; done
echo "$(date +%T) pointing the repository at $version"
python3 generator/new_version.py "$version"
echo "$(date +%T) tests"
node tests/banner.test.mjs | tail -1
(cd viewer && node tests/engine.test.mjs | tail -1)
(cd erd && node tests/engine.test.mjs | tail -1)
du -sh "data/$version"
cat <<MSG

Staged. Full set is in $work/build/$version/full (not committed; the release
workflow rebuilds it on a runner). Next, by hand:
  1. review: git status; git diff -- pending-changes.json data/README.md
  2. R tests: (cd generator/fakehosp && R_LIBS_USER=$R_LIBS_USER Rscript -e 'testthat::test_dir("tests/testthat")')
  3. commit as Claude and push main (the Pages workflow deploys the site)
  4. run the "Dataset release" workflow with version=$version (Actions tab, or
     gh workflow run release.yml -f version=$version); it rebuilds from the seed,
     checks every row count against data/$version/manifest.json and attaches
     the full set as release $version (about 10 minutes)
  5. check https://github.com/ThomUK/synthetic-hospital-data/releases/tag/$version
MSG
