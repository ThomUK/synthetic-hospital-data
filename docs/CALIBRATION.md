# Calibration: what the real figures say

Numbers taken from the source documents in `docs/sources/`, used to set the
generator's volumes, mixes and seasonal shapes. Figures are national or
provider-level 2023/24 to 2025/26 unless stated. Anything the generator uses
that is *not* in this file is an assumption and is labelled as such in
`DESIGN.md`.

## 1. Scale of a top-10 trust: imaging (DID Table 11, 2023/24)

Providers ranked by CT plus MRI examinations. Source: `DID-Table-11-2023-24-Modality-Provider-Source-setting.xlsx`, sheet Provider.

| Rank | Trust | CT | MRI | X-ray | Ultrasound | All modalities |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | University Hospitals Birmingham | 176,350 | 95,315 | 455,440 | 144,400 | 906,390 |
| 2 | Leeds Teaching Hospitals | 160,555 | 65,135 | 388,115 | 169,875 | 814,980 |
| 3 | Northern Care Alliance | 129,690 | 87,890 | 374,050 | 123,200 | 738,650 |
| 4 | Barts Health | 144,055 | 67,970 | 399,525 | 350,050 | 994,285 |
| 5 | University Hospitals Sussex | 141,680 | 64,240 | 343,320 | 158,580 | 732,665 |
| 6 | Mid and South Essex | 142,675 | 62,970 | 448,050 | 171,395 | 841,365 |
| 7 | Imperial College Healthcare | 107,140 | 85,505 | 203,295 | 94,135 | 510,525 |
| 8 | Northern Lincolnshire and Goole | 120,770 | 61,935 | 161,190 | 84,080 | 440,770 |
| 9 | University Hospitals of North Midlands | 104,635 | 77,390 | 294,845 | 110,050 | 598,020 |
| 10 | Oxford University Hospitals | 118,045 | 59,670 | 295,975 | 102,190 | 606,315 |
| 11 | Nottingham University Hospitals | 119,295 | 58,030 | 273,400 | 112,510 | 591,895 |

137 NHS trusts submitted CT activity. The top-10 pooled mean is CT 134,560,
MRI 72,800 and ultrasound 150,800 (median 133,800); the 10th-ranked trust
does CT 118,045, MRI 59,670 and ultrasound 102,190. The DID ultrasound
column counts every ultrasound examination, including obstetric and
vascular scans that DM01 excludes (see section 4.1).

**Generator target (a trust sitting around rank 8 to 10):** CT 125,000,
MRI 68,000 and non-obstetric ultrasound 115,000 a year (the top-10
ultrasound median of 133,800 less the obstetric scans the dataset
excludes, taken as about 15%). Plain X-ray is out of scope.

### Patient source setting, % of examinations

| Modality | A&E | Day case | Inpatient | Outpatient | GP direct access | Other provider | Other |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CT, England | 32.6 | 0.4 | 22.3 | 36.8 | 6.0 | 0.7 | 1.2 |
| CT, top-10 pooled | 34.9 | 0.2 | 22.1 | 37.6 | 5.0 | 0.2 | 0.1 |
| MRI, England | 3.3 | 0.7 | 12.4 | 62.9 | 15.8 | 3.0 | 1.9 |
| MRI, top-10 pooled | 3.9 | 0.4 | 14.3 | 70.9 | 9.9 | 0.5 | 0.1 |
| Ultrasound, England | 2.5 | 0.7 | 11.4 | 51.8 | 30.2 | 1.2 | 2.3 |
| Ultrasound, top-10 pooled | 2.8 | 0.7 | 14.4 | 55.1 | 26.8 | 0.1 | 0.1 |
| X-ray, England (out of scope, for comparison) | 34.4 | 0.4 | 16.1 | 21.4 | 25.9 | 0.7 | 1.2 |

The generator uses the top-10 pooled splits for CT, MRI and ultrasound.
These splits are the single strongest reason the three teams behave
differently in the data: a third of CT comes through the emergency
department, almost no MRI does, and a quarter of ultrasound is GP direct
access with no hospital clinician in the loop.

## 2. Emergency department: national Type 1 series (Monthly A&E Time Series, Sept 2026 edition)

Source: `Monthly-AE-Time-Series-September-2026.xls`, sheets Activity and
Performance. National, Type 1 departments, April 2023 to March 2026.

| Month | Type 1 attendances | Emergency admissions via Type 1 | Admitted % | Type 1 within 4 h % | 12 h+ from decision to admit |
| --- | --- | --- | --- | --- | --- |
| 2023-04 | 1,271,145 | 363,625 | 28.6 | 60.9 | 26,492 |
| 2023-07 | 1,379,854 | 391,312 | 28.4 | 60.9 | 23,396 |
| 2023-10 | 1,413,597 | 401,524 | 28.4 | 55.9 | 43,534 |
| 2024-01 | 1,397,975 | 403,208 | 28.8 | 55.4 | 54,312 |
| 2024-03 | 1,462,878 | 420,025 | 28.7 | 60.9 | 42,972 |
| 2024-07 | 1,425,569 | 405,655 | 28.5 | 61.4 | 36,806 |
| 2024-12 | 1,440,311 | 411,161 | 28.5 | 55.3 | 54,207 |
| 2025-01 | 1,359,026 | 400,481 | 29.5 | 57.7 | 61,529 |
| 2025-07 | 1,469,050 | 412,893 | 28.1 | 63.1 | 35,467 |
| 2026-01 | 1,434,757 | 395,611 | 27.6 | 57.3 | 71,517 |
| 2026-03 | 1,478,144 | 402,356 | 27.2 | 64.1 | 46,665 |

Shape the generator reproduces:

- **Volume seasonality is weak** (about ±7% around the mean; February is
  the low month because it is short, March and May are high). Attendance
  numbers do not have a big winter peak.
- **Performance seasonality is strong**: Type 1 four-hour performance runs
  about 60–64% in summer and 55–57% in December and January, and 12-hour
  waits from decision to admit roughly double in winter. The winter effect
  is a flow and bed problem, not an arrivals problem.
- **Conversion to admission** is steady at 27–29.5% nationally for Type 1.
- There is a slow improvement in four-hour performance across the three
  years (about 61% in 2023 to about 64% by March 2026).

### 2.1 Provider level: one month (Monthly A&E provider CSV, September 2026)

Source: `Monthly-AE-Provider-September-2026.csv`. The trusts that are in
the imaging top ten, with the single-ED teaching trusts that match the
fictional trust's shape at the bottom. Columns: Type 1 attendances, Type 1
four-hour performance, emergency admissions via Type 1 and as a share of
attendances, other emergency admissions (not via A&E), 12-hour-plus waits
from decision to admit, and Type 3 / other attendances.

