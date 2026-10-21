test_that("every spell has exactly one A01 and at most one A03, in order", {
  g <- gen_small(); ev <- g$tables$pas_adt_events
  n01 <- ev[event_type == "A01", .N, by = visit_number]
  expect_true(all(n01$N == 1L))
  expect_equal(nrow(n01), nrow(g$truth$spells))
  n03 <- ev[event_type == "A03", .N, by = visit_number]
  expect_true(all(n03$N == 1L))
  expect_equal(nrow(n03), sum(!g$truth$spells$open_at_end))
  ord <- ev[event_type %in% c("A01", "A03"), .(ok = all(event_datetime[event_type == "A01"] < event_datetime[event_type == "A03"])), by = visit_number]
  expect_true(all(ord$ok))
  expect_false(any(duplicated(ev$message_id)))
  expect_true(all(ev$recorded_datetime >= ev$event_datetime))
})

test_that("identifiers are consistent across systems", {
  g <- gen_small(); p <- g$tables$pas_patients
  expect_false(any(duplicated(p$mrn))); expect_false(any(duplicated(p$nhs_number)))
  expect_true(all(g$tables$pas_adt_events$mrn %in% p$mrn))
  expect_true(all(g$tables$ed_attendances$mrn %in% p$mrn))
  expect_true(all(g$tables$pas_outpatient_appointments$mrn %in% p$mrn))
  expect_true(all(g$tables$ris_imaging$mrn %in% p$mrn))
  expect_true(all(g$tables$endo_procedures$HospNo %in% p$mrn))
  expect_true(all(g$tables$pas_outpatient_appointments$referral_id %in% g$tables$pas_referrals$referral_id))
  expect_true(all(g$tables$ed_status_log$uec_activity_identifier %in% g$tables$ed_attendances$uec_activity_identifier))
  expect_true(all(g$tables$pas_op_status_log$appointment_id %in% g$tables$pas_outpatient_appointments$appointment_id))
  im <- g$tables$ris_imaging
  expect_false(any(duplicated(im$accession_number)))
})

test_that("ED timestamps are ordered and admitted attendances become emergency spells", {
  g <- gen_small(); ed <- g$tables$ed_attendances
  ok <- with(ed, (is.na(initial_assessment_timestamp) | initial_assessment_timestamp >= activity_start_datetime) &
                 (is.na(seen_for_treatment_timestamp) | is.na(initial_assessment_timestamp) | seen_for_treatment_timestamp >= initial_assessment_timestamp) &
                 (is.na(decided_to_admit_datetime) | decided_to_admit_datetime >= seen_for_treatment_timestamp) &
                 activity_end_timestamp >= activity_start_datetime)
  expect_true(all(ok))
  adm <- g$truth$ed_admitted[admitted == TRUE]
  adm <- adm[uec_activity_identifier %in% ed[as.Date(activity_end_timestamp) <= as.Date(g$meta$end), uec_activity_identifier]]
  sp <- g$truth$spells[origin == "ed"]
  expect_equal(nrow(sp), nrow(adm))
  expect_true(all(sp$uec_activity_identifier %in% adm$uec_activity_identifier))
  expect_true(all(sp$admission_method == "21"))
})

test_that("the DID hard validations hold on performed exams", {
  g <- gen_small(); im <- g$tables$ris_imaging[status == "verified"]
  expect_true(all(im$request_datetime <= im$request_received_datetime))
  expect_true(all(as.Date(im$request_received_datetime) <= as.Date(im$scan_start_datetime)))
  expect_true(all(as.Date(im$scan_start_datetime) <= as.Date(im$reported_datetime)))
  expect_true(all(im$reported_datetime <= im$verified_datetime))
  expect_true(all(is.na(im$vetted_datetime) | im$vetted_datetime <= im$booked_datetime))
  expect_true(all(im$booked_datetime <= im$scan_start_datetime))
  expect_true(all(im$patient_source_setting %in% c("01", "02", "03", "04", "05", "06", "07")))
  expect_true(all(grepl("^RZ90[12]-[0-9]{8}$", im$accession_number)))
})

