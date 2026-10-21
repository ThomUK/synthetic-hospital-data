#!/usr/bin/env python3
"""Build the published dataset from a generator run.

  python3 generator/build.py --input <run_dir> --out <data_dir> [--sample 0.05] [--version v1]

Steps: load the layer-1 CSVs into DuckDB with explicit types; write layer 1 as
Parquet (large tables partitioned by financial year); run sql/derive and
sql/aggregate; draw a patient sample and run the same SQL on it; write the
sample as Parquet and as a CSV zip; write manifest.json with row counts,
file sizes and SHA-256 checksums.
"""
import argparse, hashlib, json, os, shutil, sys, time, zipfile
from pathlib import Path
import duckdb

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
SQL = ROOT / "sql"

# Column types for the layer-1 tables (everything not listed is VARCHAR).
TS, D, I = "TIMESTAMP", "DATE", "INTEGER"
TYPES = {
    "pas_patients": {"dob": D, "registered_datetime": TS, "date_of_death": D},
    "pas_adt_events": {"message_id": I, "event_datetime": TS, "recorded_datetime": TS, "decision_to_admit_date": D, "discharge_ready_date": D},
    "ed_attendances": {"acuity": I, "activity_start_datetime": TS, "initial_assessment_timestamp": TS, "seen_for_treatment_timestamp": TS,
                       "decided_to_admit_datetime": TS, "clinically_ready_to_proceed_timestamp": TS, "activity_end_timestamp": TS},
    "ed_status_log": {"recorded_datetime": TS, "log_id": I},
    "pas_referrals": {"referral_received_date": D, "rtt_period_start_date": D, "rtt_period_end_date": D},
    "pas_outpatient_appointments": {"appointment_datetime": TS, "booked_datetime": TS, "cancelled_datetime": TS, "dna_date": D},
    "pas_op_status_log": {"recorded_datetime": TS, "log_id": I},
    "ris_imaging": {"ris_patient_id": I, "request_datetime": TS, "request_received_datetime": TS, "vetted_datetime": TS, "booked_datetime": TS,
                    "scan_start_datetime": TS, "scan_end_datetime": TS, "slot_minutes": I, "reported_datetime": TS, "verified_datetime": TS, "dm01_countable": I},
    "endo_procedures": {"ListPoints": I, "Points": I, "Comfort": I},
    "mess_log": {"mess_row": I},
}
TRUTH_TYPES = {
    "spells": {"admit": TS, "discharge": TS, "los": "DOUBLE", "died": "BOOLEAN", "day_case": "BOOLEAN", "endoscopy": "BOOLEAN", "n_episodes": I, "open_at_end": "BOOLEAN", "cancelled": "BOOLEAN"},
    "stays": {"from": TS, "to": TS, "seq": I}, "ed_admitted": {"admitted": "BOOLEAN"}, "mrn_aliases": {"merged": "BOOLEAN"},
    "imaging_links": {}, "endoscopy_links": {},
}
# Tables partitioned by financial year of this column when published in full.
PARTITION = {"pas_adt_events": "recorded_datetime", "pas_outpatient_appointments": "appointment_datetime", "pas_op_status_log": "recorded_datetime",
             "ed_status_log": "recorded_datetime", "ed_attendances": "activity_start_datetime", "ris_imaging": "request_received_datetime",
             "pas_referrals": "referral_received_date", "mess_log": None}
PATIENT_KEY = {"pas_patients": "mrn", "pas_adt_events": "mrn", "ed_attendances": "mrn", "pas_referrals": "mrn", "pas_outpatient_appointments": "mrn",
               "ris_imaging": "mrn", "endo_procedures": "HospNo"}


def log(*a):
    print(time.strftime("%H:%M:%S"), *a, flush=True)


def csv_header(path):
    with open(path, encoding="utf-8") as f:
        return f.readline().rstrip("\n").split(",")


def load_csv(con, schema, name, path, types):
    cols = csv_header(path)
    # timestamps are read as text and parsed tolerantly (with or without fractional seconds), then truncated to whole seconds
    typed = ", ".join(f"'{c}': '{'VARCHAR' if types.get(c) == TS else types.get(c, 'VARCHAR')}'" for c in cols)
    # a rare data.table fwrite artefact prints a fraction that rounds to one second as ".:00"; drop it before parsing
    sel = ", ".join(f"date_trunc('second', CAST(regexp_replace(replace(\"{c}\", 'Z', ''), '\\.:00$', '') AS TIMESTAMP)) AS \"{c}\"" if types.get(c) == TS else f'"{c}"' for c in cols)
    dq = '"'
    con.execute(f"CREATE OR REPLACE TABLE {schema}.{name} AS SELECT {sel} FROM read_csv('{path}', header = true, types = {{{typed}}}, nullstr = '', quote = '{dq}', escape = '{dq}', delim = ',')")
    return con.execute(f"SELECT count(*) FROM {schema}.{name}").fetchone()[0]