| Trust | Type 1 | 4 h % | Adm via T1 | Adm % | Other emerg adm | 12 h+ DTA | Type 3 / other |
| --- | --- | --- | --- | --- | --- | --- | --- |
| University Hospitals Birmingham (4 EDs) | 34,437 | 57.3 | 10,284 | 29.9 | 8,515 | 2,085 | 12,413 |
| University Hospitals Sussex (3) | 28,715 | 57.2 | 8,244 | 28.7 | 1,652 | 840 | 1,421 |
| Mid and South Essex (3) | 28,595 | 61.8 | 9,218 | 32.2 | 1,161 | 1,371 | 8,495 |
| Barts Health (3) | 27,253 | 61.0 | 3,992 | 14.6 | 1,207 | 1,208 | 18,702 |
| Northern Care Alliance (4) | 27,197 | 61.5 | 7,815 | 28.7 | 2,708 | 1,103 | 9,021 |
| Leeds Teaching Hospitals (2) | 19,809 | 61.8 | 3,696 | 18.7 | 1,164 | 685 | 10,454 |
| University Hospitals of North Midlands (2) | 15,160 | 45.3 | 4,724 | 31.2 | 1,167 | 640 | 9,198 |
| Nottingham University Hospitals (1) | 13,656 | 44.6 | 3,760 | 27.5 | 4,052 | 979 | 11,627 |
| Oxford University Hospitals (2) | 13,610 | 72.6 | 5,677 | 41.7 | 4,224 | 8 | 2,856 |
| Imperial College Healthcare (2) | 12,877 | 57.3 | 3,776 | 29.3 | 1,001 | 0 | 7,376 |
| Northern Lincolnshire and Goole (2) | 10,716 | 50.8 | 5,487 | 51.2 | 327 | 757 | 6,433 |
| England | 1,475,440 | 60.4 | 394,675 | 26.7 | 134,842 | 50,582 | 839,337 |

