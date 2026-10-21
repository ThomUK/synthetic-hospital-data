#!/usr/bin/env python3
"""Build erd.json for the ERD page from the published data, so the diagram
stays in sync with what is actually there.

    generator/erd.py <data_dir>/<version>            # e.g. data/v2

Columns and types are read from the sample Parquet files, row counts from
manifest.json, and lineage (which tables each derived or aggregate table is
built from) is parsed from the SQL in sql/. Relationships are inferred by
naming convention (ALIASES map column names to key concepts, CONCEPTS say
which table holds each concept's key) and then verified against the data:
every candidate link is measured as the share of the child column's values
that exist in the parent key. Links that match nearly completely are drawn
as keys, partial matches are drawn as fuzzy links with the measured rate,
and links below MIN_RATE are dropped (listed under "rejected"). The only
hand-maintained inputs are the alias and concept lists, the primary keys
and the mess-catalogue notes below.
"""
import datetime as dt
import json
import re
import sys
from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parent.parent
SQL = ROOT / "sql"
KEY_RATE = 0.995     # at or above: a key link
MIN_RATE = 0.05      # below: not a link

# Primary keys. Checked for uniqueness in the sample at build time.
KEYS = {
    "layer1/pas_patients": ["mrn"], "layer1/pas_adt_events": ["message_id"], "layer1/ed_attendances": ["uec_activity_identifier"],
    "layer1/ed_status_log": ["log_id"], "layer1/pas_referrals": ["referral_id"], "layer1/pas_outpatient_appointments": ["appointment_id"],
    "layer1/pas_op_status_log": ["log_id"], "layer1/ris_imaging": ["accession_number"], "layer1/endo_procedures": ["ProcID"],
    "reference/sites": ["site_code"], "reference/wards": ["ward_id"], "reference/beds": ["bed_id"], "reference/specialties": ["tfc"],
    "reference/consultants": ["consultant_code"], "reference/clinics": ["clinic_code"], "reference/exam_catalogue": ["exam_code"],
    "reference/ecds_codes": ["code_set", "snomed_code"], "reference/admission_method": ["code"], "reference/admission_source": ["code"],
    "reference/discharge_destination": ["code"], "reference/discharge_method": ["code"], "reference/attendance_status": ["code"],
    "reference/patient_source_setting": ["code"],
    "derived/patients": ["person_id"], "derived/patient_identifiers": ["person_id", "source", "identifier"], "derived/mrn_map": ["mrn"],
    "derived/spells": ["provspno"], "derived/episodes": ["epikey"], "derived/ward_stays": ["provspno", "stay_seq"],
    "derived/ed_attendances": ["aekey"], "derived/op_appointments": ["attendkey"], "derived/rtt_pathways": ["rtt_pathway_id"],
    "derived/imaging_exams": ["accession_number"], "derived/endoscopy_procedures": ["proc_id"], "derived/ref_ward_names": ["raw"],
    "aggregate/midnight_census": ["census_date", "site_code", "ward_id"], "aggregate/daily_flow": ["flow_date", "site_code", "tretspef"],
    "aggregate/ae_monthly": ["month", "site_code", "department_type"], "aggregate/apc_monthly": ["month", "site_code", "tretspef", "admission_group"],
    "aggregate/op_monthly": ["month", "site_code", "tretspef"], "aggregate/dm01_snapshot": ["month_end", "test"],
    "aggregate/did_extract": ["ris_accession_number"], "aggregate/did_monthly": ["month", "modality", "source_setting"],
    "aggregate/rtt_incomplete": ["month_end", "tretspef"], "aggregate/endoscopy_monthly": ["month", "site_code", "proc_type", "category", "dm01_category"],
    "answers/mess_log": ["mess_row"], "answers/truth/spells": ["visit_number"], "answers/truth/stays": ["visit_number", "seq"],
    "answers/truth/ed_admitted": ["uec_activity_identifier"], "answers/truth/mrn_aliases": ["alias_mrn"],
    "answers/truth/imaging_links": ["accession_number"], "answers/truth/endoscopy_links": ["ProcID"],
}

