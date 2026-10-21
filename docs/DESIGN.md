# Design: synthetic-hospital-data

Design document for review before any code is written. Everything marked
**assumption** is a number or rule I chose because no supplied document
gives it; everything marked **(source)** is taken from a document in
`docs/sources/` and quoted in `CALIBRATION.md`. Correct either and the
generator follows.

## 1. Purpose and principles

- A fixed, versioned, seeded synthetic dataset for one fictional acute trust
  of top-10 national scale, queryable with SQL from a browser page, from R
  and from Python, with no server.
- Three layers, each built from the one below by SQL that is checked in and
  readable, so the information lost at each step is demonstrable:
  1. **Source extracts**: what the trust's systems actually emit. Event-level,
     one table per system, deliberately messy.
  2. **Derived entities**: spells, episodes, ward stays, attendances,
     appointments, exams, procedures. What an analyst in the trust sees,
     shaped like HES and ECDS so the field names are familiar.
  3. **Aggregates**: the counts, snapshots and performance figures that leave
     the trust, shaped like the national returns (A&E monthly, DM01, DID,
     RTT, HES activity).
- Flow only. No diagnoses, procedure codes, observations or results in v1.
- Mess is injected on purpose, at known rates, and every injected row is
  recorded in a hidden answers table (`mess_log`). See `MESS-CATALOGUE.md`.
  Two source systems (ED and outpatients) ship with their audit trails so
  that administrative "bouncing", a status set, unset and reset within
  minutes, is visible as events and not just as a final value.
- Reproducible: one seed, one manifest, committed output. Re-running the
  generator with the same seed and version gives byte-identical Parquet.

## 2. The fictional trust

**Fake NHS Trust**, organisation code `RZ9` (chosen to
look like an ODS code without being one). A large teaching trust: around
1,500 beds, activity at the scale of the 8th to 10th largest imaging
providers in England **(source: DID Table 11)**.

Two sites:

| Site code | Name | Beds | Role |
| --- | --- | --- | --- |
| `RZ901` | Hospital A | ~1,100 | Main site. The only emergency department (Type 1) plus a co-located UTC stream and SDEC. All non-elective admissions, every medical specialty, trauma, emergency and complex surgery, critical care, children's services, and a large elective programme of its own. Two CT scanners dedicated to the ED and inpatients ("hot") plus two elective CT scanners; three MRI scanners; six ultrasound rooms. |
| `RZ902` | Hospital B | ~400 | Predominantly elective: day surgery, elective orthopaedics, ophthalmology, ENT, urology, most routine outpatients, a large share of routine MRI and endoscopy, and a community diagnostic centre (CDC) wing. One CT, two MRI scanners and four ultrasound rooms in the CDC. A small number of non-elective admissions arise from elective patients deteriorating on site; anything serious is transferred to RZ901. |

One ED at a top-10 trust is unusual (most of the real top ten run two or
more) and is a deliberate simplification so that ED flow has one shape.

### 2.1 Specialties and where they work

Treatment function codes (TFC) from the NHS Data Dictionary, reusing the
`nhs-specialties/` reference data in this repo. "IP" is inpatient beds,
"DC" day case, "OP" outpatients. Some specialties are split across sites,
some are not.

| TFC | Specialty | RZ901 Hospital A | RZ902 Hospital B |
| --- | --- | --- | --- |
| 180 | Emergency Medicine | ED, UTC, SDEC | – |
| 300 | General Internal Medicine | AMU, IP, OP | – |
| 430 | Geriatric Medicine | IP, frailty unit, OP | OP |
| 320 | Cardiology | CCU, IP, OP, cath lab | OP, echo |
| 340 | Respiratory Medicine | IP, OP | OP |
| 301 | Gastroenterology | IP, OP, endoscopy | OP, endoscopy |
| 361 | Renal Medicine | IP, OP, dialysis | – |
| 400 | Neurology | IP, OP | OP |
| 100 | General Surgery | emergency + complex IP, OP | DC, elective IP, OP |
| 104 | Colorectal Surgery | emergency + complex IP, OP | DC, OP, endoscopy |
| 107 | Vascular Surgery | IP, OP | – |
| 110 | Trauma & Orthopaedics | trauma IP, OP | elective IP, DC, OP |
| 101 | Urology | emergency IP, OP | elective IP, DC, OP |
| 130 | Ophthalmology | emergency eye clinic | DC, OP |
| 120 | ENT | emergency IP | DC, elective IP, OP |
| 502 | Gynaecology | IP, OP | DC, OP |
| 420 | Paediatrics | IP, OP, children's ED stream | – |
| 330 | Dermatology | – | OP |
| 410 | Rheumatology | OP | OP |
| 192 | Critical Care Medicine | ICU, HDU | – |

Obstetrics and mental health are out of scope for v1 (birth and delivery
episodes bring their own CDS types; mental health is a different data model).

### 2.2 Wards

About 60 wards are generated from a reference table of site, specialty, bed
count and canonical name. Rather than list all sixty here, the generator's
`ref_wards` seed table holds them. A companion `ref_beds` table holds one
row per bed space (`bed_id`, site, ward, bay, label, `bed_type`): inpatient
wards are beds in bays of six plus side rooms, critical care is numbered
bed spaces, day units mix trolleys, recliners and chairs with a few beds,
the ED is resus and majors trolleys with minors and fit-to-sit chairs, SDEC
is chairs and trolleys, and the discharge lounge is mostly chairs. The bed
types are `bed`, `recliner`, `trolley` and `chair`. The categories are:

| Site | Ward group | Count | Beds each | Notes |
| --- | --- | --- | --- | --- |
| RZ901 | ED, UTC, SDEC, children's ED | 4 | – / 20 / 16 / – | Locations, not bed wards, except SDEC. Admitted patients board in ED. |
| RZ901 | AMU (2 wards) and SAU | 3 | 40 / 40 / 20 | Most non-elective admissions land here first. |
| RZ901 | Medical specialty wards | 14 | 24–32 | Cardiology, CCU, respiratory (2), gastro, renal, neurology, general medicine (4), frailty (3). |
| RZ901 | Surgical wards | 8 | 24–28 | General and colorectal (3), vascular, trauma (2), urology/gynae mixed, ENT/max-fax. |
| RZ901 | Critical care | 2 | 24 / 12 | ICU, HDU. Locations with level-of-care flags. |
| RZ901 | Children's wards | 2 | 24 / 16 | |
| RZ901 | Elective surgical wards | 4 | 24–28 | For the main site's own elective programme. |
| RZ901 | Escalation wards | 3 | 0–24 | Open in winter months only; one opens on a different date each year. |
| RZ901 | Discharge lounge | 1 | – | Location with no overnight stays. |
| RZ902 | Day surgery and treatment units | 4 | 20–30 | |
| RZ902 | Elective orthopaedic wards | 3 | 28–32 | |
| RZ902 | Elective surgical wards | 3 | 20–28 | General, urology, ENT. |
| RZ902 | Eye unit, endoscopy recovery, CDC | 3 | 8 / 12 / – | |