def run_sql_dir(con, d, src="l1"):
    """Run the SQL files in order; the layer-1 schema name is substituted so the same SQL runs on the sample."""
    for f in sorted(Path(d).glob("*.sql")):
        log("  sql", f.name)
        con.execute(f.read_text().replace("l1.", f"{src}."))


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def write_parquet(con, schema, name, out_dir, partition_col=None, published_name=None):
    published_name = published_name or name
    out_dir.mkdir(parents=True, exist_ok=True)
    files = []
    n = con.execute(f"SELECT count(*) FROM {schema}.{name}").fetchone()[0]
    if partition_col and n > 1_000_000:
        fys = [r[0] for r in con.execute(f"SELECT DISTINCT fy({partition_col}) AS fy FROM {schema}.{name} ORDER BY 1").fetchall()]
        d = out_dir / published_name
        d.mkdir(exist_ok=True)
        for fy in fys:
            p = d / f"fy{fy}.parquet"
            cond = f"fy({partition_col}) = {fy}" if fy is not None else f"{partition_col} IS NULL"
            con.execute(f"COPY (SELECT * FROM {schema}.{name} WHERE {cond}) TO '{p}' (FORMAT PARQUET, COMPRESSION ZSTD)")
            files.append(p)
    else:
        p = out_dir / f"{published_name}.parquet"
        con.execute(f"COPY (SELECT * FROM {schema}.{name}) TO '{p}' (FORMAT PARQUET, COMPRESSION ZSTD)")
        files.append(p)
    return n, files


def file_entries(files, base):
    return [{"path": str(f.relative_to(base)).replace(os.sep, "/"), "bytes": f.stat().st_size, "sha256": sha256(f)} for f in files]