# Column name -> key concept. A column not listed here is never a link.
ALIASES = {
    "mrn": "mrn", "prior_mrn": "mrn", "alias_mrn": "mrn", "after_merge": "mrn", "person_mrn": "mrn", "mrn_as_recorded": "mrn", "HospNo": "mrn",
    "nhs_number": "nhs_number", "NHSNo": "nhs_number",
    "visit_number": "spell", "provspno": "spell",
    "person_id": "person",
    "referral_id": "referral",
    "appointment_id": "appointment", "attendkey": "appointment",
    "uec_activity_identifier": "ed_attendance", "aekey": "ed_attendance",
    "accession_number": "exam", "ris_accession_number": "exam",
    "ProcID": "procedure", "proc_id": "procedure",
    "rtt_pathway_id": "rtt",
    "epikey": "episode",
    "local_patient_identifier": "ed_patient", "ris_patient_id": "ris_patient", "PatientRef": "endo_patient", "vendor_patient_ref": "endo_patient",
    "site_code": "site", "sitetret": "site", "provider_site_code": "site", "site_of_treatment": "site", "Site": "site",
    "ward_id": "ward_id", "ward": "ward_name",
    "consultant_code": "consultant", "consultant_first": "consultant", "consultant_last": "consultant", "referrer_code": "consultant", "reporter_code": "consultant", "Endoscopist": "consultant",
    "clinic_code": "clinic",
    "specialty_code": "specialty", "tfc": "specialty", "tretspef": "specialty", "tretspef_first": "specialty", "tretspef_last": "specialty",
    "tfc_decision_to_admit": "specialty", "specialty_first": "specialty", "specialty_last": "specialty",
    "nicip_code": "exam_code", "exam_code": "exam_code", "imaging_code_nicip": "exam_code",
    "admission_method": "admission_method", "admimeth": "admission_method",
    "admission_source": "admission_source", "admisorc": "admission_source",
    "discharge_destination": "discharge_destination", "disdest": "discharge_destination",
    "discharge_method": "discharge_method", "dismeth": "discharge_method",
    "attendance_status": "attendance_status",
    "patient_source_setting": "patient_source_setting",
}

# Key concept -> where its key lives, in priority order. A child links to the
# first candidate in its own layer, else to the first reference candidate;
# the answers tables describe layer-1 entities, so they also fall back to
# layer 1.
CONCEPTS = {
    "mrn": [("layer1/pas_patients", "mrn"), ("derived/mrn_map", "mrn")],
    "nhs_number": [("layer1/pas_patients", "nhs_number"), ("derived/patients", "nhs_number")],
    "spell": [("layer1/pas_adt_events", "visit_number"), ("derived/spells", "provspno"), ("answers/truth/spells", "visit_number")],
    "person": [("derived/patients", "person_id")],
    "referral": [("layer1/pas_referrals", "referral_id")],
    "appointment": [("layer1/pas_outpatient_appointments", "appointment_id"), ("derived/op_appointments", "attendkey")],
    "ed_attendance": [("layer1/ed_attendances", "uec_activity_identifier"), ("derived/ed_attendances", "aekey"), ("answers/truth/ed_admitted", "uec_activity_identifier")],
    "exam": [("layer1/ris_imaging", "accession_number"), ("derived/imaging_exams", "accession_number"), ("answers/truth/imaging_links", "accession_number")],
    "procedure": [("layer1/endo_procedures", "ProcID"), ("derived/endoscopy_procedures", "proc_id"), ("answers/truth/endoscopy_links", "ProcID")],
    "rtt": [("layer1/pas_referrals", "rtt_pathway_id"), ("derived/rtt_pathways", "rtt_pathway_id")],
    "episode": [("derived/episodes", "epikey")],
    "ed_patient": [("layer1/ed_attendances", "local_patient_identifier")],
    "ris_patient": [("layer1/ris_imaging", "ris_patient_id")],
    "endo_patient": [("layer1/endo_procedures", "PatientRef")],
    "site": [("reference/sites", "site_code"), ("reference/sites", "site_name")],
    "ward_id": [("reference/wards", "ward_id")],
    "ward_name": [("reference/wards", "ward_name")],
    "consultant": [("reference/consultants", "consultant_code")],
    "clinic": [("reference/clinics", "clinic_code")],
    "specialty": [("reference/specialties", "tfc")],
    "exam_code": [("reference/exam_catalogue", "exam_code")],
    "admission_method": [("reference/admission_method", "code")],
    "admission_source": [("reference/admission_source", "code")],
    "discharge_destination": [("reference/discharge_destination", "code")],
    "discharge_method": [("reference/discharge_method", "code")],
    "attendance_status": [("reference/attendance_status", "code")],
    "patient_source_setting": [("reference/patient_source_setting", "code")],
}

