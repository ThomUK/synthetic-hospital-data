# Mess catalogue

Every imperfection the generator injects, with a stable code so that the
`mess_log` answers table, the teaching material and the tests all refer to
the same thing. Rates are **assumptions** and are generator parameters.

Codes are grouped by the system they live in, because the point of the
exercise is that different teams and different vendors make different kinds
of mess. A category column groups them by *type* of problem so the same
lesson can be taught across systems.

Categories:

- **identity** — the same person or thing appears under more than one key, or two things share a key
- **timing** — timestamps that are missing, out of order, batch-entered or in the wrong clock
- **completeness** — rows or fields that should exist and don't, or exist and shouldn't
- **coding** — the same concept recorded in different codes or free text
- **structure** — the shape of the data hides or distorts the thing it describes
- **process** — an artefact of how the organisation works rather than of the system

## PAS event log (`pas_adt_events`)

| Code | Category | What is injected | Rate | How to detect | What it teaches |
| --- | --- | --- | --- | --- | --- |
| M-PAS-01 | completeness | Duplicate event: the same A02 or A03 sent twice with a new `message_id`, seconds apart | 0.5% of events | identical event fields, different message id | Counting events is not counting things; de-duplication needs a definition of "same" |
| M-PAS-02 | completeness | Missing discharge: an A03 never sent for a spell that clearly ended (next admission for the same patient starts later) | 0.8% of spells | open spell followed by a later A01 for the same MRN | Census from events drifts upward unless spells are closed by inference |
| M-PAS-03 | timing | Out-of-order arrival: `recorded_datetime` order differs from `event_datetime` order within a spell | 2% of spells | message id order ≠ event time order | Sorting by receipt time builds the wrong story; late messages change history |
| M-PAS-04 | timing | Batch-entered transfers: a run of A02 events recorded at 07:00 or 19:00 with `event_datetime` rounded to the hour | 6% of A02 | clustering of recorded times at shift handover; minute = 00 | Ward moves "happen" at handover in the data, not when they happened |
| M-PAS-05 | process | Cancelled admission: A01 followed by A11, patient never arrived | 1.5% of A01 | A11 present | Admissions ≠ arrivals; cancelled spells must be excluded from activity and census |
| M-PAS-06 | process | Cancelled discharge: A03 followed by A13 then a later A03 (the rapid-fire variant is M-BOUNCE-08) | 1% of A03 | A13 present | A spell can "end" twice; discharge date is the last valid A03 |
| M-PAS-07 | identity | Duplicate MRN: a patient registered twice under different MRNs, later merged by an A40 | 1.2% of patients | A40 with `prior_mrn` | Patient counts are too high until merges are applied; activity before the merge sits under the old key |
| M-PAS-08 | identity | Unmerged duplicate: as M-PAS-07 but the A40 never comes | 0.3% of patients | same NHS number and date of birth, two MRNs | Some duplicates are only findable by matching, and matching has false positives |
| M-PAS-09 | coding | Ward name drift: the same ward typed as `Ward 5 Frailty`, `WARD 5 FRAILTY`, `Ward5 Frailty`, `W5 Frailty`, and (before month 14) `Ward 5 Elderly Care` | 8% of ward values | distinct count of ward strings ≫ real wards | Free text needs a reference table with validity dates |
| M-PAS-10 | structure | Zero-length ward stay: A02 to a ward and A02 away within 2 minutes (clerical correction; the three-move variant is M-BOUNCE-10) | 1% of A02 | stay duration < 5 min | Every location in the log is not a stay; a stay needs a minimum duration rule |
| M-PAS-11 | structure | A08 ambiguity: an A08 that changes the specialty code sometimes starts a new consultant episode and sometimes corrects a typo in the original episode | 3% of spells | A08 within 1 hour of A01 with specialty change is usually a correction | Episodes are a judgement derived from events, not a fact in them |
| M-PAS-12 | structure | ED as a ward: admitted patients boarding in ED have an A01 with `ward = 'ED'` and an A02 to a bed hours later | 15% of ED admissions | A01 on ward ED | Admission time ≠ arrival on a ward; the "bed" the census counts may be a trolley |
| M-PAS-13 | timing | Event lag: `recorded_datetime` lags `event_datetime` by 1–3 days for discharges on a Friday | 4% of A03 | lag > 24 h | A report run on Monday morning under-counts Friday discharges; data is never "final" |
| M-PAS-14 | completeness | Open spells at the edges of the window: spells admitted before 1 April 2023 and spells not yet discharged at 31 March 2026 | ~250 at each edge | admission or discharge outside the window | Stock versus flow; a census on day 1 is not the sum of admissions since day 1 |
| M-PAS-16 | timing | Decision-to-admit date for elective admissions defaulted to the admission date by one booking team, so the trust's median elective wait reads 10 days where comparators read 28 | 40% of elective A01 at RZ902 | `decision_to_admit_date` = admission date | A short wait in a national table can be a default, not a fast service (Nottingham's 2025/26 HES figure shows the pattern) |
| M-PAS-15 | process | Activity after death: an outpatient appointment or an A08 recorded after the patient's date of death | 0.2% of deceased patients | event after `date_of_death` | Dates of death arrive late; downstream data is not re-written |
| M-PAS-17 | completeness | Planned pathway without an actual one: a P1-P3 discharge pathway was planned but the ward never confirmed it, so the A03 was sent with `discharge_pathway` blank although the patient has gone | 6% of P1-P3 discharges | `planned_discharge_pathway` in P1-P3, `discharge_pathway` null, A03 present | A plan is not an outcome; counting discharges by pathway from the planned field over-states the supported pathways and hides the unknowns |
| M-PAS-18 | completeness | Actual pathway without a plan: a P1-P3 discharge agreed on the day, with no planned pathway ever recorded | 10% of P1-P3 discharges | `discharge_pathway` in P1-P3, `planned_discharge_pathway` null | Planned-against-actual comparisons need a denominator of discharges that had a plan, not of all discharges |
| M-PAS-19 | coding | Pathway typed in another form: `1`, `Pathway 1`, `p1`, `P 1` for `P1` | 8% of pathway values | distinct values beyond `P0`-`P3` | A four-value field becomes a twenty-value field when it is typed; normalise before you count |
| M-PAS-20 | timing | Discharge ready date entered after the event and defaulted to the discharge date, so a real delay reads as zero | 15% of discharges with a ready date and a delay | `discharge_ready_date` = discharge date on long P2/P3 stays | Delays measured from a retrospectively keyed date under-count; the distribution has a spike at zero that the process explains |