Two things stand out. The big Type 1 numbers belong to multi-ED trusts;
the single-ED teaching hospitals in the imaging top ten (Nottingham's
QMC, Oxford's John Radcliffe) run 13,000–14,000 Type 1 attendances a
month, about 165,000 a year, with a co-located UTC or Type 3 stream of a
similar order. And "other emergency admissions" (GP, bed bureau, transfers,
SDEC conversions) are as large as admissions via the ED at those trusts,
which matters for the ADT admission-method mix. Twelve-hour waits from
decision to admit vary from near zero to almost a thousand a month at the
same scale, so they are a generator parameter rather than a derived fact.

**Generator targets, taken from the Nottingham and Oxford shape:**

| Measure | Per year | Per month |
| --- | --- | --- |
| Type 1 attendances | 165,000 | 13,750 |
| UTC / Type 3 stream (same table, `uec_activity_type`) | 100,000 | 8,300 |
| Emergency admissions via the ED | 46,000 (28%) | 3,850 |
| Other emergency admissions | 40,000 | 3,300 |
| 12-hour-plus decision-to-admit waits | 5,000, winter-weighted | 250–650 |
| Type 1 four-hour performance | tracks the national monthly shape, 55–64% | |

## 3. Referral to treatment: national series (RTT Overview Timeseries, Aug 2026 edition)

Source: `RTT-Overview-Timeseries-Aug26.xlsx`. National, incomplete pathways.

| Month | Incomplete pathways | Median wait (weeks) | Within 18 weeks % | Over 52 weeks % |
| --- | --- | --- | --- | --- |
| 2023-04 | 4,324,159 | 14 | 58.3 | 5.0 |
| 2023-09 | 4,462,623 | 15 | 57.6 | 5.0 |
| 2024-03 | 4,312,728 | 15 | 57.2 | 4.1 |
| 2024-09 | 4,429,902 | 14 | 58.5 | 3.3 |
| 2025-03 | 4,434,722 | 14 | 59.8 | 2.4 |
| 2025-09 | 4,505,684 | 13 | 61.7 | 2.4 |
| 2026-03 | 4,580,320 | 11 | 65.3 | 1.3 |

Shape: the list is flat to slightly rising; the tail (over 52 weeks)
shrinks steadily from 5% to about 1%; median wait drifts from 14–15 weeks
to 11; within-18-weeks improves from 58% to 65%. The generator's referral
and clock-stop rates are tuned so the fictional trust's incomplete list
follows this profile scaled to its size.

### 3.1 Provider level: one month (RTT waiting times by provider, August 2026)

Source: `RTT-Waiting-Times-by-Provider-Aug26.xls`, sheets IncompProv,
AdmProv and NonAdmProv. The imaging top-ten trusts plus Nottingham. The
single-ED comparators (Nottingham, Oxford) sit 14th to 19th nationally by
incomplete list size.

| Trust | Incomplete | Within 18 wk % | Median wk | 92nd pct wk | Over 52 wk % | Completed admitted in month | Median wk | Completed non-admitted in month | Median wk |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| University Hospitals Birmingham NHS Foundation Trust | 96,056 | 66.6 | 11.8 | 32.8 | 0.2 | 3,066 | 4.2 | 17,094 | 7.9 |
| Leeds Teaching Hospitals NHS Trust | 89,297 | 67.5 | 11.0 | 37.3 | 1.7 | 4,642 | 8.4 | 13,772 | 6.8 |
| Northern Care Alliance NHS Foundation Trust | 136,819 | 55.8 | 15.5 | 43.6 | 2.9 | 2,501 | 14.3 | 14,463 | 13.2 |
| Barts Health NHS Trust | 122,447 | 64.1 | 12.5 | 38.4 | 0.8 | 2,537 | 15.6 | 17,778 | 10.9 |
| University Hospitals Sussex NHS Foundation Trust | 118,139 | 52.6 | 16.9 | 47.5 | 4.8 | 3,922 | 19.8 | 14,902 | 9.6 |
| Mid And South Essex NHS Foundation Trust | 165,234 | 50.4 | 17.8 | 52.2 | 8.1 | 4,078 | 12.8 | 20,348 | 11.2 |
| Imperial College Healthcare NHS Trust | 84,317 | 70.4 | 10.8 | 32.5 | 0.0 | 3,163 | 13.9 | 15,686 | 7.3 |
| Northern Lincolnshire And Goole NHS Foundation Trust | 43,136 | 58.6 | 14.3 | 44.5 | 3.7 | 1,231 | 14.5 | 6,063 | 9.8 |
| University Hospitals Of North Midlands NHS Trust | 75,383 | 60.0 | 13.8 | 41.5 | 2.3 | 2,700 | 12.8 | 11,859 | 6.4 |
| Oxford University Hospitals NHS Foundation Trust | 89,879 | 62.2 | 13.3 | 40.9 | 1.7 | 3,575 | 16.4 | 13,358 | 10.0 |
| Nottingham University Hospitals NHS Trust | 86,339 | 62.1 | 13.3 | 43.2 | 2.8 | 2,289 | 20.3 | 10,156 | 13.5 |

Pooled specialty mix of the incomplete list at five teaching trusts
(Nottingham, Oxford, Leeds, Birmingham, Imperial). "Other medical" and
"other surgical" are the national return's catch-all treatment functions
and are larger than any named specialty, which the generator reproduces
by mapping its tertiary and sub-specialty referrals to them.

| Treatment function | Description | Share of incomplete list % |
| --- | --- | --- |
| X02 | Other - Medical Services | 15.2 |
| 502 | Gynaecology Service | 9.0 |
| X05 | Other - Surgical Services | 8.4 |
| 120 | Ear Nose and Throat Service | 8.1 |
| 130 | Ophthalmology Service | 7.5 |
| 110 | Trauma and Orthopaedic Service | 6.9 |
| 330 | Dermatology Service | 6.8 |
| X04 | Other - Paediatric Services | 5.9 |
| 320 | Cardiology Service | 4.9 |
| 101 | Urology Service | 4.9 |
| 301 | Gastroenterology Service | 4.5 |
| 400 | Neurology Service | 3.5 |
| 100 | General Surgery Service | 2.5 |
| 140 | Oral Surgery Service | 2.4 |
| 340 | Respiratory Medicine Service | 2.1 |
| 160 | Plastic Surgery Service | 1.9 |
| 150 | Neurosurgical Service | 1.8 |
| 410 | Rheumatology Service | 1.4 |
| X06 | Other - Other Services | 1.2 |
| 430 | Elderly Medicine Service | 0.5 |
| 170 | Cardiothoracic Surgery Service | 0.4 |
| 300 | General Internal Medicine Service | 0.1 |
| X03 | Other - Mental Health Services | 0.0 |

**Generator targets, taken from the Nottingham and Oxford shape:**

| Measure | Value |
| --- | --- |
| Incomplete pathways, month-end snapshot | 88,000 |
| Within 18 weeks | 62% |
| Median wait | 13 weeks |
| 92nd percentile | 42 weeks |
| Over 52 weeks | 2% |
| Completed admitted pathways per month | 3,000 (median 18 weeks) |
| Completed non-admitted pathways per month | 12,000 (median 12 weeks) |
| Clock starts per month | about 15,500, so the list is roughly stable |

Over the three-year window the trust follows the national trajectory in
section 3: the over-52-week share falls from about 5% to about 1.5% and
the median from 15 weeks to 11.

## 4. Diagnostics waiting times: DM01 rules (DM01 Guidance v9, March 2026)

Source: `DM01-Guidance-v9.pdf`. Page numbers are the printed ones.

- **The 15 tests** (p5, p17). Imaging: MRI, CT, non-obstetric ultrasound,
  barium enema, DEXA. Physiological science: audiology assessments,
  echocardiography, cardiac electrophysiology, peripheral neurophysiology,
  sleep studies, urodynamics. Endoscopy: colonoscopy, flexi sigmoidoscopy,
  cystoscopy, gastroscopy. Plain X-ray is not a DM01 test. The dataset
  covers seven of the fifteen: MRI, CT, non-obstetric ultrasound, and the
  four endoscopy tests (cystoscopy modelled as a urology procedure in the
  same vendor table as the gastrointestinal ones).
- **Clock start** (p6): "when the request for a diagnostic test or procedure
  is made." **Clock stop**: "when the patient receives the diagnostic
  test/procedure." The report date plays no part.
- **Snapshot** (p6): length of wait in weeks "on the last day of the month".
- **Patient cancellation or DNA** (p6): the clock "continues until the date
  of the appointment that the patient cancelled or missed, whereupon it is
  set to zero and the waiting time starts again." Two declined reasonable
  offers (three or more weeks out) also allow a reset. No rule for hospital
  cancellations: the clock runs on.
- **Excluded from the waiting list** (p5–6): planned or surveillance tests
  on a planned list; screening-programme tests (but a diagnostic triggered
  by a positive screen is included); patients currently admitted and waiting
  for an unscheduled test; tests incidental to a therapeutic admission.
- **Activity** (p7–9): tests "carried out during the month", one unit per
  distinct test (multiple MR scans of the same knee at one visit are one
  unit), in three columns: waiting list (excluding planned), planned
  (surveillance), and unscheduled (patients admitted as emergencies,
  admission methods 21–2D, 31, 32, and tests in A&E).
- **Not in the document**: the weeks-waiting bands, the 6-week / 1%
  operational standard, any report-date rule. The bands and the standard
  come from the monthly proforma and statistical release, not the guidance.

### 4.1 Provider level: one month (DM01 provider file, August 2026)

Source: `DM01-Provider-August-2026.xls`, sheet Provider by Test. Waiting
list at month end, share waiting 6+ and 13+ weeks, and the three activity
columns the guidance defines (waiting list, planned, unscheduled).

| Trust | Test | Waiting list | 6+ wk % | 13+ wk % | Waiting-list activity | Planned | Unscheduled | Total in month |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Nottingham University Hospital | Magnetic Resonance Imaging | 5,415 | 41.6 | 8.8 | 5,955 | 972 | 25 | 6,952 |
| Nottingham University Hospital | Computed Tomography | 5,109 | 46.1 | 20.8 | 1,576 | 1,044 | 7,537 | 10,157 |
| Nottingham University Hospital | Non-obstetric Ultrasound | 6,439 | 51.6 | 14.7 | 3,255 | 415 | 1,191 | 4,861 |
| Nottingham University Hospital | Gastroscopy | 1,222 | 41.1 | 20.8 | 693 | 93 | 0 | 786 |
| Nottingham University Hospital | Colonoscopy | 857 | 36.8 | 10.7 | 594 | 99 | 0 | 693 |
| Nottingham University Hospital | Flexi Sigmoidoscopy | 426 | 30.0 | 5.2 | 275 | 35 | 0 | 310 |
| Nottingham University Hospital | Cystoscopy | 157 | 28.0 | 5.7 | 119 | 57 | 0 | 176 |
| Oxford University Hospitals NH | Magnetic Resonance Imaging | 4,345 | 11.9 | 1.7 | 5,468 | 1,030 | 121 | 6,619 |
| Oxford University Hospitals NH | Computed Tomography | 2,552 | 0.0 | 0.0 | 7,315 | 1,270 | 2,562 | 11,147 |
| Oxford University Hospitals NH | Non-obstetric Ultrasound | 5,380 | 8.3 | 0.0 | 7,504 | 380 | 80 | 7,964 |
| Oxford University Hospitals NH | Gastroscopy | 1,186 | 69.7 | 45.0 | 287 | 22 | 55 | 364 |
| Oxford University Hospitals NH | Colonoscopy | 863 | 58.6 | 30.7 | 366 | 60 | 3 | 429 |
| Oxford University Hospitals NH | Flexi Sigmoidoscopy | 376 | 51.1 | 23.9 | 112 | 24 | 25 | 161 |
| Oxford University Hospitals NH | Cystoscopy | 245 | 24.9 | 6.5 | 544 | 21 | 24 | 589 |
| Leeds Teaching Hospitals NHS T | Magnetic Resonance Imaging | 3,954 | 9.2 | 1.6 | 3,075 | 729 | 200 | 4,004 |
| Leeds Teaching Hospitals NHS T | Computed Tomography | 3,002 | 3.7 | 0.4 | 2,571 | 1,044 | 4,465 | 8,080 |
| Leeds Teaching Hospitals NHS T | Non-obstetric Ultrasound | 5,988 | 17.8 | 0.3 | 5,547 | 1,013 | 1,255 | 7,815 |
| Leeds Teaching Hospitals NHS T | Gastroscopy | 401 | 36.2 | 28.9 | 243 | 69 | 14 | 326 |
| Leeds Teaching Hospitals NHS T | Colonoscopy | 334 | 17.7 | 12.0 | 201 | 111 | 1 | 313 |
| Leeds Teaching Hospitals NHS T | Flexi Sigmoidoscopy | 88 | 0.0 | 0.0 | 84 | 30 | 2 | 116 |
| Leeds Teaching Hospitals NHS T | Cystoscopy | 207 | 18.4 | 13.5 | 134 | 206 | 1 | 341 |
| Imperial College Healthcare NH | Magnetic Resonance Imaging | 4,902 | 17.7 | 0.6 | 5,747 | 1,379 | 1,212 | 8,338 |
| Imperial College Healthcare NH | Computed Tomography | 1,636 | 2.7 | 0.2 | 3,876 | 748 | 6,295 | 10,919 |
| Imperial College Healthcare NH | Non-obstetric Ultrasound | 4,160 | 15.6 | 1.9 | 7,373 | 429 | 917 | 8,719 |
| Imperial College Healthcare NH | Gastroscopy | 849 | 1.2 | 0.0 | 506 | 11 | 28 | 545 |
| Imperial College Healthcare NH | Colonoscopy | 875 | 1.0 | 0.0 | 574 | 15 | 4 | 593 |
| Imperial College Healthcare NH | Flexi Sigmoidoscopy | 125 | 0.0 | 0.0 | 78 | 3 | 10 | 91 |
| Imperial College Healthcare NH | Cystoscopy | 257 | 2.7 | 0.8 | 192 | 21 | 13 | 226 |
| University Hospitals Birmingha | Magnetic Resonance Imaging | 7,111 | 19.7 | 3.6 | 8,569 | 1,040 | 2,030 | 11,639 |
| University Hospitals Birmingha | Computed Tomography | 3,828 | 14.8 | 1.1 | 9,252 | 3,494 | 14,094 | 26,840 |
| University Hospitals Birmingha | Non-obstetric Ultrasound | 16,455 | 42.5 | 7.7 | 8,508 | 806 | 3,165 | 12,479 |
| University Hospitals Birmingha | Gastroscopy | 2,200 | 57.4 | 44.8 | 1,265 | 0 | 0 | 1,265 |
| University Hospitals Birmingha | Colonoscopy | 2,297 | 55.9 | 39.5 | 1,306 | 0 | 0 | 1,306 |
| University Hospitals Birmingha | Flexi Sigmoidoscopy | 580 | 53.6 | 37.6 | 271 | 0 | 0 | 271 |
| University Hospitals Birmingha | Cystoscopy | 580 | 56.0 | 33.8 | 212 | 45 | 17 | 274 |

| Test (England, sum of providers) | Waiting list | 6+ wk % | Waiting-list activity | Planned | Unscheduled | Planned % | Unscheduled % |
| --- | --- | --- | --- | --- | --- | --- | --- | 
| Magnetic Resonance Imaging | 357,356 | 22.0 | 353,029 | 37,150 | 50,288 | 8 | 11 |
| Computed Tomography | 181,619 | 11.2 | 347,413 | 78,033 | 369,965 | 10 | 47 |
| Non-obstetric Ultrasound | 648,630 | 21.7 | 573,707 | 59,278 | 87,302 | 8 | 12 |
| Gastroscopy | 73,297 | 29.9 | 52,909 | 6,040 | 3,483 | 10 | 6 |
| Colonoscopy | 76,686 | 30.9 | 47,855 | 6,342 | 850 | 12 | 2 |
| Flexi Sigmoidoscopy | 23,459 | 33.2 | 12,693 | 1,753 | 940 | 11 | 6 |
| Cystoscopy | 24,198 | 27.3 | 23,132 | 6,857 | 1,449 | 22 | 5 |

Notes: the DM01 "unscheduled" column for CT is half of all CT activity
nationally and three quarters at Nottingham, which is the DID's A&E plus
inpatient share seen from the other side. Endoscopy is almost entirely
waiting-list activity with about a tenth planned (surveillance). Six-week
breaches vary from 0% to 70% between trusts of the same size for the same
test; Oxford reports 0% for CT and 70% for gastroscopy in the same month.
Nottingham does about 1,965 of the four DM01 endoscopy procedures a month,
rank 19 nationally; Birmingham 3,116, rank 2. Nottingham's DM01
non-obstetric ultrasound activity (4,861 a month) is about half its DID
ultrasound count (112,510 a year, 9,400 a month): the difference is
obstetric scans (out of scope here), vascular scans, screening, and scans
incidental to another purpose, none of which DM01 counts. The generator
therefore produces about 115,000 non-obstetric ultrasound rows a year in
the RIS of which roughly 60,000 are DM01-countable.

Weeks-waiting profile, endoscopy, pooled RX1/RTH/RR8/RYJ (% of list): 0<1: 17.0 | 1<2: 15.2 | 2<3: 12.0 | 3<4: 7.6 | 4<5: 9.1 | 5<6: 5.5 | 6<7: 2.7 | 7<8: 2.8 | 8<9: 2.9 | 9<10: 2.6 | 10<11: 1.9 | 11<12: 1.6 | 12<13: 1.7 | 13+: 17.3

Weeks-waiting profile, MRI, pooled RX1/RTH/RR8/RYJ (% of list): 0<1: 15.4 | 1<2: 17.3 | 2<3: 14.4 | 3<4: 12.9 | 4<5: 10.4 | 5<6: 8.1 | 6<7: 4.7 | 7<8: 4.0 | 8<9: 3.6 | 9<10: 2.3 | 10<11: 1.3 | 11<12: 1.2 | 12<13: 0.9 | 13+: 3.5

Weeks-waiting profile, non-obstetric ultrasound, pooled RX1/RTH/RR8/RYJ (% of list): 0<1: 15.6 | 1<2: 17.4 | 2<3: 13.6 | 3<4: 10.8 | 4<5: 9.6 | 5<6: 7.9 | 6<7: 5.1 | 7<8: 4.2 | 8<9: 3.2 | 9<10: 2.2 | 10<11: 1.8 | 11<12: 1.8 | 12<13: 1.9 | 13+: 4.8

Weeks-waiting profile, CT, pooled RX1/RTH/RR8/RYJ (% of list): 0<1: 21.1 | 1<2: 18.6 | 2<3: 14.0 | 3<4: 10.5 | 4<5: 9.0 | 5<6: 6.3 | 6<7: 2.3 | 7<8: 1.8 | 8<9: 2.1 | 9<10: 1.9 | 10<11: 1.1 | 11<12: 1.3 | 12<13: 1.1 | 13+: 8.8

**Generator targets, taken from the Nottingham and Oxford shape:**

| Measure | Value |
| --- | --- |
| Endoscopy procedures a year | 24,000: gastroscopy 9,400, colonoscopy 8,300, flexi sigmoidoscopy 3,700, cystoscopy 2,600 |
| of which planned (surveillance) | 12%; unscheduled 3% |
| Endoscopy waiting list at month end | 2,700, with 35% over 6 weeks and 15% over 13 weeks |
| MRI waiting list at month end | 5,000, with 20% over 6 weeks |
| CT waiting list at month end | 3,500, with 10% over 6 weeks |
| Non-obstetric ultrasound waiting list at month end | 5,500, with 20% over 6 weeks (Nottingham 6,439 at 52%, Oxford 5,380 at 8%) |
| Non-obstetric ultrasound DM01 activity a month | 5,000 of the 9,600 ultrasound exams in the RIS; 8% planned, 12% unscheduled |
| Weeks-waiting profiles | the pooled profiles above, as band weights |

## 5. Diagnostic Imaging Dataset: fields and derivations

Sources: `DID-Annex-2-Data-Items-v6.1.pdf`, `DID-Technical-Report-v13-2023-24.pdf`,
`DID-Annual-Statistical-Release-2023-24.pdf`.

### 5.1 The submission (Annex 2)

A CSV with no header row and 17 columns in this order: NHS Number (M*),
NHS Number Status (R), Date of Birth (M*), Ethnicity (M*), Patient Gender
(M*), Patient Home Postcode (M*), Registered GP Practice (M*), Patient Type
(M), Referrer (R), Referring Organisation (R), Date of Test Request (R),
Date Test Request Received (R), Date of Test (M), Imaging Code NICIP (M, or
SNOMED CT), Imaging Code SNOMED CT, Date Test Report Issued (R), Provider
Site Code (M), RIS Accession Number (M). M = mandatory, R = required, M* =
at least one of the starred items must be present (Technical Report p9).

Every temporal item is a **date only**. There is no time of day, no
cancellation, no DNA, no modality and no body-site field: modality and body
site live inside the NICIP or SNOMED code, and the accession number exists
"so that a differentiation can be made between multiple body parts examined
at the same attendance". It must be unique within site code.

Patient Type (source setting) codes: 01 inpatient, 02 day case, 03
outpatient, 04 GP direct access, 05 A&E, 06 other health care provider, 07
other; "based on intended management at the time of the diagnostic test
request". There is no code for unknown.

### 5.2 Hard validations (Technical Report Table A, p9)

Request date ≤ request received ≤ test date ≤ report issued; test date not
more than 3 months before the submission month; NHS number must pass the
modulus-11 check and must not be 1234567890, 0123456789 or N00000000N;
postcode has exactly one space; referrer must be 8 characters (1–2 letters
then digits) or is converted to 99. "Only five data fields (in addition to
accession number) are mandatory, whilst all other fields can be left blank."