# Mess-catalogue notes shown on fuzzy links, keyed by (child table, column).
NOTES = {
    ("layer1/ed_attendances", "mrn"): "M-ED-01: null when the interface failed to match (4%). M-ED-02: wrong person matched (0.1%).",
    ("layer1/ed_attendances", "nhs_number"): "M-ED-07: typed by hand with spaces on 2% of rows.",
    ("layer1/ris_imaging", "mrn"): "From the PAS feed; see M-RIS-06 for untraced numbers.",
    ("layer1/ris_imaging", "nhs_number"): "M-RIS-06: untraced numbers that differ from the PAS by one digit (1%).",
    ("layer1/endo_procedures", "HospNo"): "M-EN-02: blank for screening patients registered by the hub. M-EN-05: no spell or appointment key, linkage is by NHS number and date.",
    ("layer1/endo_procedures", "NHSNo"): "M-EN-02: written with spaces.",
    ("layer1/endo_procedures", "Site"): "M-EN-03: free text in four spellings; matches the site name only after normalising.",
    ("layer1/pas_adt_events", "ward"): "M-PAS-09: ward name drift, the same ward typed several ways and renamed mid-period.",
    ("layer1/pas_adt_events", "prior_mrn"): "M-PAS-07: on A40 merges only, the MRN being merged away.",
    ("layer1/pas_adt_events", "visit_number"): "Parent is the spell implied by the A01 event; the PAS has no spell table.",
    ("layer1/pas_outpatient_appointments", "referral_id"): "A few appointments cite a referral that is not in the extract (booked against a referral received before the window).",
    ("derived/ed_attendances", "mrn_as_recorded"): "The MRN as the ED system sent it, before MPI resolution; person_id is the resolved link.",
    ("derived/imaging_exams", "mrn_as_recorded"): "The MRN as the RIS sent it, before MPI resolution.",
    ("derived/endoscopy_procedures", "mrn_as_recorded"): "HospNo as exported, before MPI resolution.",
    ("derived/op_appointments", "mrn_as_recorded"): "The MRN on the appointment row, before merges were applied.",
}

# Display groups within a layer, by table name pattern (first match wins).
GROUPS = [
    (r"^layer1/pas_", "PAS"), (r"^layer1/ed_", "ED system"), (r"^layer1/ris_", "Radiology (RIS)"), (r"^layer1/endo_", "Endoscopy vendor"),
    (r"^derived/(patients|patient_identifiers|mrn_map)$", "Master patient index"),
    (r"^derived/(spells|episodes|ward_stays|ref_ward_names)$", "Admitted care"),
    (r"^derived/ed_", "Emergency care"), (r"^derived/(op_appointments|rtt_pathways)$", "Outpatients and RTT"),
    (r"^derived/imaging_", "Imaging"), (r"^derived/endoscopy_", "Endoscopy"),
    (r"^aggregate/(midnight_census|daily_flow|apc_monthly)$", "Admitted care"), (r"^aggregate/ae_", "Emergency care"),
    (r"^aggregate/(op_monthly|rtt_incomplete)$", "Outpatients and RTT"), (r"^aggregate/(did_|dm01)", "Diagnostics"), (r"^aggregate/endoscopy_", "Endoscopy"),
    (r"^answers/mess_log$", "Mess log"), (r"^answers/truth/", "Truth"),
    (r"^reference/(sites|wards|beds)$", "Estate"), (r"^reference/(specialties|consultants|clinics)$", "Services"),
    (r"^reference/", "Code lists"),
]