## Administrative bouncing (`pas_adt_events`, `ed_status_log`, `pas_op_status_log`)

A status that is set, reversed and set again within minutes, usually by
admin staff correcting a slip or working through a queue in the wrong
order. The final value is often right; the path to it is not, and anything
derived from "the time the status changed" is wrong.

| Code | Category | What is injected | Rate | How to detect | Measure affected | What it teaches |
| --- | --- | --- | --- | --- | --- | --- |
| M-BOUNCE-01 | process | Outpatient reception marks a patient DNA, the clinician discharges the pathway, reception then marks the patient arrived (they were in the wrong waiting area), all within 4 minutes; the discharge is reversed 20 minutes later or not at all | 1.5% of attended appointments | `pas_op_status_log` with ≥3 changes to `attendance_status` inside 10 minutes | Outpatient DNA rate; RTT clock stop (discharge) and restart | The appointments table says attended; the log says the pathway was closed in between; a DNA letter may already have been generated |
| M-BOUNCE-02 | process | Outpatient status flips attended → DNA → attended → DNA across the clinic close-down batch as two clerks reconcile the same list | 0.8% of appointments | alternating values with identical `recorded_datetime` for the batch rows | Outpatient DNA rate; attended first/follow-up counts | Two people editing one list produce a sequence no single person intended |
| M-BOUNCE-03 | timing | Clinic closed in a batch: every "arrived" and "seen" for a session written at 17:58, so arrival-to-seen is zero minutes for the whole clinic | 60% of clinics | all rows in a clinic share `recorded_datetime` | Clinic waiting time (arrival to seen); clinic utilisation | Status times are recording times; a waiting-time measure built from them measures the clerk, not the clinic |
| M-BOUNCE-04 | process | Outcome bouncing: `outcome` set to discharged, then follow-up, then discharged, then "added to waiting list" within an afternoon as the clinician edits the letter | 2% of attendances | ≥3 changes to `outcome` on one appointment | RTT clock stop date; follow-up backlog; inpatient waiting list additions | The RTT clock stop depends on the outcome; each flip would move it |
| M-BOUNCE-05 | process | ED departure bounce: patient marked departed, reopened by the nurse in charge because the ambulance has not come, departed again 90 minutes later; `ed_attendances` carries the second departure time | 3% of admitted attendances | `ed_status_log` with departed → re-opened → departed | Four-hour performance; time in department; 12-hour breaches | Which departure is the four-hour clock stop? The system took the last; the first is the one the breach report would prefer |
| M-BOUNCE-06 | process | ED decision-to-admit bounce: DTA recorded, removed when SDEC accepts the patient, re-recorded when SDEC closes for the night; the attendance ends up admitted with the *third* DTA time | 2% of admitted attendances | multiple decision-to-admit rows | 12-hour decision-to-admit waits; 4–12 hour trolley waits | Twelve-hour trolley waits are measured from DTA; a bounced DTA shortens them by design or by accident |
| M-BOUNCE-07 | process | ED triage bounce: triaged, then "arrived" re-set by reception when the wrong patient was selected, then triaged again with a different acuity | 1% of attendances | two triage rows with different acuity | Acuity casemix; triage-within-15-minutes | Acuity is a judgement recorded twice; the casemix table uses whichever survived |
| M-BOUNCE-08 | process | PAS discharge bounce: A03 discharge, A13 cancel discharge, A02 back to the ward, A03 again the next morning because transport failed; a second A03/A13 pair the day after for 10% of those | 2.5% of overnight spells; one bounce in 10 doubles | A13 within 6 hours of A03 | Discharge date; bed days; length of stay; discharges before noon | Bed days and discharge date differ by a day depending on which A03 you believe; the midnight census counts the bed either way |
| M-BOUNCE-09 | process | PAS admission bounce: A01 admit to AMU, A11 cancel admit (patient went to SDEC instead), A01 again three hours later to a different ward with a new `visit_number` | 1.5% of ED admissions | A11 then A01 for the same MRN within 6 hours | Spell count; 30-day readmission rate; admissions via ED | Two spells, one patient, one episode of illness; the readmission rate just went up |
| M-BOUNCE-10 | process | PAS ward-move bounce: A02 to ward 7, A02 back to AMU two minutes later (clerk picked the wrong patient), A02 to ward 7 again an hour later | 2% of A02 | three A02 within 90 minutes returning to the origin ward | Transfer count; ward stays; ward-level occupancy | Ward stays of two minutes are not stays; transfer counts need a minimum duration rule |
| M-BOUNCE-11 | process | PAS consultant bounce: A08 changes specialty from 300 to 430 and back twice in a morning as the frailty team accept then decline then accept the patient | 1% of medical spells | ≥3 A08 specialty changes within 4 hours | FCE count; episodes per spell; specialty activity | Episode counts (FCEs) inflate with every change; the derived layer has to decide which changes were care transfers |