### 5.3 Completeness and known data-quality behaviour (Technical Report)

2023/24 completeness: NHS number 99.4%, NHS number status 82.6%, GP code
94.1%, date of test request 94.0%, date of report issue about 95.8%.
Providers have defaulted Patient Type to "Other" for up to 40% of
outpatient requests; accession numbers not consistently available have
produced both overwrites (same accession, different exams) and duplicates
(same exam, different accessions); some providers submit several records
for a complex exam that should be one. All of these are reproduced in the
mess catalogue (M-RIS-*).

### 5.4 Waits and reporting (Annual Release, 2023/24)

| Measure | X-ray | Ultrasound | CT | MRI |
| --- | --- | --- | --- | --- |
| Median request to test, days | 0 | 15 | 1 | 20 |
| Median test to report, days | 1 | 0 | 0 | 4 |
| Reported same day, inpatient and A&E | 31% | 97% | 91% | 74% |
| Reported by end of next day, inpatient and A&E | 55% | 98% | 98% | 87% |
| Reported same day, outpatient and GP | 38% | 94% | 18% | 12% |
| Reported by end of next day, outpatient and GP | 50% | 96% | 29% | 24% |

Monthly MRI request-to-test medians run 19–23 days with January the
longest; the release notes a seasonal rise in January for every modality.
Brain MRI is 953,500 of 4.4 million MRI (21.6%); chest and/or abdomen CT is
806,625 of 7.7 million CT (10.5%). RCR/SoR reporting guidance "suggests
turnaround times from 12 hours (<4 hours for Emergency Department requests
and the acutely unwell) up to 28 days according to urgency and modality".

