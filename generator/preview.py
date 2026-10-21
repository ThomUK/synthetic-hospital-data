#!/usr/bin/env python3
"""Write 100-row JSON previews of every table in the sample, for the data viewer.

    generator/preview.py <data_dir>/<version>            # e.g. data/v2

Reads manifest.json, takes the first 100 rows of each sample table in file
order and writes preview/sample/<layer>__<table>.json with the column names,
DuckDB types and the rows. build.py calls this at the end of a build. Only
the sample is previewed: it is the set served by Pages, and the full set has
the same columns.
"""
import datetime as dt
import json
import math
import sys
from pathlib import Path

import duckdb

N_ROWS = 100


def cell(v):
    if v is None:
        return None
    if isinstance(v, float):
        return None if math.isnan(v) else v
    if isinstance(v, (dt.datetime, dt.date, dt.time)):
        return v.isoformat(sep=" ") if isinstance(v, dt.datetime) else v.isoformat()
    if isinstance(v, (bytes, bytearray)):
        return v.hex()
    if isinstance(v, (int, bool, str)):
        return v
    if isinstance(v, (list, tuple)):
        return [cell(x) for x in v]
    return str(v)


def preview(con, parquet_path, n=N_ROWS):
    rel = con.execute(f"SELECT * FROM read_parquet('{parquet_path}') LIMIT {n}")
    cols = [{"name": d[0], "type": str(d[1])} for d in rel.description]
    rows = [[cell(v) for v in r] for r in rel.fetchall()]
    return cols, rows


def write_previews(version_dir):
    """version_dir holds manifest.json and sample/."""
    version_dir = Path(version_dir)
    m = json.load(open(version_dir / "manifest.json"))
    out = version_dir / "preview"
    con = duckdb.connect()
    written = {}
    for part in ("sample",):
        for table, v in m.get(part, {}).items():
            if "rows" not in v:
                continue
            # the largest file: for partitioned tables the first partitions hold
            # the few rows whose dates were mistyped into other years
            first = max(v["files"], key=lambda f: f["bytes"])["path"]  # "v1/full/layer1/x.parquet"
            rel = Path(*Path(first).parts[1:])  # drop the version prefix
            src = version_dir / rel
            if not src.exists():
                print(f"  missing {src}", file=sys.stderr)
                continue
            cols, rows = preview(con, src)
            d = out / part
            d.mkdir(parents=True, exist_ok=True)
            name = table.replace("/", "__") + ".json"
            with open(d / name, "w") as f:
                json.dump({"table": table, "part": part, "rows_total": v["rows"], "files": len(v["files"]),
                           "columns": cols, "rows": rows}, f, separators=(",", ":"))
            written[f"{part}/{table}"] = len(rows)
    with open(out / "index.json", "w") as f:
        json.dump({"version": m["version"], "n_rows": N_ROWS, "tables": written}, f, indent=1)
    return written


if __name__ == "__main__":
    w = write_previews(sys.argv[1])
    print(f"wrote {len(w)} previews")