test_that("the endoscopy export uses the vendor's text formats", {
  g <- gen_small(); en <- g$tables$endo_procedures
  expect_true(all(grepl("^[0-9]{2}/[0-9]{2}/[0-9]{4}$", en$ProcDate)))
  expect_true(all(is.na(en$StartTime) | grepl("^[0-9]{2}:[0-9]{2}$", en$StartTime)))
  expect_true(all(grepl("^fake_[0-9]{3} [0-9]{3} [0-9]{4}$", en$NHSNo)))
  expect_true(all(en$Points == ifelse(en$ProcType == "Colonoscopy", 2L, 1L)))
  expect_true(all(en$Site %in% c("Hospital A", "Hospital B")))
  lp <- en[, .(s = sum(Points), lp = ListPoints[1]), by = ListID]
  expect_true(all(lp$s == lp$lp))
})

test_that("no activity is recorded after a patient's date of death", {
  g <- gen_small(); p <- g$tables$pas_patients[!is.na(date_of_death)]
  ev <- g$tables$pas_adt_events[mrn %in% p$mrn]
  ev[, dod := p$date_of_death[match(mrn, p$mrn)]]
  expect_true(all(as.Date(ev$event_datetime) <= ev$dod))
  ap <- g$tables$pas_outpatient_appointments[mrn %in% p$mrn & attendance_status %in% c("5", "6")]
  ap[, dod := p$date_of_death[match(mrn, p$mrn)]]
  expect_true(all(as.Date(ap$appointment_datetime) <= ap$dod))
})

test_that("writing produces one CSV per table plus a manifest", {
  g <- gen_small(); d <- tempfile("fh"); write_layer1(g, d)
  f <- list.files(d)
  expect_true(all(paste0(names(g$tables), ".csv") %in% f))
  expect_true("manifest.json" %in% f)
  m <- jsonlite::fromJSON(file.path(d, "manifest.json"))
  expect_equal(m$row_counts$pas_adt_events, nrow(g$tables$pas_adt_events))
  x <- data.table::fread(file.path(d, "pas_adt_events.csv"), nrows = 5)
  expect_true(all(c("message_id", "event_type", "event_datetime", "mrn", "visit_number") %in% names(x)))
})


test_that("beds reference: every ward has bed spaces, with the four bed types", {
  ref <- fh_reference()
  beds <- ref$beds
  expect_setequal(unique(beds$bed_type), c("bed", "recliner", "trolley", "chair"))
  expect_true(all(ref$wards$ward_id %in% beds$ward_id))
  expect_equal(anyDuplicated(beds$bed_id), 0L)
  expect_equal(anyDuplicated(beds[, .(ward_id, bed_label)]), 0L)
  # inpatient wards: one bed space per bed in the wards table, all of type bed
  inpt <- ref$wards[kind %in% c("bed", "escalation", "critical") & ward_name != "SDEC"]
  cnt <- beds[ward_id %in% inpt$ward_id, .N, by = ward_id]
  expect_equal(cnt[match(inpt$ward_id, ward_id), N], inpt$beds)
  expect_true(all(beds[ward_id %in% inpt$ward_id, bed_type] == "bed"))
  # the ED is cubicles and chairs, not beds
  expect_false("bed" %in% beds[ward_name == "ED", bed_type])
  expect_true(all(c("trolley", "chair") %in% beds[ward_name == "ED", bed_type]))
  # day units hold trolleys, recliners and chairs as well as beds
  expect_true(all(c("trolley", "recliner") %in% beds[ward_id %in% ref$wards[kind == "daycase", ward_id], bed_type]))
})


test_that("reference keys are unique and codes keep their leading zeros", {
  ref <- fh_reference()
  expect_equal(anyDuplicated(ref$clinics$clinic_code), 0L)
  expect_false(any(is.na(ref$clinics$clinic_code)) || any(grepl("NA$", ref$clinics$clinic_code)))
  expect_equal(ref$patient_source_setting$code, sprintf("%02d", 1:7))
  expect_equal(anyDuplicated(ref$consultants$consultant_code), 0L)
  expect_equal(anyDuplicated(ref$wards$ward_id), 0L)
})


test_that("the generator exports the beds reference table", {
  g <- gen_small()
  expect_true("beds" %in% names(g$reference))
  expect_gt(nrow(g$reference$beds), 1000)
})