National monthly activity 2023/24 (all modalities): April lowest at 3.61
million, January highest at 4.19 million, December 3.64 million. The
generator uses the per-modality monthly columns from Table 1 as its
seasonal index.

### 5.5 Day curves (GIRFT radiology, 2017/18 DID data, chart-read)

| Days from request | CT done by | MRI done by | Ultrasound done by |
| --- | --- | --- | --- |
| 0 | ≈43% | ≈8% | ≈18% |
| 1 | ≈50% | ≈13% | ≈26% |
| 10 | ≈65% | ≈31% | ≈40% |
| 14 | ≈72% | ≈38% | ≈46% |
| 28 | ≈85% | ≈62% | ≈68% |
| 42 | ≈92% | ≈84% | ≈87% |

| Days from test | CT reported by | MRI reported by |
| --- | --- | --- |
| 0 | ≈59% | ≈24% |
| 1 | ≈69% | ≈35% |
| 3 | ≈76% | ≈50% |
| 7 | ≈88% | ≈70% |
| 21 | ≈98% | ≈92% |

GIRFT gives no test-to-report curve for ultrasound beyond "ultrasound
reporting turnaround times are generally swift" because sonographers
report their own scans; Table 13 below confirms it. GIRFT also reports mean
scanner counts per trust of 3.4 CT and 2.8 MRI
(median 2), recommends at least two CT scanners accessible from any ED, and
suggests cold scanners plan for "75–80% of all available slots". It gives
no slot lengths, no per-scanner throughput and no DNA rates; those stay as
assumptions.

