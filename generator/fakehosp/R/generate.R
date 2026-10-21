#' Generate the Fake NHS Trust synthetic dataset (layer 1, clean)
#'
#' @param seed integer seed; the same seed and parameters give identical output
#' @param n_patients number of patients with at least one contact (800000 at full scale)
#' @param start,end activity window (dates)
#' @param volumes annual volumes at full scale, see [default_volumes()]
#' @param mess mess rates keyed by catalogue code (see [default_mess_rates()]); `NULL` for a clean dataset
#' @param out_dir if given, the tables are written there as CSV with a manifest
#' @param verbose print progress
#' @return a list with `tables` (layer-1 source extracts), `reference`, `truth`
#'   (the clean spell and stay tables the derived layer should reproduce) and `meta`
#' @export
generate <- function(seed = 20230401L, n_patients = 800000L, start = "2023-04-01", end = "2026-03-31",
                     volumes = default_volumes(), mess = default_mess_rates(), out_dir = NULL, verbose = TRUE) {
  checkmate::assert_int(seed); checkmate::assert_int(n_patients, lower = 1000L)
  start <- as.Date(start); end <- as.Date(end)
  scale <- n_patients / volumes$patients_full_scale
  t0 <- Sys.time()
  ref <- fh_reference(seed)
  vmsg(verbose, "Patients: ", n_patients)
  pts <- generate_patients(n_patients, seed, start, end)
  ed  <- generate_ed(pts, ref, volumes, scale, seed, start, end, verbose)
  op  <- generate_outpatients(pts, ref, volumes, scale, seed, start, end, verbose)
  adm <- generate_admissions(pts, ref, volumes, scale, seed, start, end, ed, op, verbose)
  # elective admissions close the RTT clocks of the pathways they came from
  if (nrow(adm$rtt_stops) > 0L) {
    op$referrals[adm$rtt_stops, on = "referral_id", `:=`(rtt_period_end_date = i.admit_date, rtt_period_status = "30")]
    op$referrals[!is.na(rtt_period_end_date) & rtt_period_end_date > end, `:=`(rtt_period_end_date = as.Date(NA), rtt_period_status = "20")]
  }
  op$referrals[, `:=`(stop_kind = NULL, wl_decision_date = NULL)]
  img <- generate_imaging(pts, ref, volumes, scale, seed, start, end, ed, adm, op, verbose)
  endo <- generate_endoscopy(pts, ref, volumes, scale, seed, start, end, adm, op, verbose)
  # deaths: in hospital (spells) and in the ED. A death is only kept when it is
  # the patient's last contact anywhere; otherwise the patient survives.
  d1 <- adm$spells[died == TRUE, .(mrn, dod = as.Date(discharge), src = "spell", key = visit_number)]
  d2 <- ed$attendances[died == TRUE, .(mrn, dod = as.Date(activity_end_timestamp), src = "ed", key = uec_activity_identifier)]
  cand <- rbind(d1, d2)
  last <- rbindlist(list(
    adm$spells[, .(mrn, d = as.Date(admit))], adm$spells[, .(mrn, d = as.Date(discharge))],
    ed$attendances[, .(mrn, d = as.Date(activity_start_datetime))],
    op$appointments[attendance_status %in% c("5", "6"), .(mrn, d = as.Date(appointment_datetime))],
    img[, .(mrn, d = as.Date(request_datetime))],
    endo[, .(mrn = HospNo, d = as.Date(ProcDate, "%d/%m/%Y"))]))[, .(last = max(d)), by = mrn]
  cand[last, on = "mrn", last := i.last]
  # the first death wins; a second "death" of the same patient is reverted
  setorder(cand, mrn, dod)
  dup <- cand[duplicated(mrn)]
  if (nrow(dup) > 0L) {
    rs <- dup[src == "spell", key]; re <- dup[src == "ed", key]
    adm$spells[visit_number %in% rs, `:=`(died = FALSE, discharge_method = "1", discharge_destination = "19")]
    adm$events[visit_number %in% rs & event_type == "A03", `:=`(discharge_method = "1", discharge_destination = "19")]
    ed$attendances[uec_activity_identifier %in% re, `:=`(died = FALSE, discharge_status = "Treatment complete", discharge_destination = "Usual place of residence / family members")]
  }
  dod <- cand[!duplicated(mrn), .(mrn, dod)]
  pts[dod, on = "mrn", date_of_death := i.dod]
  # activity the sampler gave a dead patient after their death is moved to a
  # living donor of the same sex and similar age, in every table
  moved <- move_post_death_activity(pts, dod, adm, ed, op, img, endo)
  adm <- moved$adm; ed <- moved$ed; op <- moved$op; img <- moved$img; endo <- moved$endo
  pas_patients <- pts[, .(mrn, nhs_number, nhs_number_status = "01", sex, dob, ethnicity, gp_practice, postcode, registered_datetime, date_of_death)]
  tables <- list(
    pas_patients = pas_patients,
    pas_adt_events = adm$events,
    ed_attendances = ed$attendances[, !c("admitted", "died", "age")],
    ed_status_log = ed$status_log,
    pas_referrals = op$referrals,
    pas_outpatient_appointments = op$appointments,
    pas_op_status_log = op$status_log,
    ris_imaging = img,
    endo_procedures = endo
  )
  truth <- list(
    spells = adm$spells[, .(visit_number, mrn, admit, discharge, admission_method, patient_class, specialty_first = first_specialty, specialty_last = specialty_code,
                            site_code, los, died, day_case, endoscopy, n_episodes, origin, uec_activity_identifier, referral_id, open_at_end)],
    stays = adm$stays,
    ed_admitted = ed$attendances[, .(uec_activity_identifier, admitted)],
    imaging_links = img[, .(accession_number, linked_id)],
    endoscopy_links = endo[, .(ProcID, linked_id)]
  )
  img[, linked_id := NULL]; endo[, linked_id := NULL]
  mess_log <- NULL
  rm(ed, op, adm, img, endo, d1, d2, cand, last, dod, moved); gc()
  if (!is.null(mess)) {
    gen0 <- list(tables = tables, truth = truth, reference = ref)
    m <- inject_mess(gen0, mess, seed, start, end, verbose)
    tables <- m$tables; truth <- m$truth; mess_log <- m$mess_log
    vmsg(verbose, "Mess rows logged: ", nrow(mess_log))
  }
  meta <- list(version = if (is.null(mess)) "v1-clean" else "v1", seed = seed, n_patients = n_patients, start = as.character(start), end = as.character(end),
               scale = scale, mess = if (is.null(mess)) "none" else "default_mess_rates", generator = "fakehosp 0.2.0",
               elapsed_s = round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1))
  gen <- list(tables = tables, reference = ref[c("sites", "wards", "beds", "specialties", "consultants", "clinics", "exam_catalogue", "admission_method",
                                                  "admission_source", "discharge_destination", "discharge_method", "attendance_status",
                                                  "patient_source_setting", "ecds_codes")], truth = truth, mess_log = mess_log, meta = meta)
  if (!is.null(out_dir)) write_layer1(gen, out_dir)
  vmsg(verbose, "Done in ", meta$elapsed_s, " s")
  invisible(gen)
}