Names are *not* stable in the source data (see the mess catalogue): several
wards are renamed mid-period, escalation wards open and close, and names
appear with inconsistent casing and spacing.

## 3. Time range and population

- **Activity window:** 1 April 2023 to 31 March 2026 inclusive. Three full
  financial years, enough for monthly time series and seasonality, and the
  period for which national A&E and RTT monthly figures were supplied
  **(source)**.
- **Edges are honest.** Some spells are open at 1 April 2023 (their admission
  events exist, dated before the window) and some are open at 31 March 2026
  (no discharge yet). Open spells at the window edges are what make the
  midnight census differ from admissions minus discharges.
- **Population: 800,000 patients** who had at least one contact in the
  window. **Assumption**, derived as follows: a trust of this scale sees
  roughly 265,000 ED and UTC attendances, 250,000 spells and 1.5 million
  attended outpatient appointments a year; with realistic repeat rates (an ED attender averages
  about 1.5 attendances a year, an outpatient about 3 appointments a year)
  that is roughly 500,000 distinct patients a year and about 800,000 over
  three years. The original plan of 50,000 patients would mean every patient
  attending ED eleven times, so it had to rise with the trust size.
- Age and sex drawn from the pooled teaching-trust admitted-care age
  profile and the DID imaging age bands **(source: HES APC provider table,
  DID release)**; the ED and outpatient profiles are **assumptions**
  shaped from those.
- Some patients die during the window (in hospital or notified later), so
  dates of death exist and some are recorded after activity that should have
  stopped.

### 3.1 Identifiers

| Identifier | Format | Owner | Notes |
| --- | --- | --- | --- |
| NHS number | `fake_` + 10 digits, the 10 digits having a valid modulus-11 check digit | national | The full 10 digits are kept so the DID validation rule ("must pass the Modulus 11 check digit test") would pass on the digits, and the prefix makes it unmistakably fake. Stored as text. |
| NHS number status | DID / ECDS `NHS NUMBER STATUS INDICATOR CODE` (01 traced, 02 untraced, etc.) | each system | Carried on ED and RIS rows; mostly 01. |
| Hospital number (MRN) | `T` + 7 digits | PAS | The trust's master identifier. Both sites share one PAS. |
| ED system ID | `E` + 8 digits | ED system | ECDS `LOCAL PATIENT IDENTIFIER (EXTENDED)` for the ED; mapped to MRN by an interface that sometimes fails. |
| RIS patient ID | integer | Radiology Information System | |
| RIS accession number | `RZ901-` or `RZ902-` + 8 digits | RIS | DID: "must be unique within site code". Uniqueness is only within site, which is itself a lesson. |
| Endoscopy system ID | `EN-` + 6 digits | endoscopy vendor | |

A patient can have more than one MRN (duplicates later merged via an A40
event) and the departmental systems hold their own identifiers, so joining
across systems is a real task, not a foreign-key lookup. The master patient
index in layer 2 resolves this.

## 4. Layer 1: source extracts

One table per source system, with that system's own conventions. Column
names deliberately differ in style between systems.

### 4.1 `pas_adt_events` — the PAS event log

An HL7 v2 ADT-style event stream. This is the single most important table:
everything in the inpatient domain is derived from it.

| Column | Meaning |
| --- | --- |
| `message_id` | sequence number in the order the message was received |
| `event_type` | `A04` register (ED or outpatient-to-admit pre-registration), `A01` admit, `A02` transfer, `A03` discharge, `A08` update (consultant or specialty change creates a new episode; also used for demographic corrections), `A11` cancel admit, `A13` cancel discharge, `A40` merge patient |
| `event_datetime` | when the thing happened (effective time) |
| `recorded_datetime` | when the message was sent; lags `event_datetime` by minutes to days |
| `mrn` | hospital number |
| `visit_number` | PAS spell identifier (becomes HES `PROVSPNO`) |
| `site_code` | `RZ901` or `RZ902` |
| `ward` | ward name as typed in the PAS at the time |
| `bed` | bay/bed label, often blank |
| `consultant_code` | fictional GMC-style code |
| `specialty_code` | TFC (HES `TRETSPEF`); main specialty (HES `MAINSPEF`) is on the consultant reference table |
| `admission_method` | HES `ADMIMETH` codes **(source)**: 11 waiting list, 12 booked, 13 planned, 21 ED, 22 GP, 23 bed bureau, 24 consultant clinic, 25 mental health crisis team, 28 other emergency, 2A ED of another provider, 2B transfer of an admitted patient from another hospital, 2D other emergency admission, 31/32 maternity (unused), 81 transfer from another provider (non-emergency). On A01 only. |
| `admission_source` | HES `ADMISORC` codes **(source)**: 19 usual residence, 29 temporary residence, 51 NHS other provider ward, 54 care home, etc. On A01 only. |
| `intended_management` | HES `INTMANIG`: 1 overnight, 2 not overnight. On A01 only. Lets the day-case versus inpatient distinction be derived rather than stated. |
| `patient_class` | HES `CLASSPAT`: 1 ordinary admission, 2 day case, 3 regular day attender |
| `decision_to_admit_date` | HES `ELECDATE`, elective admissions only |
| `discharge_method` | HES `DISMETH`: 1 clinical discharge, 4 died, 6 self-discharge, 7 discharged by relative. On A03 only. |
| `discharge_destination` | HES `DISDEST`: 19 home, 54 care home, 51 other NHS provider, 79 died, etc. On A03 only. |
| `discharge_ready_date` | HES `DISREADYDATE`, populated for a minority of long-stay patients. On A03 only. |
| `prior_mrn` | on A40 only: the MRN being merged away |