### 5.6 Request to test by source setting (DID Table 9, England 2023/24)

Source: `DID-Table-9-2023-24-Request-to-test-by-source.xlsx`. Share of
examinations by days from request to test. These are the band weights the
generator uses per modality and source; they explain why the CT, MRI and ultrasound
teams' queues look nothing alike.

| Modality | Source setting | 0-7 days % | 8-31 | 32-62 | >62 | Exams |
| --- | --- | --- | --- | --- | --- | --- |
| CT | Accident and Emergency Department | 99.7 | 0.2 | 0.0 | 0.0 | 2,466,680 |
| CT | Admitted Patient Care - Day case | 66.7 | 22.0 | 6.1 | 5.2 | 30,770 |
| CT | Admitted Patient Care - Inpatient | 98.0 | 1.5 | 0.3 | 0.2 | 1,693,700 |
| CT | GP Direct Access | 26.9 | 51.0 | 16.9 | 5.2 | 461,900 |
| CT | Outpatient | 26.3 | 38.5 | 16.7 | 18.5 | 2,819,500 |
| CT | Other | 50.1 | 27.6 | 11.7 | 10.6 | 143,460 |
| MRI | Accident and Emergency Department | 86.2 | 7.4 | 5.2 | 1.1 | 143,430 |
| MRI | Admitted Patient Care - Day case | 30.5 | 25.0 | 14.6 | 29.9 | 28,925 |
| MRI | Admitted Patient Care - Inpatient | 93.1 | 5.3 | 1.0 | 0.6 | 545,540 |
| MRI | GP Direct Access | 14.3 | 45.6 | 29.6 | 10.5 | 695,515 |
| MRI | Outpatient | 19.6 | 37.4 | 25.1 | 17.9 | 2,772,130 |
| MRI | Other | 27.7 | 33.4 | 26.7 | 12.2 | 216,645 |
| US | Accident and Emergency Department | 85.7 | 5.7 | 3.2 | 5.4 | 267,930 |
| US | Admitted Patient Care - Day case | 67.7 | 17.2 | 6.9 | 8.2 | 71,275 |
| US | Admitted Patient Care - Inpatient | 94.2 | 3.8 | 1.4 | 0.6 | 1,222,785 |
| US | GP Direct Access | 14.7 | 37.3 | 33.9 | 14.1 | 3,270,575 |
| US | Outpatient | 41.9 | 25.6 | 16.0 | 16.5 | 5,578,890 |
| US | Other | 41.2 | 26.3 | 19.2 | 13.4 | 369,220 |

### 5.7 Report turnaround by provider (DID Table 13, 2023/24 Q4)

Source: `DID-Table-13-2023-24-Report-turnaround-by-provider.xlsx`. Share of
examinations reported by elapsed time from test, split inpatient and A&E
versus outpatient and GP.

| Trust | Modality | IP and A&E: same day % | by next day % | >28 d % | not known % | cases | OP and GP: by next day % | by 7 d % | by 14 d % | >28 d % | not known % | cases |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Imperial College Healthcare  | CT | 92 | 98 | 0.0 | 0.2 | 17,125 | 28 | 56 | 75 | 2.2 | 16.4 | 11,800 |
| Imperial College Healthcare  | MRI | 69 | 81 | 3.3 | 5.1 | 4,110 | 18 | 43 | 56 | 12.2 | 24.4 | 19,845 |
| Oxford University Hospitals  | CT | 94 | 99 | 0.1 | 0.1 | 16,230 | 23 | 55 | 77 | 9.1 | 0.9 | 13,960 |
| Oxford University Hospitals  | MRI | 88 | 95 | 0.1 | 0.1 | 2,245 | 24 | 58 | 73 | 11.3 | 3.2 | 13,770 |
| Nottingham University Hospit | CT | 83 | 98 | 0.0 | 0.7 | 18,735 | 17 | 45 | 64 | 0.0 | 30.8 | 12,010 |
| Nottingham University Hospit | MRI | 79 | 90 | 0.0 | 2.5 | 3,020 | 23 | 63 | 75 | 0.0 | 21.4 | 11,050 |
| University Hospitals Birming | CT | 96 | 100 | 0.0 | 0.0 | 28,805 | 30 | 63 | 84 | 1.0 | 0.0 | 16,595 |
| University Hospitals Birming | MRI | 80 | 96 | 0.1 | 0.0 | 5,450 | 27 | 48 | 74 | 3.2 | 0.0 | 18,290 |
| Leeds Teaching Hospitals NHS | CT | 76 | 97 | 0.1 | 0.2 | 21,215 | 23 | 44 | 72 | 2.8 | 0.2 | 21,650 |
| Leeds Teaching Hospitals NHS | MRI | 74 | 89 | 0.1 | 2.1 | 3,130 | 29 | 55 | 80 | 1.8 | 1.0 | 14,230 |
| Imperial College Healthcare | US | 96 | 98 | 0.0 | 0.3 | 3,420 | 94 | 99 | 100 | 0.0 | 0.3 | 24,150 |
| Oxford University Hospitals | US | 97 | 99 | 0.0 | 0.7 | 3,725 | 94 | 99 | 100 | 0.1 | 0.1 | 23,740 |
| Nottingham University Hospit | US | 90 | 94 | 0.0 | 2.3 | 5,090 | 95 | 98 | 98 | 0.0 | 2.1 | 23,415 |
| University Hospitals Birming | US | 99 | 99 | 0.0 | 0.0 | 9,230 | 97 | 100 | 100 | 0.0 | 0.0 | 28,055 |
| Leeds Teaching Hospitals NHS | US | 97 | 97 | 0.2 | 0.3 | 10,135 | 90 | 93 | 94 | 0.1 | 6.1 | 33,835 |

Nottingham outpatient and GP reporting by quarter 2023/24:
   2023-24 Q1 CT: by next day 16%, by 7 days 40%, by 14 days 49%, >28 days 0.1%, not known 42%
   2023-24 Q1 MRI: by next day 18%, by 7 days 34%, by 14 days 41%, >28 days 0.4%, not known 50%
   2023-24 Q2 CT: by next day 12%, by 7 days 33%, by 14 days 43%, >28 days 0.0%, not known 49%
   2023-24 Q2 MRI: by next day 20%, by 7 days 37%, by 14 days 46%, >28 days 0.2%, not known 50%
   2023-24 Q3 CT: by next day 15%, by 7 days 32%, by 14 days 44%, >28 days 0.1%, not known 42%
   2023-24 Q3 MRI: by next day 17%, by 7 days 38%, by 14 days 48%, >28 days 0.1%, not known 44%
   2023-24 Q4 CT: by next day 17%, by 7 days 45%, by 14 days 64%, >28 days 0.0%, not known 31%
   2023-24 Q4 MRI: by next day 23%, by 7 days 63%, by 14 days 75%, >28 days 0.0%, not known 21%