def layer_of(key):
    return key.split("/")[0]


def group_of(key):
    for pat, g in GROUPS:
        if re.search(pat, key):
            return g
    return "Other"


def lineage():
    """Which published tables each derived/aggregate table is built from, parsed from the SQL."""
    stmts = {}
    for d in ("derive", "aggregate"):
        for f in sorted((SQL / d).glob("*.sql")):
            text = f.read_text()
            for m in re.finditer(r"CREATE\s+OR\s+REPLACE\s+TABLE\s+(derived|agg)\.(\w+)\s+AS(.*?);", text, re.S | re.I):
                schema, name, body = m.group(1), m.group(2), m.group(3)
                refs = set()
                for s, t in re.findall(r"\b(l1|derived|truth|agg)\.(\w+)", body):
                    refs.add((s, t))
                stmts[(schema, name)] = refs
    def published(schema, t):
        return {"l1": "layer1/", "derived": "derived/", "agg": "aggregate/", "truth": "answers/truth/"}[schema] + t
    out = {}
    for (schema, name), refs in stmts.items():
        if name.startswith("_"):
            continue
        seen, stack, srcs = set(), list(refs), set()
        while stack:
            s, t = stack.pop()
            if (s, t) in seen or (s, t) == (schema, name):
                continue
            seen.add((s, t))
            if t.startswith("_"):
                stack.extend(stmts.get((s, t), ()))
            elif s == "l1" and t.startswith("ref_"):
                srcs.add("reference/" + t[4:])
            else:
                srcs.add(published(s, t))
        out[published(schema, name)] = sorted(srcs)
    return out


NORM = "lower(regexp_replace(CAST({x} AS VARCHAR), '[^A-Za-z0-9]', '', 'g'))"


def measure(con, child, col, parent, pcol):
    """Share of the child column's non-null values found in the parent column,
    raw first and, if that fails, after normalising case and punctuation
    (which is how a hand-typed NHS number or a free-text site still links)."""
    n_nonnull, n_match, n_all = con.execute(
        f'SELECT count("{col}"), count(*) FILTER (WHERE "{col}" IN (SELECT "{pcol}" FROM "{parent}" WHERE "{pcol}" IS NOT NULL)), count(*) FROM "{child}"').fetchone()
    if n_nonnull == 0:
        return None
    rate, normalised = n_match / n_nonnull, False
    if rate < KEY_RATE:
        cx, px = NORM.format(x=f'"{col}"'), NORM.format(x=f'"{pcol}"')
        n_norm = con.execute(f'SELECT count(*) FILTER (WHERE {cx} IN (SELECT {px} FROM "{parent}" WHERE "{pcol}" IS NOT NULL)) FROM "{child}" WHERE "{col}" IS NOT NULL').fetchone()[0]
        if n_norm / n_nonnull > rate:
            rate, normalised = n_norm / n_nonnull, True
    return {"rate": rate, "null_rate": 1 - n_nonnull / n_all if n_all else 0, "normalised": normalised}