Across all of these the `mess_log` records the *intended* final state so
that a derived-layer rule ("last write wins", "last write by a clinical
user", "value held longest") can be scored against it.

## ED system (`ed_attendances`)

| Code | Category | What is injected | Rate | How to detect | What it teaches |
| --- | --- | --- | --- | --- | --- |
| M-ED-01 | identity | MRN not populated: the interface failed to match, `mrn` is null | 4% of attendances | null `mrn` | Linking ED to admissions needs the MPI, not a key |
| M-ED-02 | identity | Wrong MRN: the interface matched the wrong person (same name and date of birth) | 0.1% of attendances | NHS number on the ED row ≠ NHS number of the MRN in PAS | Interface errors are silent; cross-check identifiers where two exist |
| M-ED-03 | timing | Departure time equals decision-to-admit time (see also M-BOUNCE-05 and -06): the ED system auto-closes on admission, so `departure_datetime` is when the admission was keyed, not when the patient left | 60% of admitted attendances | departure = DTA to the minute; PAS A02 away from ED hours later | The four-hour clock stops in the ED system before the patient leaves the department |
| M-ED-04 | timing | Breach-shaped departures: a cluster of `departure_datetime` at 3 h 55–3 h 59 after arrival for discharged patients | 5% of discharged attendances | histogram spike just under 4 h | Targets shape data; the distribution reveals the behaviour |
| M-ED-05 | completeness | Missing initial assessment and triage times for walk-in minors streamed to UTC | 20% of UTC attendances | null `initial_assessment_datetime` | Process steps that did not happen are indistinguishable from steps not recorded |
| M-ED-06 | process | Unplanned re-attendance within 72 h recorded as a new first attendance | 3% of re-attendances | same patient within 72 h, category = first | Re-attendance rates depend on who classifies, not just what happened |
| M-ED-07 | coding | `nhs_number` typed by hand at registration, with spaces in 3-3-4 groups (`fake_410 897 3682`) on 2% of rows; the `fake_` prefix is kept on every variant so no value can pass for a real number | 2% | pattern mismatch | Identifiers need normalising before they are keys |

## Outpatients and referrals (`pas_outpatient_appointments`, `pas_referrals`)

| Code | Category | What is injected | Rate | How to detect | What it teaches |
| --- | --- | --- | --- | --- | --- |
| M-OP-01 | structure | Rebooking churn: a hospital-cancelled slot plus a new slot for the same referral, so one intended appointment is 2–4 rows | hospital cancellations run at 20% of attended appointments, patient cancellations at 12% (HES OP provider table) | same referral, cancelled then booked | Appointments offered ≠ appointments delivered ≠ patients seen |
| M-OP-02 | coding | Attendance status 5 recorded for telephone contacts that the clinician never logged as completed | 3% of telephone contacts | status 5 with no outcome | Attended is a default, not an observation |
| M-OP-03 | completeness | Referral with no appointment and no clock stop (lost to follow-up) | 1.5% of referrals | open pathway, no activity for 52 weeks | The RTT incomplete list contains ghosts; validation is a job |
| M-OP-04 | process | Clock stop recorded 1–3 weeks after the attendance that stopped it | 10% of clock stops | `clock_stop_date` > attendance date | Snapshots taken too early over-state waiting |

## Radiology: CT team (`ris_imaging` where `modality = 'CT'`)

The CT team is a high-volume, 24/7, emergency-led service. Its timestamps are
clean because scanners write them, but its booking admin is loose.

| Code | Category | What is injected | Rate | How to detect | What it teaches |
| --- | --- | --- | --- | --- | --- |
| M-CT-01 | completeness | Cancelled-and-rebooked exams kept as separate rows with `status = 'cancelled'` and a second row for the same request | 7% of CT requests | same patient, same exam code, request minutes apart | Requests ≠ exams; activity counts need a status filter |
| M-CT-02 | completeness | ED CTs with `request_datetime` after `scan_start_datetime` (scan done on a verbal request, order entered afterwards) | 10% of ED CT | request > scan | Negative waits are a process signal, not a data error to delete |
| M-CT-03 | coding | `body_area` blank, `exam_description` carries it as free text (`CT abdo pelv w contrast`, `CTAP`, `CT A/P`) | 30% of CT | null `body_area` | Classification lives in the catalogue, not the row |
| M-CT-04 | completeness | `vetted_datetime` null (CT does not vet emergency or urgent) | 70% of CT | null vetting | A step that one team does and another does not is not missing data |
| M-CT-05 | timing | Report and verification time identical (auto-verified by the reporting radiologist) | 85% of CT | reported = verified | Two timestamps, one event |
| M-CT-06 | process | Duplicate `exam_id` across the two scanners after a RIS upgrade in month 20, resolved by a `scanner_id` suffix later | 0.2% of CT in months 20–22 | non-unique accession | Keys are only unique within the assumptions of the system that minted them |

## Radiology: MRI team (`ris_imaging` where `modality = 'MR'`)

The MRI team is a scheduled, vetted, mostly elective service with a reporting
backlog. Its booking is tidy but its timestamps are backfilled.

| Code | Category | What is injected | Rate | How to detect | What it teaches |
| --- | --- | --- | --- | --- | --- |
| M-MR-01 | timing | Backfilled report dates: reports written during a backlog clearance are dated in batches on Friday afternoons, with `reported_datetime` identical to the minute for 20–40 exams | 15% of MR reports | many reports with the same timestamp | Median report turnaround depends on when the data was cut, not just on the service |
| M-MR-02 | timing | `scan_end_datetime` = `scan_start_datetime` + `slot_minutes` exactly (end time derived from the slot, not observed) | 40% of MR | end − start equals slot for all exams of a type | A derived field dressed as an observation |
| M-MR-03 | coding | `body_area` inconsistent for the same `exam_code`: `Knee`, `knee`, `Knee (L)`, `Lower limb` | 12% of MR | several body areas per exam code | A field filled by people, not by the catalogue |
| M-MR-04 | process | Reporting backlog: `reported_datetime` − `scan_end_datetime` grows from a median of 3 days to 21 days over each summer, then collapses | seasonal | time series of turnaround | A backlog is visible in events and invisible in a monthly mean |
| M-MR-05 | completeness | `vetted_datetime` present for every routine MR but `vetted_datetime` < `request_datetime` for 1% (vetting clock set to default on form) | 1% of MR | vetting before request | Timestamps from forms carry the form's defaults |
| M-MR-06 | process | DNA rate twice as high at RZ902 on Saturdays (extended-hours lists) | structural | DNA by site and weekday | Access initiatives generate their own data patterns |
| M-MR-07 | structure | Two exams in one slot: whole spine booked as three rows (cervical, thoracic, lumbar) sharing one `booked_datetime` and one scan start | 4% of MR | multiple rows, same patient, same scan start | Counting rows counts exam codes, not patients scanned or scanner hours used |

## Radiology: ultrasound team (`ris_imaging` where `modality = 'US'`)

Sonographer-led, GP-facing, spread across both sites and the CDC. Reports
are instant; the mess is in the request and the booking.

| Code | Category | What is injected | Rate | How to detect | What it teaches |
| --- | --- | --- | --- | --- | --- |
| M-US-01 | timing | `reported_datetime` = `verified_datetime` = `scan_end_datetime` + 2 minutes (sonographer verifies in the room) | 95% of US | three timestamps within minutes | A turnaround of zero is a workflow, not a performance |
| M-US-02 | structure | One request, two or more rows: abdomen and pelvis requested together booked as `UABDO` plus `UPELV` on the same slot | 8% of US | same patient, same scan start, two codes | DM01 counts one unit; the DID counts two records; neither is wrong |
| M-US-03 | completeness | GP direct-access DNAs at the CDC site recorded as cancellations by the patient, so the DM01 clock resets without a DNA ever appearing | 6% of RZ902 GP US | status cancelled with `cancel_reason` blank and no rebooking contact | The clock-reset rule rewards recording a DNA as a cancellation |
| M-US-04 | coding | `patient_source_setting` defaulted to `07 Other` for CDC bookings made through the community booking hub | 25% of RZ902 US in months 13–19 | spike in 07 for US only | The DID technical report names this exact behaviour at real providers for ultrasound |
| M-US-05 | process | Obstetric scans leak in: a few hundred `UPELV` rows a year with an obstetric indication, which the DM01 extract must exclude | 0.5% of US | indication text, age and sex | Scope rules are applied downstream, and the upstream system does not know them |

## Radiology: all teams, DID-shaped (`ris_imaging` and `agg_did_extract`)

Behaviours the DID technical report documents at real providers.

| Code | Category | What is injected | Rate | How to detect | What it teaches |
| --- | --- | --- | --- | --- | --- |
| M-RIS-01 | completeness | `request_datetime` null; `request_received_datetime` present | 6% of exams (DID request-date completeness 94.0%) | null request date | The national median uses the received date as a fallback and excludes rows missing both; which rows fall out is not random |
| M-RIS-02 | completeness | `verified_datetime` null on performed outpatient and GP exams at RZ901 (outsourced and home-reported studies filed outside the RIS), falling over the window as the interface is fixed | 45% of RZ901 outpatient CT and MRI reports in year 1, 30% in year 2, 5% in year 3; near zero for inpatient and A&E (DID Table 13 shows Nottingham at 21–50% through 2023/24) | status performed, no report date | Turnaround medians are computed only over exams with a report date, so the missing ones hide the slow tail: the trust shows 0% over 28 days while a third of its reports are unaccounted for |
| M-RIS-03 | coding | `patient_source_setting` defaulted to `07 Other` for a run of outpatient CT and MRI requests at RZ902 for seven months (the ultrasound variant is M-US-04) | up to 40% of RZ902 OP requests in months 13–19 | spike in 07 | A default looks like a category; source splits are only as good as the booking screen |
| M-RIS-04 | identity | Same exam submitted twice with different accession numbers after a RIS archive rebuild | 0.5% in month 25 | same patient, code, test date | Accession numbers are unique within site and within the system that minted them, not forever |
| M-RIS-05 | structure | Complex exam submitted as several records (CT chest/abdo/pelvis as three rows sharing an accession suffix) | 3% of CT staging | same accession stem, same minute | "One record per examination, with the most complex code" is a rule some systems cannot follow |
| M-RIS-06 | identity | `nhs_number_status` 02 (untraced) with an NHS number present that differs from the PAS one by one digit | 1% | status 02 and mismatch against MPI | An untraced number is a claim, not a fact |

## Endoscopy vendor (`endo_procedures`)

A procedure reporting system, not a flow system. Its mess is about shape and
linkage rather than events.

| Code | Category | What is injected | Rate | How to detect | What it teaches |
| --- | --- | --- | --- | --- | --- |
| M-EN-01 | structure | Dates as text in `DD/MM/YYYY`; times as `HH:MM` text; 1% of dates in `MM/DD/YYYY` after a locale change on one workstation in month 9 | 1% in month 9 | dates where day ≤ 12 and month > 12 after parsing; impossible gaps | Parse dates with a rule and a validation, never with a cast |
| M-EN-02 | identity | `NHSNo` with spaces; `HospNo` blank for screening patients (registered by the screening hub, not the trust) | spaces 100%, blank HospNo 80% of BCSP | pattern; null | Departmental systems hold their own view of who a patient is |
| M-EN-03 | coding | `Site` as free text in four spellings | 100% | distinct values | Even a two-site trust needs a site reference table |
| M-EN-04 | completeness | `StartTime`/`EndTime` blank for emergency inpatient procedures done on the ward or in theatre | 50% of IP-NEL | null times, Category = IP-NEL | Activity that happens outside the room the system was built for is thin in the data |
| M-EN-05 | structure | No spell, appointment or referral key: linkage to PAS is by NHS number and date | 100% | by design | Joining across vendors is matching, with rules and a confidence, not a key |
| M-EN-06 | process | Surveillance recalls booked 3–9 months late with `ReferralDate` set to the original recall date, so they look like long waits unless `Category` is used | structural | SURV with long referral-to-procedure | Planned patients distort waiting-time measures unless excluded, as DM01 does |
| M-EN-07 | completeness | `Comfort` and `Extent` null for abandoned and DNA procedures, and null for 5% of completed ones | structural + 5% | null where Outcome = completed | Missing-by-design versus missing-by-omission need different handling |
| M-EN-08 | identity | Same procedure exported twice with different `ProcID` after a report amendment | 2% | same PatientRef, ProcDate, ProcType, StartTime | Amendments create rows in a system without versioning |

## Cross-system

| Code | Category | What is injected | Rate | How to detect | What it teaches |
| --- | --- | --- | --- | --- | --- |
| M-X-01 | identity | The same person has an MRN, an ED id, a RIS id and an endoscopy id, with the NHS number present and correctly formatted in only some of them | structural | MPI build | The master patient index is a product, not an input |
| M-X-02 | timing | Clocks differ: the ED system runs 2 minutes ahead of the PAS and the RIS writes times in UTC during British Summer Time, so overlapping events disagree by 1 hour in summer | structural | ED departure 1 h before/after PAS admission in summer | Timestamps have a time zone and a source, whether or not the column says so |
| M-X-03 | completeness | The aggregates do not add up: `agg_daily_flow` admissions minus discharges does not equal the change in `agg_midnight_census` | emergent, not injected | reconcile the three layers | Aggregates built from different definitions never reconcile exactly; the event layer is where reconciliation happens |

## Implementation status

Every entry below with a rate is implemented in the generator's
`R/mess.R`, keyed by its code in `default_mess_rates()`; set a code to 0 to
switch it off, or pass `mess = NULL` to `generate()` for the clean dataset.
Entries marked structural or emergent (M-PAS-14, M-CT-04, M-EN-05,
M-X-01, M-X-03) need no injection: they arise from the clean generator or
from the derivation itself. Two renames (Ward 11 Frailty, formerly Ward 11
Elderly Care, from June 2024; Ward 4 Gastro, formerly Ward 4 GI Medicine,
from November 2024) are applied to the event log as reference drift and are
not logged, since they are correct history rather than error.

## How the catalogue is used

- The generator reads this file's codes as parameter names in
  `default_mess_rates()`. Any code can be set to 0 to switch it off.
- Every injected row is written to `mess_log` with its code, so an exercise
  can be marked: "find the duplicate MRNs" has an answer key.
- The explainer page uses the codes as anchors so each lesson links to the
  rows that demonstrate it.
- When a new kind of mess is added, add it here first with a code, then to
  the generator, then to the tests.