Three lessons the generator reproduces. First, the comparators report
80–95% of inpatient and A&E CT and MRI the same day but only 45–63% of
outpatient exams within a week, while ultrasound is 90–99% same day for
every source because the sonographer writes the report in the room. Second, Nottingham's outpatient CT and MRI show 21–50%
of reports with no issue date across 2023/24 and 0% over 28 days: the
missing dates swallow the tail, so the trust looks as if it has no slow
reports at all. That pattern is now mess entry M-RIS-02 at Nottingham's
rates rather than my earlier guess. Third, the missing-date problem does
not touch ultrasound at the same trust (2%), so it is a workflow property
of the CT and MRI reporting chain, not of the RIS.

## 6. HES and ECDS field shapes

Sources: `HES-Data-Model-v1.0.pdf` (an entity diagram only), `HES-APC-TOS-v2.06.xlsx`, `ECDS-ETOS-v4.0.8.xlsx`.

- HES APC is one row per **episode** (`EPIKEY`), with spell fields repeated
  on every episode (`ADMIDATE`, `ADMIMETH`, `ADMISORC`, `CLASSPAT`) and
  discharge fields only on the last (`DISDATE`, `DISMETH`, `DISDEST`,
  `SPELEND = Y`). `EPIORDER`, `EPISTART`, `EPIEND`, `SPELBGIN`, `EPISTAT`
  (3 finished), `SPELDUR`, `ELECDATE`, `INTMANIG`, `DISREADYDATE`,
  `TRETSPEF`, `MAINSPEF`, `SITETRET`, `PROVSPNOPS`. HES AE carries `EPIKEY`
  and HES APC carries `AEKEY`, which is how an attendance links to its
  admission.
- HES OP is one row per **appointment** (`ATTENDKEY`) with `ATTENDED` (2
  patient cancelled, 3 DNA, 4 hospital cancelled, 5 seen, 6 late and seen,
  7 late not seen), `FIRSTATT` (1–4), `ATENTYPE` derived from the two,
  `OUTCOME`, `PRIORITY` (1 routine, 2 urgent, 3 two-week wait), `REFSOURC`,
  `REQDATE`, `DNADATE`, `WAITING`, `RTTPERSTART/END/STAT`.
- ECDS v4 is one row per **attendance** with timestamps for activity start
  (arrival), initial assessment, seen for treatment, decided to admit,
  clinically ready to proceed and activity end; SNOMED-coded arrival mode,
  attendance source, acuity (1 immediate … 5 low acuity), chief complaint,
  discharge status (treatment complete, streamed, left before assessment,
  died) and discharge destination (home, ward, HDU, ICU, SDEC, theatre,
  transfer, mortuary). The ETOS refset tabs give the full code lists with
  SNOMED concept IDs; the generator's `ref_ecds_codes` is built from them.

## 7. Admitted patient care and outpatients: HES provider tables 2025/26

Sources: `HES-APC-provider-2025-26.xlsx` (Hospital Episode Statistics,
admitted patient care, hospital providers) and `HES-OP-provider-2025-26.csv`
(outpatient activity, provider level). Financial year 2025/26.

### 7.1 Admitted patient care

FCE is a finished consultant episode; FAE is a finished admission episode,
in other words an admission. Nottingham ranks 6th nationally by admissions,
Oxford 15th.

| Trust | FCEs | Admissions (FAE) | Emergency | Waiting list | Planned | Other | Emergency % | Mean wait, days | Median wait, days | Mean LOS, days | Day cases (FCE) | Day case % of FCE | FCE bed days |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| England | 22,627,070 | 18,466,126 | 6,542,854 | 7,449,621 | 2,563,098 | 1,910,553 | 35 | 79 | 34 | 4.5 | 8,733,223 | 39 | 45,123,255 |
| University Hospitals Birmingham NHS Foundation Trust | 468,545 | 402,365 | 214,705 | 109,280 | 58,320 | 20,060 | 53 | 76 | 30 | 4.1 | 144,625 | 31 | 1,054,264 |
| University Hospitals Sussex NHS Foundation Trust | 377,470 | 301,245 | 123,555 | 98,720 | 58,070 | 20,900 | 41 | 84 | 39 | 4.5 | 141,445 | 37 | 729,086 |
| Mid And South Essex NHS Foundation Trust | 357,390 | 294,505 | 125,065 | 101,285 | 40,710 | 27,445 | 42 | 73 | 28 | 4.3 | 125,105 | 35 | 736,159 |
| Nottingham University Hospitals NHS Trust | 377,010 | 293,955 | 106,815 | 140,010 | 13,425 | 33,705 | 36 | 14 | 10 | 3.9 | 130,760 | 35 | 655,740 |
| Northern Care Alliance NHS Foundation Trust | 315,225 | 255,135 | 121,775 | 86,175 | 37,315 | 9,880 | 48 | 70 | 29 | 3.9 | 106,985 | 34 | 584,602 |
| Imperial College Healthcare NHS Trust | 294,910 | 247,090 | 57,125 | 129,350 | 18,545 | 42,070 | 23 | 43 | 17 | 4.0 | 129,445 | 44 | 481,822 |
| University Hospitals Of North Midlands NHS Trust | 315,720 | 232,105 | 75,400 | 91,050 | 32,415 | 33,245 | 32 | 78 | 29 | 4.2 | 109,095 | 35 | 519,252 |
| Oxford University Hospitals NHS Foundation Trust | 275,515 | 229,145 | 108,490 | 90,015 | 11,720 | 18,920 | 47 | 77 | 28 | 3.6 | 83,555 | 30 | 523,348 |
| Barts Health NHS Trust | 299,015 | 222,760 | 73,180 | 91,035 | 28,720 | 29,825 | 33 | 72 | 31 | 5.3 | 96,970 | 32 | 682,378 |
| Leeds Teaching Hospitals NHS Trust | 241,240 | 200,745 | 56,570 | 81,475 | 42,050 | 20,650 | 28 | 78 | 36 | 6.7 | 99,300 | 41 | 676,541 |
| Northern Lincolnshire And Goole NHS Foundation Trust | 150,895 | 135,180 | 71,205 | 36,520 | 18,385 | 9,070 | 53 | 71 | 35 | 2.9 | 50,465 | 33 | 241,589 |