# Reassign rows dated after a patient's death to a living donor patient.
move_post_death_activity <- function(pts, dod, adm, ed, op, img, endo) {
  if (nrow(dod) == 0L) return(list(adm = adm, ed = ed, op = op, img = img, endo = endo))
  dead <- pts[dod, on = "mrn", nomatch = 0L]
  alive <- pts[is.na(date_of_death)]
  alive[, band := pmin(age_mid %/% 10, 9)]
  dead[, band := pmin(age_mid %/% 10, 9)]
  dead[, donor := NA_character_]
  for (s in c("1", "2")) for (b in 0:9) {
    pool <- alive[sex == s & band == b, mrn]
    if (length(pool) == 0L) pool <- alive[sex == s, mrn]
    k <- dead[sex == s & band == b, .N]
    if (k > 0L) dead[sex == s & band == b, donor := sample(pool, k, TRUE)]
  }
  map <- dead[, .(mrn, dod, donor)]
  fix <- function(dt, datecol, mrncol = "mrn") {
    if (is.null(dt) || nrow(dt) == 0L) return(dt)
    m <- map[match(dt[[mrncol]], map$mrn)]
    hit <- !is.na(m$mrn) & as.Date(dt[[datecol]]) > m$dod
    if (!any(hit)) return(dt)
    new <- m$donor[hit]
    set(dt, which(hit), mrncol, new)
    pn <- pts[match(new, pts$mrn)]
    if ("nhs_number" %in% names(dt)) set(dt, which(hit), "nhs_number", pn$nhs_number)
    if ("local_patient_identifier" %in% names(dt)) set(dt, which(hit), "local_patient_identifier", pn$ed_patient_id)
    if ("ris_patient_id" %in% names(dt)) set(dt, which(hit), "ris_patient_id", pn$ris_patient_id)
    if ("NHSNo" %in% names(dt)) set(dt, which(hit), "NHSNo", paste0(substr(pn$nhs_number, 1, 8), " ", substr(pn$nhs_number, 9, 11), " ", substr(pn$nhs_number, 12, 15)))
    if ("PatientRef" %in% names(dt)) set(dt, which(hit), "PatientRef", pn$endo_patient_ref)
    dt
  }
  adm$spells <- fix(adm$spells, "admit")
  adm$events <- fix(adm$events, "event_datetime")
  ed$attendances <- fix(ed$attendances, "activity_start_datetime")
  op$referrals <- fix(op$referrals, "referral_received_date")
  op$appointments <- fix(op$appointments, "appointment_datetime")
  img <- fix(img, "request_datetime")
  endo[, .d := as.Date(ProcDate, "%d/%m/%Y")]
  endo <- fix(endo, ".d", "HospNo")
  endo[, .d := NULL]
  list(adm = adm, ed = ed, op = op, img = img, endo = endo)
}