def build(version_dir):
    version_dir = Path(version_dir)
    m = json.load(open(version_dir / "manifest.json"))
    con = duckdb.connect()
    tables = {}
    for key, v in m["sample"].items():
        if "rows" not in v:
            continue
        rel = Path(*Path(v["files"][0]["path"]).parts[1:])
        path = version_dir / rel
        con.execute(f"CREATE VIEW \"{key}\" AS SELECT * FROM read_parquet('{path}')")
        cols = [{"name": d[0], "type": str(d[1])} for d in con.execute(f'SELECT * FROM "{key}" LIMIT 0').description]
        pk = [c for c in KEYS.get(key, []) if c in {x["name"] for x in cols}]
        pk_unique = None
        if pk:
            cols_sql = ", ".join(f'"{c}"' for c in pk)
            n, d = con.execute(f'SELECT count(*), count(DISTINCT ({cols_sql})) FROM "{key}"').fetchone()
            pk_unique = (n == d)
        tables[key] = {"layer": layer_of(key), "group": group_of(key), "rows_sample": v["rows"],
                       "rows_full": m["full"].get(key, {}).get("rows"), "pk": pk, "pk_unique": pk_unique, "columns": cols, "sources": []}
    for t, srcs in lineage().items():
        if t in tables:
            tables[t]["sources"] = [s for s in srcs if s in tables]

    links, rejected = [], []
    for key, t in tables.items():
        lay = layer_of(key)
        for c in t["columns"]:
            concept = ALIASES.get(c["name"])
            if not concept:
                continue
            cands = CONCEPTS[concept]
            parent = next(((pt, pc) for pt, pc in cands if layer_of(pt) == lay and pt in tables), None)
            if parent is None:
                parent = next(((pt, pc) for pt, pc in cands if layer_of(pt) == "reference" and pt in tables), None)
            if parent is None and lay == "answers":
                parent = next(((pt, pc) for pt, pc in cands if layer_of(pt) == "layer1" and pt in tables), None)
            if parent is None or (parent[0] == key and parent[1] == c["name"]):
                continue
            # a concept may offer several columns on the same parent (site code or site name): take the best match
            best = None
            for pt, pc in [parent] + [(pt, pc) for pt, pc in cands if pt == parent[0] and pc != parent[1] and pt in tables]:
                meas = measure(con, key, c["name"], pt, pc)
                if meas and (best is None or meas["rate"] > best["rate"]):
                    best = {"pt": pt, "pc": pc, **meas}
            if best is None:
                rejected.append({"from": key, "column": c["name"], "to": parent[0], "to_column": parent[1], "reason": "no values"})
                continue
            if best["rate"] < MIN_RATE:
                rejected.append({"from": key, "column": c["name"], "to": best["pt"], "to_column": best["pc"], "reason": f"match rate {best['rate']:.3f}"})
                continue
            kind = "key" if best["rate"] >= KEY_RATE and not best["normalised"] else "fuzzy"
            if (key, c["name"]) in NOTES and best["rate"] < 1:
                kind = "fuzzy"
            one_to_one = t["pk"] == [c["name"]]
            links.append({"from": key, "column": c["name"], "to": best["pt"], "to_column": best["pc"], "concept": concept, "kind": kind,
                          "match_rate": round(best["rate"], 4), "null_rate": round(best["null_rate"], 4), "normalised": best["normalised"],
                          "one_to_one": one_to_one, "note": NOTES.get((key, c["name"]), "")})
    return {"version": m["version"], "built_at": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "basis": "columns and types from the sample Parquet; link match rates measured on the sample; row counts from manifest.json; lineage parsed from sql/",
            "thresholds": {"key_rate": KEY_RATE, "min_rate": MIN_RATE},
            "tables": tables, "links": links, "rejected": rejected}


def write_erd(version_dir):
    e = build(version_dir)
    out = Path(version_dir) / "erd.json"
    out.write_text(json.dumps(e, indent=1))
    return e


if __name__ == "__main__":
    e = write_erd(sys.argv[1])
    print(f"{len(e['tables'])} tables, {len(e['links'])} links ({sum(l['kind']=='fuzzy' for l in e['links'])} fuzzy), {len(e['rejected'])} rejected")
    bad = [k for k, t in e["tables"].items() if t["pk"] and not t["pk_unique"]]
    print("non-unique primary keys:", bad or "none")
    print("tables without a primary key:", [k for k, t in e["tables"].items() if not t["pk"]] or "none")