def build_layers(con, out_dir, base, label, tables, partition=True, src="l1"):
    """Write layer 1, derived and aggregate tables for the layer-1 schema `src`."""
    manifest = {}
    log(label, "layer 1 -> parquet")
    for t in tables:
        n, files = write_parquet(con, src, t, out_dir / "layer1", PARTITION.get(t) if partition else None)
        manifest[f"layer1/{t}"] = {"rows": n, "files": file_entries(files, base)}
    for t in [r[0] for r in con.execute(f"SELECT table_name FROM information_schema.tables WHERE table_schema = '{src}' AND table_name LIKE 'ref_%'").fetchall()]:
        n, files = write_parquet(con, src, t, out_dir / "reference", None, t.replace("ref_", "", 1))
        manifest[f"reference/{t.replace('ref_', '', 1)}"] = {"rows": n, "files": file_entries(files, base)}
    log(label, "derive")
    con.execute("CREATE SCHEMA IF NOT EXISTS derived"); run_sql_dir(con, SQL / "derive", src)
    for t in [r[0] for r in con.execute("SELECT table_name FROM information_schema.tables WHERE table_schema = 'derived' AND table_name NOT LIKE '\\_%' ESCAPE '\\' ORDER BY 1").fetchall()]:
        n, files = write_parquet(con, "derived", t, out_dir / "derived", None)
        manifest[f"derived/{t}"] = {"rows": n, "files": file_entries(files, base)}
    log(label, "aggregate")
    con.execute("CREATE SCHEMA IF NOT EXISTS agg"); run_sql_dir(con, SQL / "aggregate", src)
    for t in [r[0] for r in con.execute("SELECT table_name FROM information_schema.tables WHERE table_schema = 'agg' ORDER BY 1").fetchall()]:
        n, files = write_parquet(con, "agg", t, out_dir / "aggregate", None)
        manifest[f"aggregate/{t}"] = {"rows": n, "files": file_entries(files, base)}
    return manifest


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", required=True); ap.add_argument("--out", required=True)
    ap.add_argument("--sample", type=float, default=0.05); ap.add_argument("--version", default="v2")
    ap.add_argument("--db", default=None, help="DuckDB file to use instead of memory (lets the build spill to disk)")
    a = ap.parse_args()
    run = Path(a.input); out = Path(a.out) / a.version; base = Path(a.out)
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    gm = json.load(open(run / "manifest.json"))
    con = duckdb.connect(a.db or ":memory:")
    con.execute("PRAGMA threads=4"); con.execute("SET preserve_insertion_order=false")
    con.execute("CREATE SCHEMA l1")
    log("loading layer 1 from", run)
    tables = [t for t in TYPES if (run / f"{t}.csv").exists()]
    counts = {}
    for t in tables:
        counts[t] = load_csv(con, "l1", t, run / f"{t}.csv", TYPES[t]); log("  ", t, counts[t])
    for p in sorted(run.glob("ref_*.csv")):
        load_csv(con, "l1", p.stem, p, {})
    con.execute("CREATE SCHEMA truth")
    for p in sorted((run / "truth").glob("*.csv")):
        load_csv(con, "truth", p.stem, p, TRUTH_TYPES.get(p.stem, {}))
    # macros used by partitioning before the derive SQL defines them
    con.execute("CREATE OR REPLACE MACRO fy(x) AS CASE WHEN month(x) >= 4 THEN year(x) ELSE year(x) - 1 END")

    manifest = {"dataset": "Fake NHS Trust synthetic hospital data", "version": a.version, "generator": gm, "built_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                "window": {"start": gm["start"], "end": gm["end"]}, "timestamps": "UTC, whole seconds; see docs/MESS-CATALOGUE.md M-X-02 for the clock offsets inside the data",
                "layout": {"full": "every row", "sample": f"{a.sample:.0%} of patients (by hash of the surviving MRN) with all of their rows in every table; derived and aggregate layers recomputed on the sample"},
                "full": {}, "sample": {}}

    # ---- full ----
    layer1_tables = [t for t in tables if t != "mess_log"]
    manifest["full"] = build_layers(con, out / "full", base, "full", layer1_tables)
    n, files = write_parquet(con, "l1", "mess_log", out / "full" / "answers", None)
    manifest["full"]["answers/mess_log"] = {"rows": n, "files": file_entries(files, base)}
    for t in [r[0] for r in con.execute("SELECT table_name FROM information_schema.tables WHERE table_schema = 'truth'").fetchall()]:
        n, files = write_parquet(con, "truth", t, out / "full" / "answers" / "truth", None)
        manifest["full"][f"answers/truth/{t}"] = {"rows": n, "files": file_entries(files, base)}

    # ---- sample: same pipeline on a patient subset ----
    log("sample: selecting patients")
    con.execute(f"CREATE TABLE sample_people AS SELECT person_mrn FROM derived.mrn_map GROUP BY person_mrn HAVING (hash(person_mrn) % 10000) < {int(a.sample * 10000)}")
    con.execute("CREATE TABLE sample_mrns AS SELECT m.mrn FROM derived.mrn_map m JOIN sample_people s ON s.person_mrn = m.person_mrn")
    con.execute("CREATE TABLE sample_nhs AS SELECT DISTINCT nhs_number FROM l1.pas_patients WHERE mrn IN (SELECT mrn FROM sample_mrns) AND nhs_number IS NOT NULL")
    full = {t: f"l1.{t}" for t in tables}
    con.execute("CREATE SCHEMA s1")
    for t in layer1_tables:
        key = PATIENT_KEY.get(t)
        if t == "ed_attendances":
            con.execute("CREATE TABLE s1.ed_attendances AS SELECT * FROM l1.ed_attendances WHERE mrn IN (SELECT mrn FROM sample_mrns) OR (mrn IS NULL AND nhs_norm(nhs_number) IN (SELECT nhs_number FROM sample_nhs))")
        elif t == "endo_procedures":
            con.execute("CREATE TABLE s1.endo_procedures AS SELECT * FROM l1.endo_procedures WHERE HospNo IN (SELECT mrn FROM sample_mrns) OR (HospNo IS NULL AND nhs_norm(NHSNo) IN (SELECT nhs_number FROM sample_nhs))")
        elif t == "ed_status_log":
            con.execute("CREATE TABLE s1.ed_status_log AS SELECT * FROM l1.ed_status_log WHERE uec_activity_identifier IN (SELECT uec_activity_identifier FROM s1.ed_attendances)")
        elif t == "pas_op_status_log":
            con.execute("CREATE TABLE s1.pas_op_status_log AS SELECT * FROM l1.pas_op_status_log WHERE appointment_id IN (SELECT appointment_id FROM s1.pas_outpatient_appointments)")
        elif key:
            con.execute(f"CREATE TABLE s1.{t} AS SELECT * FROM l1.{t} WHERE {key} IN (SELECT mrn FROM sample_mrns)")
    con.execute("""CREATE TABLE s1.mess_log AS SELECT m.* FROM l1.mess_log m WHERE m.row_key IS NULL
        OR (m.table = 'pas_patients' AND m.row_key IN (SELECT mrn FROM s1.pas_patients))
        OR (m.table = 'ed_attendances' AND m.row_key IN (SELECT uec_activity_identifier FROM s1.ed_attendances))
        OR (m.table = 'pas_outpatient_appointments' AND m.row_key IN (SELECT appointment_id FROM s1.pas_outpatient_appointments))
        OR (m.table = 'pas_op_status_log' AND m.mess_id <> 'M-BOUNCE-03' AND m.row_key IN (SELECT appointment_id FROM s1.pas_outpatient_appointments))
        OR (m.table = 'pas_referrals' AND m.row_key IN (SELECT referral_id FROM s1.pas_referrals))
        OR (m.table = 'ris_imaging' AND m.row_key IN (SELECT accession_number FROM s1.ris_imaging))
        OR (m.table = 'endo_procedures' AND m.row_key IN (SELECT ProcID FROM s1.endo_procedures))
        OR (m.table = 'pas_adt_events' AND m.row_key IN (SELECT CAST(message_id AS VARCHAR) FROM s1.pas_adt_events))""")
    for t in [r[0] for r in con.execute("SELECT table_name FROM information_schema.tables WHERE table_schema = 'l1' AND table_name LIKE 'ref_%'").fetchall()]:
        con.execute(f"CREATE TABLE s1.{t} AS SELECT * FROM l1.{t}")
    con.execute("CREATE SCHEMA s_truth")
    con.execute("CREATE TABLE s_truth.spells AS SELECT * FROM truth.spells WHERE mrn IN (SELECT mrn FROM sample_mrns) OR visit_number IN (SELECT visit_number FROM s1.pas_adt_events)")
    con.execute("CREATE TABLE s_truth.stays AS SELECT * FROM truth.stays WHERE visit_number IN (SELECT visit_number FROM s_truth.spells)")
    con.execute("CREATE TABLE s_truth.ed_admitted AS SELECT * FROM truth.ed_admitted WHERE uec_activity_identifier IN (SELECT uec_activity_identifier FROM s1.ed_attendances)")
    con.execute("CREATE TABLE s_truth.mrn_aliases AS SELECT * FROM truth.mrn_aliases WHERE mrn IN (SELECT mrn FROM sample_mrns)")
    con.execute("CREATE TABLE s_truth.imaging_links AS SELECT * FROM truth.imaging_links WHERE accession_number IN (SELECT accession_number FROM s1.ris_imaging)")
    con.execute("CREATE TABLE s_truth.endoscopy_links AS SELECT * FROM truth.endoscopy_links WHERE ProcID IN (SELECT ProcID FROM s1.endo_procedures)")
    # the same SQL runs on the sample schema
    con.execute("DROP SCHEMA derived CASCADE"); con.execute("DROP SCHEMA agg CASCADE")
    manifest["sample"] = build_layers(con, out / "sample", base, "sample", layer1_tables, partition=False, src="s1")
    n, files = write_parquet(con, "s1", "mess_log", out / "sample" / "answers", None)
    manifest["sample"]["answers/mess_log"] = {"rows": n, "files": file_entries(files, base)}
    for t in [r[0] for r in con.execute("SELECT table_name FROM information_schema.tables WHERE table_schema = 's_truth'").fetchall()]:
        n, files = write_parquet(con, "s_truth", t, out / "sample" / "answers" / "truth", None)
        manifest["sample"][f"answers/truth/{t}"] = {"rows": n, "files": file_entries(files, base)}

    # ---- CSV zip of the sample ----
    log("sample: csv zip")
    zpath = out / "sample" / "sample-csv.zip"
    with zipfile.ZipFile(zpath, "w", zipfile.ZIP_DEFLATED) as z:
        for key, entry in manifest["sample"].items():
            for f in entry["files"]:
                pq = base / f["path"]
                csvp = pq.with_suffix(".csv")
                con.execute(f"COPY (SELECT * FROM read_parquet('{pq}')) TO '{csvp}' (FORMAT CSV, HEADER)")
                z.write(csvp, arcname=key + ".csv"); csvp.unlink()
    manifest["sample"]["sample-csv.zip"] = {"files": file_entries([zpath], base), "note": "the same tables as CSV, for tools that cannot read Parquet; the Parquet files are canonical"}
    manifest["totals"] = {"full_bytes": sum(f["bytes"] for e in manifest["full"].values() for f in e["files"]),
                          "sample_bytes": sum(f["bytes"] for e in manifest["sample"].values() for f in e["files"])}
    (out / "manifest.json").write_text(json.dumps(manifest, indent=1))
    log("previews for the data viewer")
    import preview
    preview.write_previews(out)
    log("erd.json for the ERD page")
    import erd
    erd.write_erd(out)
    log("done; full", round(manifest["totals"]["full_bytes"] / 1e6), "MB, sample", round(manifest["totals"]["sample_bytes"] / 1e6), "MB")


if __name__ == "__main__":
    main()
