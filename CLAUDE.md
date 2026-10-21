# synthetic-hospital-data

A seeded, reproducible, deliberately messy synthetic dataset for a fictional
acute trust (Fake NHS Trust), with an R generator, a DuckDB build, derived
and aggregate SQL, a table viewer and entity relationship diagrams, deployed
to GitHub Pages from `main`.

## Working rules

- **Always merge finished work to `main` and push it.** There is no review
  gate and Pages only deploys from `main`. Do the work on the session branch
  if one is assigned, then fast-forward or merge it into `main` and push
  `main`. Do not leave work on a side branch or open a pull request unless
  asked.
- **Commit and merge as Claude, never as the repo owner.** Author and
  committer must be `Claude <noreply@anthropic.com>`; prefer fast-forward
  merges so no merge commit is created under another name.
- **Do not regenerate the published data unless asked.** Every change to the
  generator that is not yet in `data/<version>/` gets a line in
  `pending-changes.json`; the pages show it as a banner through `banner.js`.
  A regenerated dataset is a new version directory with its own manifest.
- Asset URLs use `?v=dev`; the Pages workflow rewrites them to the commit SHA.
- Pure-JS apps keep their engine DOM-free and unit-tested:
  `node tests/engine.test.mjs` in `viewer/` and `erd/`, and
  `node tests/banner.test.mjs` at the root.
- The R package tests: `cd generator/fakehosp && Rscript -e 'testthat::test_dir("tests/testthat")'`.
- Full-set releases come from the `release` workflow (Actions tab, run by
  hand with the version as input), never from a session. See `generator/README.md`.