About 9 events per ordinary admission and 3 per day case. Volume: 250,000
spells a year excluding maternity, of which 95,000 emergency (46,000 via the
ED and 49,000 by other routes), 140,000 waiting list or booked and 15,000
planned; 90,000 are day cases and there are about 310,000 consultant
episodes **(source: HES APC provider table 2025/26, Nottingham and Oxford;
A&E provider CSV for the ED split)**. That is about 3.4 events per spell, 0.9
million events a year and 2.6 million over three years (measured on the
clean generator's full-scale run).

### 4.2 `ed_attendances` — ED system export

ECDS v4-shaped **(source: ECDS ETOS v4.0.8)**, one row per attendance, from
a different system with its own patient ID. Column names follow the ECDS
XML element names in snake case so the mapping to the national dataset is
one-to-one.

| Column | ECDS item |
| --- | --- |
| `uec_activity_identifier` | URGENT AND EMERGENCY CARE ACTIVITY IDENTIFIER |
| `local_patient_identifier` | LOCAL PATIENT IDENTIFIER (EXTENDED), the `E` number |
| `nhs_number`, `nhs_number_status_indicator_code` | as the ED system holds them |
| `mrn` | not an ECDS item; populated by the PAS interface, nullable |
| `site_of_treatment` | ORGANISATION SITE IDENTIFIER (OF TREATMENT), always `RZ901` |
| `uec_activity_type` | ED (Type 1), UTC stream, SDEC |
| `arrival_mode` | ECDS arrival mode: own transport / walk-in, public transport, emergency road ambulance, ambulance with medical escort, non-emergency ambulance, helicopter, police, custodial |
| `attendance_category` | ECDS attendance category (first unplanned, follow-up unplanned, follow-up planned, etc.) |
| `attendance_source` | ECDS attendance source group and item: self, GP, NHS 111, out-of-hours GP, ambulance service, ED of another provider, outpatient/SDEC, inpatient ward, community nurse, police, etc. |
| `activity_start_datetime` | URGENT AND EMERGENCY CARE ACTIVITY START DATE AND TIME (arrival) |
| `initial_assessment_timestamp` | INITIAL ASSESSMENT TIMESTAMP (triage) |
| `acuity` | ECDS acuity 1–5: 1 immediate (resus), 2 very urgent, 3 urgent (majors), 4 standard (minors), 5 low acuity |
| `chief_complaint` | short list drawn from the ECDS chief complaint refset |
| `seen_for_treatment_timestamp` | TIMESTAMP SEEN FOR TREATMENT |
| `decided_to_admit_datetime` | DECIDED TO ADMIT DATE AND TIME, nullable |
| `tfc_decision_to_admit` | ACTIVITY TREATMENT FUNCTION CODE (DECISION TO ADMIT) |
| `clinically_ready_to_proceed_timestamp` | CLINICALLY READY TO PROCEED TIMESTAMP, nullable |
| `discharge_status` | ECDS discharge status: treatment complete; streamed to GP / UTC / SDEC / frailty; left before initial assessment; left after assessment; died in department; dead on arrival |
| `discharge_destination` | ECDS discharge destination: home, residential care, nursing care, ED short stay ward, SDEC, ward bed, operating theatre, HDU, CCU, ICU, transfer to another hospital, hospice, mortuary |
| `activity_end_timestamp` | ACTIVITY END TIMESTAMP (departure) |

Volume: 165,000 Type 1 attendances a year plus a 100,000-a-year UTC stream
in the same table **(source: September 2026 provider CSV, the single-ED
teaching trusts in the imaging top ten run 13,000–14,000 Type 1 a month)**,
of which about 28% of Type 1 are admitted **(source: national Type 1 series,
27–29.5% every month 2023–26; Nottingham 27.5%)**.

#### 4.2.1 `ed_status_log` — the tracking board audit trail

The ED system keeps an audit trail of every status change on the tracking
board, and `ed_attendances` is the last-written state. One row per change:
`uec_activity_identifier`, `status` (arrived, triaged, in cubicle, seen,
awaiting results, referred, decision to admit, ready to go, departed,
re-opened), `recorded_datetime`, `user_role` (receptionist, nurse,
clinician, bed manager). About six rows per attendance, more when the
record bounces (see M-BOUNCE-*). The timestamps in `ed_attendances` are
the *last* time each status was set, which is not always the first.

### 4.3 `pas_outpatient_appointments`

One row per appointment slot that was booked, with HES OP field semantics
**(source: HES OP ATOS)**. Columns: `appointment_id` (HES `ATTENDKEY`),
`mrn`, `referral_id`, `site_code` (`SITETRET`), `clinic_code`,
`specialty_code` (`TRETSPEF`), `consultant_code`, `appointment_datetime`
(`APPTDATE` plus time), `first_attendance` (`FIRSTATT`: 1 first face to
face, 2 follow-up face to face, 3 first telephone/video, 4 follow-up
telephone/video), `attendance_status` (`ATTENDED`: 2 cancelled by patient,
3 DNA no warning, 4 cancelled by hospital, 5 seen on time, 6 arrived late and
seen, 7 arrived late not seen), `outcome` (`OUTCOME`: discharged, timed
follow-up given, follow-up to be arranged, moved to another specialty, added
to inpatient waiting list, diagnostic requested), `priority` (`PRIORITY`: 1
routine, 2 urgent, 3 two-week wait), `referral_source` (`REFSOURC`: 03 GP,
04 ED, 05 consultant, 10 following ED attendance, 01 following emergency
admission, etc.), `booked_datetime`, `cancelled_datetime`,
`dna_date` (`DNADATE`), `staff_type` (`STAFFTYP`).

Volume: 1.5 million attended appointments a year plus 105,000 DNAs,
175,000 patient cancellations and 300,000 hospital cancellations, so about
2.1 million appointment rows a year; 34% of attendances are first
attendances, 19% are by telephone or video, half of first attendances are
GP referrals, and the median wait from GP referral to first attendance is
17 days **(source: HES OP provider table 2025/26, Nottingham and Oxford)**.

#### 4.3.1 `pas_op_status_log` — the appointment audit trail

The PAS writes an audit row every time an appointment's status or outcome
is changed, and `pas_outpatient_appointments` holds the last value. One
row per change: `appointment_id`, `field` (`attendance_status` or
`outcome`), `old_value`, `new_value`, `recorded_datetime`, `user_id`,
`workstation` (clinic reception, central booking, ward clerk, overnight
batch). About 2.5 rows per appointment on average: booked, then arrived or
DNA, then an outcome. Clinic reception closes the day's clinic in a batch
at the end of the session, so most "arrived" and "seen" rows carry the
same `recorded_datetime` an hour or more after the appointment time.

### 4.4 `pas_referrals` — the RTT skeleton

One row per referral into the trust. Columns: `referral_id`, `mrn`,
`referral_received_date` (HES `REQDATE`), `referral_source`,
`specialty_code`, `priority`, `rtt_pathway_id`, `rtt_period_start_date`,
`rtt_period_end_date` (nullable), `rtt_period_status` (HES `RTTPERSTAT`
codes: 10 first activity, 20 subsequent activity, 30 first definitive
treatment, 31/32 active monitoring, 33 DNA first appointment, 34 decision
not to treat, 35 patient declined, 36 died, 90/91/92 non-RTT). Enough to
derive incomplete-pathway snapshots with the national weeks-waiting profile,
not a full RTT implementation.

The trust's incomplete list runs at about 88,000 pathways with about
15,500 clock starts and 15,000 clock stops a month (3,000 admitted, 12,000
non-admitted) **(source: RTT provider file, Nottingham and Oxford, August
2026)**, with median wait drifting from 14–15 weeks to 11 and the
over-52-week share from 5% to 1.5% across the window, as nationally
**(source: RTT overview)**. The specialty mix of the list follows the
pooled teaching-trust profile in `CALIBRATION.md` section 3.1, including
the "other medical" and "other surgical" catch-alls.

### 4.5 `ris_imaging` — CT, MRI and ultrasound from the Radiology Information System

One structure, three modalities, three very different teams (see mess
catalogue M-CT-*, M-MR-* and M-US-*). Plain X-ray is deliberately left out:
it would add 320,000 rows a year and teach nothing the other three do not.
One row per examination request, which is richer than the DID submission
(the DID is a date-only, performed-exams-only extract of this; see the
aggregate layer).

| Column | Meaning | DID item it feeds **(source: DID Annex 2)** |
| --- | --- | --- |
| `accession_number` | `RZ90n-` + 8 digits, unique within site | RIS Accession Number (M) |
| `ris_patient_id` | RIS identifier | – |
| `nhs_number`, `nhs_number_status` | as the RIS holds them | NHS Number (M*), NHS Number Status (R) |
| `mrn` | as the RIS holds it, from the PAS feed | – |
| `modality` | `CT`, `MR` or `US` | derived from the code via Annex 1 |
| `nicip_code` | NICIP code from the Annex 1 lookup **(source)**, e.g. `CHEAC` CT head, `CABPEC` CT abdomen and pelvis with contrast, `CCHEC` CT chest with contrast, `CURIT` CT urinary tract, `CAICN` CT angiogram intracranial, `CVCLD` CT colonography, `MMRCP` MRCP, `MPROSC` MRI prostate with contrast, `MCARD` MRI heart, `MLIVEC` MRI liver with contrast, `MSHLL` MRI shoulder left, `MHIPB` MRI hips, `UABDO` US abdomen, `UPETV` US pelvis transvaginal, `UURTR` US urinary tract | Imaging Code NICIP (M) |
| `snomed_code` | the mapped SNOMED CT code, sometimes blank, sometimes the only code present | Imaging Code SNOMED CT (M, either/or) |
| `exam_description` | free text as the booking clerk typed it | – |
| `body_area` | local reference value, inconsistently filled | – (DID carries body site inside the code) |
| `priority` | emergency, urgent, two-week-wait, routine, planned | – |
| `patient_source_setting` | DID Patient Type codes **(source)**: 01 inpatient, 02 day case, 03 outpatient, 04 GP direct access, 05 A&E, 06 other health care provider, 07 other. "Based on intended management at the time of the request." | Patient Type (M) |
| `referrer_code`, `referring_organisation` | GMC-style or practice code; ODS code | Referrer (R), Referring Organisation (R) |
| `request_datetime` | when the clinician made the request | Date of Test Request (R) |
| `request_received_datetime` | when the RIS received it (order comms makes these equal; paper and phone requests do not) | Date Test Request Received (R) |
| `vetted_datetime` | radiologist, radiographer or (for ultrasound) clinical support worker vetting, nullable | – |
| `booked_datetime` | appointment time given | – |
| `scan_start_datetime`, `scan_end_datetime` | actual scanner time | Date of Test (M), date part only |
| `slot_minutes` | the slot the booking system allocated | – |
| `reported_datetime` | preliminary report | – |
| `verified_datetime` | final report authorised | Date Test Report Issued (R), date part only |
| `reporter_code` | | – |
| `status` | requested, vetted, booked, cancelled, DNA, performed, reported, verified | – (the DID has no cancellation or DNA items) |
| `cancel_reason` | nullable | – |
| `site_code` | scanner site | Provider Site Code (M) |
| `scanner_id` | `CT1`–`CT4`, `MR1`–`MR3`, `US1`–`US6` at RZ901; `CT5`, `MR4`, `MR5`, `US7`–`US10` at RZ902 | – |

**Exam catalogue.** The GIRFT radiology report **(source)** gives no slot
lengths or per-scanner throughput ("there is no clear correlation between
the amount of equipment a trust owns and its performance"), and neither does
any other supplied document, so durations remain **assumptions** from
patient-facing NHS guidance and published timing studies. What the sources
do give is the shape of the queue around each exam: see section 4.5.1.
Inpatient and ED exams run a few minutes longer than outpatient ones.

| Modality | Exam | NICIP | Typical room time (min) | Slot (min) | Share of modality | Main sources |
| --- | --- | --- | --- | --- | --- | --- |
| CT | Head | `CHEAC` | 5–10 | 10 | 30% | ED, inpatient |
| CT | Chest with contrast | `CCHEC` | 8–12 | 15 | 10% | OP, GP, inpatient |
| CT | Chest high resolution | `CHRC` | 8–12 | 15 | 2% | OP |
| CT | Abdomen and pelvis with contrast | `CABPEC` | 12–18 | 20 | 18% | ED, inpatient, OP, 2WW |
| CT | Chest/abdo/pelvis (staging) | `CCAPC` | 15–20 | 20 | 10% | OP, 2WW |
| CT | Pulmonary angiogram (CTPA) | `CPULA`* | 10–15 | 15 | 8% | ED, inpatient |
| CT | Urinary tract (renal colic) | `CURIT` | 5–10 | 10 | 6% | ED |
| CT | Angiography (intracranial, aorta, lower limb) | `CAICN`, `CAAAG`, `CALLB` | 12–18 | 20 | 5% | ED, inpatient |
| CT | Coronary angiography (CTCA) | `CCORA`* | 20–30 | 30 | 4% | OP cardiology |
| CT | Colonography | `CVCLD` | 20–30 | 30 | 3% | OP, GP, 2WW |
| CT | Guided biopsy / drainage | `CBIOPB`, `CABDOD` | 30–50 | 45 | 2% | inpatient, OP |
| CT | Spine / extremity | `CLSPI`* | 8–12 | 15 | 2% | ED, OP |
| MR | Brain | `MBRAI`* | 20–30 | 30 | 22% | OP, GP, inpatient |
| MR | Lumbar spine | `MLUSP`* | 20–30 | 30 | 20% | GP, OP |
| MR | Knee | `MKNEL`/`MKNER`* | 20–30 | 30 | 14% | GP, OP |
| MR | Whole spine | `MWSPI`* | 40–50 | 45 | 6% | inpatient, OP |
| MR | Shoulder / hip / small joint | `MSHLL`, `MSHLR`, `MHIPB` | 20–30 | 30 | 10% | GP, OP |
| MR | MRCP | `MMRCP` | 25–40 | 45 | 5% | OP, inpatient |
| MR | Prostate | `MPROSC` | 30–40 | 40 | 7% | OP, 2WW |
| MR | Pelvis (gynae) | `MPEGY` | 30–45 | 45 | 5% | OP, 2WW |
| MR | Cardiac | `MCARD` | 45–60 | 60 | 4% | OP cardiology |
| MR | Breast | `MBRSB` | 30–45 | 45 | 2% | OP |
| MR | Liver / abdomen with contrast | `MLIVEC`, `MABDOC` | 30–40 | 45 | 5% | OP, inpatient |
| US | Abdomen | `UABDO` | 15–20 | 20 | 18% | GP, OP, inpatient |
| US | Abdomen and pelvis | `UABPE` | 20–25 | 30 | 8% | GP, OP |
| US | Pelvis, transabdominal and transvaginal | `UPELV`, `UPETV` | 15–25 | 20 | 14% | GP, OP gynaecology |
| US | Urinary tract / renal | `UURTR` | 15–20 | 20 | 10% | GP, OP, inpatient |
| US | Thyroid and neck | `UTHPY`, `UNECK` | 15–20 | 20 | 6% | GP, OP, 2WW |
| US | Testes / scrotal | `UTEST` | 10–15 | 15 | 3% | GP, OP, ED |
| US | Musculoskeletal (shoulder, soft tissue lump) | `USHLL`, `USLUM` | 15–20 | 20 | 10% | GP, OP |
| US | Lower limb veins (DVT) | placeholder | 15–20 | 20 | 9% | ED, inpatient, SDEC |
| US | Liver | `ULIVE` | 15–20 | 20 | 5% | OP, GP |
| US | Breast and axilla (symptomatic) | `UMAAB` | 20–30 | 30 | 7% | OP breast clinic |
| US | Paediatric hips | `UHIPB` | 10–15 | 15 | 3% | OP paediatrics |
| US | Guided biopsy / drainage | `UABDOB` | 30–45 | 45 | 4% | inpatient, OP |
| US | Arterial doppler, carotid, other vascular | `ULAMB` | 20–30 | 30 | 3% | OP, inpatient; excluded from DM01 |

Codes marked * or "placeholder" were not pulled from the lookup in this
pass and are to be confirmed from `DID-Annex-1-...xlsx` when the catalogue
is built. Obstetric ultrasound is excluded altogether (DM01 excludes it and
maternity is out of scope); vascular ultrasound is in the RIS and the DID
but excluded from the DM01 non-obstetric ultrasound count **(source)**. The DID
release reports Brain MRI as 21.6% of all MRI and chest/abdomen CT as 10.5%
of all CT nationally **(source)**, which the shares above respect.

#### 4.5.1 Calibration of the imaging queue **(source: DID annual release, GIRFT)**

The generator reproduces these national 2023/24 figures at trust level, with
the three teams' different behaviours layered on top:

| Measure | CT | MRI | Ultrasound |
| --- | --- | --- | --- |
| Median request to test, all sources | 1 day | 20 days | 15 days |
| Request to test: share done same day (GIRFT, 2017/18) | ≈43% | ≈8% | ≈18% |
| Request to test: share done by day 14 | ≈72% | ≈38% | ≈46% |
| Request to test: share done by day 42 | ≈92% | ≈84% | ≈87% |
| Median test to report, all sources | 0 days | 4 days | 0 days |
| Reported same day, inpatient and A&E | 91% | 74% | 97% |
| Reported same day, outpatient and GP | 18% | 12% | 94% |
| Reported by end of next day, outpatient and GP | 29% | 24% | 96% |
| Source mix (top-10 trusts): A&E / inpatient / outpatient / GP | 35 / 22 / 38 / 5 | 4 / 14 / 71 / 10 | 3 / 14 / 55 / 27 |
| Request to test within 7 days: A&E / inpatient / outpatient / GP (Table 9) | 99.7 / 98 / 26 / 27 | 86 / 93 / 20 / 14 | 86 / 94 / 42 / 15 |
| Request to test over 62 days: outpatient / GP (Table 9) | 18.5 / 5.2 | 17.9 / 10.5 | 16.5 / 14.1 |
| Outpatient and GP exams reported within 7 days (Table 13, comparators) | 45–63% | 48–63% | ≈95% |
| DM01 waiting list at month end, share over 6 weeks | 3,500, 10% | 5,000, 20% | 5,500, 20% |

Ultrasound is the third personality: sonographers report their own scans
as they go, so test-to-report is near zero everywhere, but a quarter of
requests are GP direct access and those queue for weeks.

Pathway: request → vetting (MRI always; CT only routine; ultrasound by a
clinical support worker against a protocol) → booking → scan → report →
verification (ultrasound reports are verified by the sonographer at the
time, so `reported_datetime` and `verified_datetime` coincide). January has longer request-to-test waits for all
modalities **(source)**, and the DID counts an exam on its test date.

Volume: **125,000 CT, 68,000 MRI and 115,000 non-obstetric ultrasound
examinations a year (source: top-10 scale from DID Table 11, ultrasound
net of obstetric)**, of which about 60,000 ultrasound exams are
DM01-countable **(source: DM01 provider file)**, with the national monthly shape (April lowest,
January highest, December a dip; range about ±8%).

### 4.6 `endo_procedures` — the endoscopy vendor's export

A different vendor, so a different shape: procedure-centric, one wide table,
text dates, its own identifiers, no event log. Modelled on the National
Endoscopy Database minimum dataset as far as it is publicly described;
field names are the vendor's style, not the NED's.

| Column | Meaning |
| --- | --- |
| `ProcID` | vendor procedure id |
| `PatientRef` | `EN-` identifier |
| `NHSNo` | text, **with spaces** (`fake_123 456 7890`) |
| `HospNo` | MRN as typed, sometimes blank or with the wrong site prefix |
| `ProcDate` | text, `DD/MM/YYYY` |
| `StartTime`, `EndTime` | text, `HH:MM`, sometimes blank |
| `ProcType` | OGD (gastroscopy), Colonoscopy, Flexi Sig, Cystoscopy (the four DM01 endoscopy tests **(source)**; ERCP and EUS excluded from v1) |
| `Category` | `IP-EL` elective inpatient / day case, `IP-NEL` emergency inpatient, `OP` outpatient direct, `SURV` surveillance (planned), `BCSP` bowel cancer screening |
| `Indication` | short list (e.g. dyspepsia, dysphagia, PR bleeding, iron deficiency, FIT positive, surveillance polyps, GI bleed inpatient, haematuria) |
| `Urgency` | routine, urgent, 2WW, emergency |
| `ReferralDate` | text |
| `Endoscopist` | code |
| `ListID`, `ListPoints` | the list the procedure was on and its total points |
| `Points` | 1 for OGD, flexi sig and cystoscopy; 2 for colonoscopy (JAG convention) |
| `Sedation` | none, throat spray, conscious sedation, Entonox, GA |
| `Extent` | for lower GI: caecum, terminal ileum, splenic flexure, etc. |
| `Completion` | Y/N (caecal intubation for colonoscopy) |
| `Comfort` | 1–5 modified Gloucester comfort score |
| `Outcome` | normal, abnormal with biopsy, polypectomy, abandoned, DNA, cancelled on the day |
| `Site` | free text: `HA`, `Hosp A`, `HB`, `Hospital B` |
| `Report` | one-line synthetic free text, no clinical meaning |

Procedure durations (**assumption**, from NHS patient guidance): OGD 10–15
min, flexi sig 15–20, colonoscopy 30–45 (longer with polypectomy),
cystoscopy 10–15. A standard service list is 10 points over about 4 hours
at RZ902 and 8 points at RZ901 where emergency cases interrupt
(**assumption**; JAG's published training-list standard is 8 points).

**DM01 rules the generator honours (source):**

- Screening programme procedures (`BCSP` index colonoscopy) are not DM01
  diagnostics, but a colonoscopy triggered by a positive FIT *is*.
- Planned (surveillance) procedures are excluded from the waiting list but
  counted as activity in their own column.
- Inpatient emergency procedures are excluded from the waiting list and
  counted as "unscheduled" activity (admission methods 21–2D, 31, 32).
- A patient cancellation or DNA resets the clock to zero at the missed date.
- Entirely therapeutic procedures are excluded; diagnostic-turned-therapeutic
  stay in.

**How endoscopy links to the rest.** There is no spell or appointment key in
this table. Linkage is by patient and date:

- `IP-EL` procedures match a day-case spell on the same date (admission method 11/12, specialty 301, 104 or 101).
- `IP-NEL` procedures match an open non-elective spell containing the procedure date (e.g. upper GI bleed admitted via ED).
- `OP` procedures match a referral or an outpatient appointment whose outcome was "diagnostic requested" within the preceding 12 weeks.
- `SURV` and `BCSP` are planned: a recall date exists and the procedure is excluded from waiting-time aggregates. `BCSP` patients are aged 50–74 (**assumption**).

About 45% `OP`, 12% `SURV`, 8% `BCSP`, 30% `IP-EL`, 5% `IP-NEL`
(**assumption** for the split; the DM01 planned share of 12% and
unscheduled share of 3% are **(source)**). Volume: 24,000 procedures a year,
gastroscopy 9,400, colonoscopy 8,300, flexi sigmoidoscopy 3,700, cystoscopy
2,600 **(source: DM01 provider file, Nottingham August 2026 scaled to a
year)**. The endoscopy waiting list at month end is about 2,700 with 35%
over six weeks **(source)**.

### 4.7 Reference tables

`ref_sites`, `ref_wards` (with valid-from/valid-to for renames), `ref_beds`
(one row per bed space with its type), `ref_specialties`
(from `nhs-specialties/`), `ref_consultants`, `ref_clinics`, `ref_exam_catalogue`
(NICIP, SNOMED, modality, durations), `ref_admission_method`,
`ref_admission_source`, `ref_discharge_destination`, `ref_attendance_status`,
`ref_ecds_codes` (arrival mode, attendance source, acuity, discharge status,
discharge destination, with their SNOMED concept IDs from the ETOS),
`ref_patient_source_setting`, `ref_chief_complaint`.

### 4.8 `mess_log` — the answers

One row per injected imperfection: `mess_id` (catalogue code), `table`,
`row_key`, `field`, `original_value` (where the mess replaced something),
`note`, `mess_row`. Shipped as a separate file (`mess_log.csv`) so it can be
withheld in a teaching exercise. Rows whose note says "removed" or "never
happened" refer to rows that no longer exist in the table; the PAS event
log is re-sequenced after injection, so its `row_key` values are the
pre-injection message ids and should be matched on the other columns.
The clinic close-down batch (M-BOUNCE-03) is logged once per clinic
session, with the clinic code and date as the key, rather than once per
audit row.

## 5. Layer 2: derived entities

All built by DuckDB SQL files under `sql/derive/`, run in order and committed
with the data. Each file is short enough to read in a teaching session.
Column names follow HES and ECDS where a HES or ECDS field exists
**(source: HES APC/OP TOS, ECDS ETOS)**, so a user who knows HES can query
without a dictionary.

| Table | Grain | Derived from | Key decisions the SQL has to make |
| --- | --- | --- | --- |
| `patients` | one row per real person (master patient index) | all sources + A40 merges | which MRN survives; how ED, RIS and endoscopy identifiers map on |
| `spells` | one hospital provider spell (`PROVSPNO`, `ADMIDATE`, `DISDATE`, `ADMIMETH`, `ADMISORC`, `CLASSPAT`, `DISMETH`, `DISDEST`, `SPELDUR`) | `pas_adt_events` | handling A11/A13 cancellations, duplicate A03s, missing A03s, open spells at the edges |
| `episodes` | consultant episode (`EPIKEY`, `EPIORDER`, `EPISTART`, `EPIEND`, `TRETSPEF`, `MAINSPEF`, `SPELBGIN`, `SPELEND`, `EPISTAT`) | A01 + A08 specialty changes | episode boundaries when A08 is a correction rather than a transfer of care; `EPISTAT` 3 finished / unfinished at year end |
| `ward_stays` | one continuous stay on one ward | A01/A02/A03 | normalising ward names; stays of zero minutes; ED and Discharge Lounge as locations |
| `ed_attendances_clean` | one attendance (`AEKEY`-style key) | `ed_attendances` + `ed_status_log` + MPI | resolving unmapped MRNs; linking admitted attendances to spells (HES AE carries `EPIKEY`, APC carries `AEKEY` **(source: HES data model)**); choosing the *first* time a status was reached rather than the last-written one when the record has bounced |
| `op_appointments_clean` | one appointment (`ATTENDKEY`, `ATENTYPE` derived from `FIRSTATT` and `ATTENDED`) | `pas_outpatient_appointments` + `pas_op_status_log` | collapsing rebooked slots; deciding the final status when it changed several times within minutes (last write, last write by a clinical user, or the value that held longest) |
| `rtt_pathways` | one pathway | `pas_referrals` + appointments + spells | clock stops implied by activity |
| `imaging_exams` | one performed exam | `ris_imaging` | de-duplicating CT cancellations; backfilled MRI report dates; ultrasound multi-row bookings; request-to-test and test-to-report intervals |
| `endoscopy_procedures` | one performed procedure | `endo_procedures` + MPI + spells | parsing text dates; attaching `spell_id` or `referral_id` by date overlap; DM01 category (waiting list / planned / unscheduled) |

## 6. Layer 3: aggregates

Built by SQL under `sql/aggregate/`. Each mirrors a national return or a
standard management report, and each discards something recoverable only
from layer 1 or 2.

| Aggregate | Grain | Mirrors **(source)** | What it loses |
| --- | --- | --- | --- |
| `agg_midnight_census` | ward × day, beds occupied at 00:00 | bed state / SitRep | everything between midnights; same-day stays vanish |
| `agg_daily_flow` | site × specialty × day: admissions, discharges, deaths, transfers in/out | daily flow report | who moved; LOS distribution |
| `agg_ae_monthly` | site × month: Type 1 attendances, within 4 h, over 4 h, emergency admissions via ED, over 4 h and over 12 h from decision to admit | Monthly A&E time series | intra-day arrival pattern; acuity mix |
| `agg_apc_monthly` | specialty × admission-method group × month: spells, FCEs, bed days, mean and median LOS, day cases | HES APC activity | the LOS tail; readmissions |
| `agg_op_monthly` | specialty × month: first and follow-up attendances, DNA rate, hospital cancellations | HES OP activity | rebooking churn |
| `agg_dm01_snapshot` | test × month-end: waiting list by weeks waiting, plus activity in month split waiting list / planned / unscheduled | DM01 | who waited; the clock resets; which cancellations were the hospital's |
| `agg_did_extract` | one row per performed exam with the 17 DID columns, dates only | DID submission | times of day; cancellations; DNAs; everything about the queue before the scan |
| `agg_did_monthly` | modality × patient source setting × month: exams, median request-to-test and test-to-report, same-day report % | DID statistics | exam mix; team differences |
| `agg_rtt_incomplete` | specialty × month-end: incomplete pathways by weeks waiting, median, within 18 weeks, over 52 weeks | RTT incomplete | pathway histories |
| `agg_endoscopy_monthly` | procedure type × category × month: procedures, points, completion rate | JAG-style activity | list utilisation; linkage to admissions |

`agg_did_extract` deserves a sentence: it is the layer-1 RIS table reduced
to exactly what the DID asks for. Putting the two side by side is the
cleanest demonstration in the whole dataset of what a national extract
cannot see.

## 7. Volumes, seasonality and shape

Annual volumes the generator targets:

| Activity | Per year | Basis |
| --- | --- | --- |
| ED Type 1 attendances | 165,000 | **(source: provider CSV, single-ED trusts in the imaging top ten)** |
| UTC / Type 3 attendances | 100,000 | **(source: provider CSV, same trusts)** |
| Emergency admissions via ED | 46,000 | 28% of Type 1 **(source: national series and provider CSV)** |
| Other emergency admissions | 40,000 | **(source: provider CSV, Nottingham and Oxford)** |
| Spells, excluding maternity | 250,000: emergency 95,000, waiting list and booked 140,000, planned 15,000; day cases 90,000 | **(source: HES APC provider table, Nottingham and Oxford)** |
| Consultant episodes | 310,000 | **(source: same, 1.25 per spell)** |
| Bed days | 560,000 | **(source: same)** |
| Outpatient attendances | 1,500,000, plus 105,000 DNAs, 175,000 patient and 300,000 hospital cancellations | **(source: HES OP provider table, Nottingham and Oxford)** |
| CT examinations | 125,000 | **(source: DID Table 11, rank 8–10)** |
| MRI examinations | 68,000 | **(source: DID Table 11, rank 8–10)** |
| Ultrasound examinations, non-obstetric | 115,000, of which about 60,000 DM01-countable | **(source: DID Table 11 top-10 median net of obstetric; DM01 provider file)** |
| Endoscopy procedures | 24,000 | **(source: DM01 provider file, Nottingham)** |
| RTT incomplete pathways (snapshot) | 88,000 | **(source: RTT provider file, Nottingham and Oxford)** |
| RTT completed pathways | 180,000 | **(source: same, 15,000 a month)** |

Patterns the generator builds in, with sources where they exist:

- **ED arrivals**: weak volume seasonality (about ±7%, February low, March and
  May high) but strong performance seasonality: four-hour performance about
  60–64% in summer and 55–57% in December and January, and 12-hour
  decision-to-admit waits roughly doubling in winter **(source)**. Arrivals
  peak early afternoon and on Mondays (**assumption**).
- **Admissions**: non-elective peaks in winter with an early-January spike;
  elective dips over Christmas and in August; discharges dip at weekends so
  occupancy peaks on Monday (**assumption**, consistent with the ED
  performance pattern). Median elective wait 28 days; median length of
  stay 1 day with a long tail **(source: HES APC)**.
- **Imaging**: April lowest, January highest, December a dip; January has
  the longest request-to-test waits **(source)**. MRI reporting backlog
  grows over each summer (**assumption** for the shape; the annual median
  stays at 4 days to match the national figure).
- **RTT**: incomplete list flat to slightly rising; over-52-week tail shrinks
  from 5% to 1.3%; median wait from 14–15 weeks to 11 **(source)**.
- **Length of stay**: log-normal with a long tail per specialty
  (**assumption**).
- A flu season in each winter with a different shape (nod to the `flu/`
  app).

## 8. Hosting, formats and access

- **Primary format: Parquet**, one file per table. The full-scale run
  produces 38 million rows, about 1.1 GB as ZSTD Parquet, which exceeds
  what GitHub Pages will host, so the **full set is attached to a GitHub
  release** of the repository (one asset per file, large tables partitioned
  by financial year, uploaded by a workflow that rebuilds the set from the
  seed and checks it against the committed manifest) and the **5% sample
  lives in the repository** under
  `data/v2/sample/` and is served by Pages. `data/README.md` has the URLs
  and read examples.
- **A `sample/` partition alongside `full/`**: a 5% sample of *patients*
  (about 40,000) with all of their activity across every table, so joins
  hold. About 129 MB including the CSV zip (the full set is 1,069 MB).
  This is what the browser console loads by default;
  `full/` is a toggle. Both carry the same version and seed.
- **Secondary format: a CSV zip** of the sample's tables, alongside it. It
  exists only for people whose tools cannot read Parquet, and for opening a
  table in a spreadsheet. The Parquet files are canonical; the CSVs are
  generated from them and carry the same version tag. Everything is listed
  in `manifest.json` with row counts, sizes and checksums. The full set has
  no CSV zip: at 3.7 GB it would not be a convenience.
- **Browser:** a page in the usual repo style with a DuckDB-WASM SQL console
  pre-loaded with the tables, a schema browser, and the explainer walking
  from an ADT event to a spell to a midnight census with runnable queries.
  GitHub Pages serves the Parquet files from the same origin, so no CORS or
  external hosting is needed.
- **R:** `duckdb` with the httpfs extension or `arrow::read_parquet()` on the
  Pages URL. A small R package in the sub-project (working name
  `fakehosp`) wraps this: `fh_tables()`, `fh_read("spells")`, and
  `fh_connect(scale = "sample")` which returns a DuckDB connection with
  every table attached as a view so joins run locally.
- **Python:** `duckdb.sql("select ... from 'https://thomuk.github.io/synthetic-hospital-data/data/v2/full/spells.parquet'")`
  or `pandas.read_parquet(url)`. Documented in the README; no package.
- **Versioning:** `data/v2/` is immutable once published. A regenerated or
  reshaped dataset goes to `data/v2/` with its own manifest. Other projects
  pin a version.

## 9. The generator

- **Language: R**, as an R package under `generator/`.
- **Toolchain in the cloud session.** CRAN is not reachable from the
  container, so R (4.3.3) and its packages come from the Ubuntu archive:
  data.table, testthat, jsonlite, withr, cli, checkmate, digest, lubridate.
  The archive has no arrow or duckdb for R, so the package writes its
  layer-1 tables as CSV with `data.table::fwrite` and a small Python step
  using DuckDB converts them to Parquet, runs `sql/derive` and
  `sql/aggregate`, draws the sample and writes the manifest. The SQL is the
  same whichever engine runs it, which is the point. `generator/setup-cloud.sh`
  installs all of this and is the environment's setup script.
- **Entry point:** `generate(seed = 20230401, n_patients = 800000, start = "2023-04-01", end = "2026-03-31", volumes = default_volumes(), mess = default_mess_rates(), out_dir)`.
- **Pipeline:** population → referrals and outpatient → ED attendances →
  admissions and ward moves (clean event log) → imaging → endoscopy → inject
  mess (recording every injection in `mess_log`) → write layer 1 and truth
  as CSV (`generator/run.R`) → `generator/build.py` loads into DuckDB,
  writes Parquet, runs `sql/derive/*.sql` and `sql/aggregate/*.sql`, draws
  the 5% patient sample and reruns the same SQL on it, zips the sample as
  CSV and writes the manifest.
- **Tests:** `testthat` unit tests on the engine (determinism for a fixed
  seed, volumes within tolerance, every spell has one A01, every injected
  mess row is in `mess_log`, derived layer reproduces the clean truth when
  mess is switched off, DID hard validations pass on `agg_did_extract`:
  request ≤ received ≤ test ≤ report).
- **Mess is a switch.** `mess = NULL` produces the clean dataset, which is
  itself useful: the derived layer built from clean data is the ground
  truth the messy derivation is marked against.
- **No regeneration in the browser.** The committed dataset is the product;
  the generator is there so anyone can run it locally with another seed or
  size (a 50,000-patient run for a laptop is the obvious one).

## 10. Deliverables, in order

1. This design, the calibration note and the mess catalogue (done).
2. R package with the clean generator and tests (done; `generate(mess = NULL)`).
3. Mess injection and `mess_log` (done; `generate()` with `default_mess_rates()`).
4. Derive and aggregate SQL; Parquet build; manifest; sample partition; CSV zip; publication (done; `generator/build.py`, `sql/`, sample under `data/v2/`, full set released by `.github/workflows/release.yml`).
5. Browser console and explainer page; card on the root `index.html`; README row.
6. R helper package and R/Python access docs.

## 11. Open points for review

- The patient count (800,000) follows from the top-10 volumes: 38 million
  rows across tables, 1,069 MB of Parquet for the full set. The principle
  was agreed at 750,000; the HES outpatient volumes pushed it up slightly.
- Every headline volume now has a provider-level source. What remains
  assumed is listed in `CALIBRATION.md` section 8: exam durations and the
  endoscopy procedure-level fields. DID Table 9 (medians by modality and source) and
  Table 13 (quarterly turnaround by provider) would sharpen the imaging
  calibration.
- The trust code `RZ9` and site codes `RZ901`/`RZ902`.