Notes: "Other" admissions are mostly maternity and births, which the
dataset excludes. Nottingham's short mean wait (14 days) against 70–80
days elsewhere is a reporting artefact worth copying as a mess entry, not
a performance figure. Episodes per admission run 1.2–1.3 at the teaching
trusts. FCE bed days of 520,000–660,000 a year imply 1,450–1,800 occupied
beds, consistent with a 1,500-bed trust at high occupancy.

Age profile of episodes, pooled over Nottingham, Oxford, Leeds and Imperial (%):

0 : 4.1 | 1-4 : 2.2 | 5-9 : 1.9 | 10-14 : 2.0 | 15 : 0.5 | 16 : 0.5 | 17 : 0.5 | 18 : 0.5 | 19 : 0.6 | 20-24 : 3.2 | 25-29 : 4.7 | 30-34 : 6.2 | 35-39 : 5.8 | 40-44 : 4.7 | 45-49 : 4.7 | 50-54 : 5.4 | 55-59 : 6.8 | 60-64 : 7.8 | 65-69 : 7.8 | 70-74 : 7.6 | 75-79 : 8.5 | 80-84 : 6.4 | 85-89 : 4.6 | 90+ : 2.9

### 7.2 Outpatients

| Trust | Attended | DNA | Patient cancelled | Hospital cancelled | DNA % | First att | Follow-up att | Tele % of attended | GP-referred first % | Median wait GP ref, first att (days) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| England | 116,891,346 | 8,151,086 | 10,721,925 | 13,922,435 | 6.5 | 38,641,885 | 78,227,464 | 18 | 41 | 33 |
| Leeds Teaching Hospitals NHS Trust | 1,551,975 | 96,750 | 0 | 0 | 5.9 | 543,765 | 1,008,210 | 24 | 33 | 13 |
| Northern Care Alliance NHS Foundation Trust | 1,130,830 | 101,075 | 151,425 | 211,515 | 8.2 | 427,955 | 702,845 | 18 | 48 | 32 |
| Barts Health NHS Trust | 1,860,090 | 208,945 | 213,125 | 570,045 | 10.1 | 574,395 | 1,285,695 | 13 | 33 | 50 |
| Mid And South Essex NHS Foundation Trust | 1,614,695 | 109,025 | 162,065 | 236,105 | 6.3 | 480,025 | 1,134,665 | 19 | 42 | 45 |
| Imperial College Healthcare NHS Trust | 1,417,015 | 136,750 | 197,655 | 351,005 | 8.8 | 490,710 | 926,305 | 19 | 28 | 57 |
| University Hospitals Of North Midlands NHS Trust | 967,775 | 68,010 | 155,455 | 159,935 | 6.6 | 380,400 | 587,375 | 22 | 36 | 14 |
| Oxford University Hospitals NHS Foundation Trust | 1,645,380 | 73,710 | 0 | 0 | 4.3 | 727,985 | 917,395 | 19 | 35 | 18 |
| Nottingham University Hospitals NHS Trust | 1,513,200 | 112,090 | 177,490 | 313,625 | 6.9 | 518,560 | 994,640 | 19 | 54 | 17 |

Notes: hospital cancellations exceed patient cancellations everywhere and
are two to three times the DNA count, which the rebooking-churn mess entry
(M-OP-01) now reflects. Telephone and video consultations are about a fifth
of attendances. Median wait from GP referral to first attendance is 17–18
days at Nottingham and Oxford against 33 nationally. Some trusts report no
cancellations at all (Leeds, Oxford), a reminder that a zero in a national
table is often a submission gap rather than a fact. Birmingham, Sussex,
Mid and South Essex and Northern Lincolnshire are absent from the
outpatient file for 2025/26.

### 7.3 Generator targets, taken from the Nottingham and Oxford shape

| Measure | Per year |
| --- | --- |
| Admissions (spells), excluding maternity | 250,000 |
| of which emergency | 95,000 (46,000 via the ED, 49,000 by other routes) |
| of which waiting list and booked | 140,000 |
| of which planned | 15,000 |
| Day cases | 90,000 (36% of admissions) |
| Consultant episodes | 310,000 (1.25 per spell) |
| Bed days | 560,000 |
| Median wait, elective admission | 28 days |
| Outpatient attendances | 1,500,000 (34% first, 66% follow-up, 19% telephone or video) |
| DNAs | 105,000 (6.5% of attended plus DNA) |
| Patient cancellations | 175,000 |
| Hospital cancellations | 300,000 |
| First attendances referred by a GP | 50% |
| Median GP referral to first attendance | 17 days |

## 8. Discharge pathways (assumptions, with the shape in `default_discharge_pathways()`)

No public dataset gives discharge-to-assess pathway shares by trust in a
form the generator can copy, so these are assumptions, exposed as one
configuration object so a run can be reshaped without touching the code.

- **Planned pathway shares by age band.** The 2020 Hospital Discharge
  Service guidance planned for 50% P0, 45% P1, 4% P2 and 1% P3 across acute
  discharges; the published acute discharge situation reports show real
  trusts with far more P0 than that. The generator takes the higher-P0 view
  and lets age carry the gradient: under 65s 94/5/0.8/0.2, 65-74 82/14/3/1,
  75-84 64/26/7/3, 85 and over 45/35/12/8 (P0/P1/P2/P3, %). Pooled over the
  dataset's age mix this gives roughly 80% P0, 14% P1, 4% P2 and 2% P3 of
  live inpatient discharges.
- **Elective admissions** need less support: their P1-P3 shares are scaled
  by 0.4 and P0 takes the remainder.
- **Planned against actual.** The actual pathway follows the plan 97% of
  the time for P0, 80% for P1, 75% for P2 and 88% for P3; the rest step up
  or down one pathway, with P1 plans most often ending as P0 (12%).
- **Recording.** A planned pathway is written down for 35% of P0 discharges
  and nearly all P1-P3 ones, because simple discharges are not planned
  formally. The discharge ready date is recorded for 25% of P0 discharges
  and 90-95% of P1-P3 ones.
- **Delay** from no longer meeting the criteria to reside to discharge: no
  delay for 85% of P0, 30% of P1, 10% of P2 and 5% of P3; otherwise
  lognormal with medians of 1, 2, 5 and 9 days. Capped at the length of
  stay.
- **Destination** follows the actual pathway: P0 and P1 go to usual or
  temporary residence (P0 keeps a 4% share of transfers to another NHS
  hospital), P2 to another NHS hospital (70%) or a non-NHS hospital (30%),
  P3 to a care home (60%) or a non-NHS care home (40%). Deaths and day
  cases have no pathway and keep their HES destinations.

## 9. Not supplied, still assumptions

- Slot lengths and room times for individual exam types: nothing supplied
  gives them, and GIRFT says no national figure exists.
- Endoscopy procedure durations, list points per list, comfort and
  completion rates: no public NED extract was supplied.
