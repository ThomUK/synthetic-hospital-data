# Mess injection: every catalogued imperfection, applied at a known rate and
# recorded in mess_log. See docs/MESS-CATALOGUE.md for the codes.

#' Default mess rates, keyed by catalogue code
#'
#' Set a code to 0 to switch it off; pass `mess = NULL` to [generate()] for a
#' clean dataset. Rates are proportions of the population named in the
#' catalogue entry.
#' @export
default_mess_rates <- function() {
  list(
    `M-PAS-01` = 0.005, `M-PAS-02` = 0.008, `M-PAS-03` = 0.02, `M-PAS-04` = 0.06, `M-PAS-05` = 0.015, `M-PAS-06` = 0.01,
    `M-PAS-07` = 0.012, `M-PAS-08` = 0.003, `M-PAS-09` = 0.08, `M-PAS-10` = 0.01, `M-PAS-11` = 0.03, `M-PAS-12` = 0.15,
    `M-PAS-13` = 0.04, `M-PAS-15` = 0.002, `M-PAS-16` = 0.40,
    `M-ED-01` = 0.04, `M-ED-02` = 0.001, `M-ED-03` = 0.60, `M-ED-04` = 0.05, `M-ED-05` = 0.20, `M-ED-06` = 0.03, `M-ED-07` = 0.02,
    `M-OP-01` = 0.03, `M-OP-02` = 0.03, `M-OP-03` = 0.015, `M-OP-04` = 0.10,
    `M-BOUNCE-01` = 0.015, `M-BOUNCE-02` = 0.008, `M-BOUNCE-03` = 0.60, `M-BOUNCE-04` = 0.02, `M-BOUNCE-05` = 0.03,
    `M-BOUNCE-06` = 0.02, `M-BOUNCE-07` = 0.01, `M-BOUNCE-08` = 0.025, `M-BOUNCE-09` = 0.015, `M-BOUNCE-10` = 0.02, `M-BOUNCE-11` = 0.01,
    `M-CT-01` = 0.07, `M-CT-02` = 0.10, `M-CT-03` = 0.30, `M-CT-05` = 0.85, `M-CT-06` = 0.002,
    `M-MR-01` = 0.15, `M-MR-02` = 0.40, `M-MR-03` = 0.12, `M-MR-04` = 1, `M-MR-05` = 0.01, `M-MR-06` = 0.06, `M-MR-07` = 0.04,
    `M-US-01` = 0.95, `M-US-02` = 0.08, `M-US-03` = 0.75, `M-US-04` = 0.25, `M-US-05` = 0.005,
    `M-RIS-01` = 0.06, `M-RIS-02` = 1, `M-RIS-03` = 0.40, `M-RIS-04` = 0.005, `M-RIS-05` = 0.03, `M-RIS-06` = 0.01,
    `M-EN-01` = 0.01, `M-EN-02` = 0.80, `M-EN-03` = 1, `M-EN-04` = 0.50, `M-EN-06` = 0.60, `M-EN-07` = 0.05, `M-EN-08` = 0.02,
    `M-X-02` = 1
  )
}

# ---- logging helper -------------------------------------------------------
new_mess_log <- function() {
  e <- new.env(); e$rows <- list(); e
}
log_mess <- function(ml, mess_id, table, row_key, field = NA_character_, original_value = NA_character_, note = NA_character_) {
  n <- length(row_key)
  if (n == 0L) return(invisible(NULL))
  ml$rows[[length(ml$rows) + 1L]] <- data.table(mess_id = mess_id, table = table, row_key = as.character(row_key),
                                                field = rep_len(field, n), original_value = rep_len(as.character(original_value), n),
                                                note = rep_len(note, n))
  invisible(NULL)
}
pick <- function(n, p) which(runif(n) < p)
# provisional message ids for rows added during injection (re-sequenced at the end)
reseq <- function(ev) { if (anyNA(ev$message_id)) ev[is.na(message_id), message_id := max(ev$message_id, na.rm = TRUE) + seq_len(.N)]; ev }
chr <- function(x) if (inherits(x, "POSIXct")) fmt_dt(x) else if (inherits(x, "Date")) fmt_d(x) else as.character(x)

# ---- orchestration ---------------------------------------------------------
inject_mess <- function(gen, rates, seed, start, end, verbose = FALSE) {
  stage_seed(seed, 9L)
  ml <- new_mess_log()
  r <- function(code) { v <- rates[[code]]; if (is.null(v)) 0 else v }
  start <- as.Date(start); end <- as.Date(end)
  T <- gen$tables; tr <- gen$truth; pts <- T$pas_patients
  ctx <- list(start = start, end = end, ref = gen$reference, pts = pts)
  vmsg(verbose, "Mess: PAS")
  res <- mess_pas(T, tr, r, ml, ctx);        T <- res$T; tr <- res$tr; rm(res); gc()
  vmsg(verbose, "Mess: ED")
  res <- mess_ed(T, tr, r, ml, ctx);         T <- res$T; tr <- res$tr
  vmsg(verbose, "Mess: outpatients")
  res <- mess_op(T, tr, r, ml, ctx);         T <- res$T; tr <- res$tr
  vmsg(verbose, "Mess: bouncing")
  res <- mess_bounce(T, tr, r, ml, ctx);     T <- res$T; tr <- res$tr; rm(res); gc()
  # apply the outpatient log removals and additions in one pass
  lg <- T$pas_op_status_log; T$pas_op_status_log <- NULL
  if (".keep" %in% names(lg)) { kept <- lg[.keep == TRUE]; rm(lg); gc(); kept[, .keep := NULL] } else kept <- lg
  if (length(T$op_log_add)) { add <- rbindlist(T$op_log_add); T$op_log_add <- NULL; lg <- rbindlist(list(kept, add)); rm(kept, add); gc() } else lg <- kept
  T$pas_op_status_log <- lg; rm(lg)
  vmsg(verbose, "Mess: radiology")
  res <- mess_ris(T, tr, r, ml, ctx);        T <- res$T; tr <- res$tr
  vmsg(verbose, "Mess: endoscopy")
  res <- mess_endo(T, tr, r, ml, ctx);       T <- res$T; tr <- res$tr
  vmsg(verbose, "Mess: identity and clocks")
  res <- mess_identity(T, tr, r, ml, ctx);   T <- res$T; tr <- res$tr
  res <- mess_clocks(T, tr, r, ml, ctx);     T <- res$T; tr <- res$tr
  # re-sequence the ADT log by recorded time
  setorder(T$pas_adt_events, recorded_datetime)
  T$pas_adt_events[, message_id := .I]
  setorder(T$ed_status_log, uec_activity_identifier, recorded_datetime); T$ed_status_log[, log_id := .I]
  setorder(T$pas_op_status_log, appointment_id, recorded_datetime); T$pas_op_status_log[, log_id := .I]
  mess_log <- if (length(ml$rows)) rbindlist(ml$rows) else data.table(mess_id = character(), table = character(), row_key = character(), field = character(), original_value = character(), note = character())
  mess_log[, mess_row := .I]
  list(tables = T, truth = tr, mess_log = mess_log)
}

# Ward-name variants used by M-PAS-09.
ward_variant <- function(w) {
  k <- sample.int(4L, length(w), TRUE)
  v <- w
  v[k == 1L] <- toupper(w[k == 1L])
  v[k == 2L] <- gsub(" ", "", w[k == 2L])
  v[k == 3L] <- sub("^Ward (\\d+)", "W\\1", w[k == 3L])
  v[k == 4L] <- paste0(w[k == 4L], " ")
  v
}

# ---- PAS -------------------------------------------------------------------
mess_pas <- function(T, tr, r, ml, ctx) {
  ev <- T$pas_adt_events; sp <- tr$spells
  start <- ctx$start
  key <- function(dt) dt$message_id
  # M-PAS-16 defaulted decision-to-admit date (RZ902 elective)
  i <- ev[, which(event_type == "A01" & site_code == "RZ902" & admission_method %in% c("11", "12"))]
  i <- i[runif(length(i)) < r("M-PAS-16")]
  if (length(i)) { log_mess(ml, "M-PAS-16", "pas_adt_events", ev$message_id[i], "decision_to_admit_date", chr(ev$decision_to_admit_date[i]), "defaulted to the admission date")
    ev[i, decision_to_admit_date := as.Date(event_datetime)] }
  # M-PAS-11 A08 correction: A01 carried the wrong specialty, A08 fixes it within the hour
  a01 <- ev[event_type == "A01" & specialty_code %in% c("300", "430", "100", "110")]
  i <- pick(nrow(a01), r("M-PAS-11"))
  if (length(i)) {
    wrong <- c("300" = "430", "430" = "300", "100" = "104", "110" = "100")
    fix <- a01[i]
    corr <- fix[, .(message_id = NA_integer_, event_type = "A08", event_datetime = event_datetime + mins(runif(.N, 5, 55)), recorded_datetime = event_datetime + mins(runif(.N, 6, 60)),
                    mrn, visit_number, site_code, ward = NA_character_, bed = NA_character_, consultant_code, specialty_code, admission_method = NA_character_, admission_source = NA_character_,
                    intended_management, patient_class, decision_to_admit_date = as.Date(NA), discharge_method = NA_character_, discharge_destination = NA_character_, discharge_ready_date = as.Date(NA), prior_mrn = NA_character_)]
    log_mess(ml, "M-PAS-11", "pas_adt_events", fix$message_id, "specialty_code", fix$specialty_code, "A01 specialty wrong; the A08 that follows is a correction, not a transfer of care")
    ev[message_id %in% fix$message_id, specialty_code := wrong[specialty_code]]
    ev <- reseq(rbind(ev, corr))
  }
  # M-PAS-12 ED as a ward: A01 at decision to admit on ward "ED", A02 to the real ward at the original admit time
  eda <- T$ed_attendances[!is.na(decided_to_admit_datetime), .(uec_activity_identifier, decided_to_admit_datetime)]
  cand <- sp[origin == "ed" & uec_activity_identifier %in% eda$uec_activity_identifier]
  i <- pick(nrow(cand), r("M-PAS-12"))
  if (length(i)) {
    c2 <- cand[i]; c2[, dta := eda$decided_to_admit_datetime[match(uec_activity_identifier, eda$uec_activity_identifier)]]
    a <- ev[event_type == "A01" & visit_number %in% c2$visit_number]
    a[, dta := c2$dta[match(visit_number, c2$visit_number)]]
    mv <- a[, .(message_id = NA_integer_, event_type = "A02", event_datetime, recorded_datetime = event_datetime + mins(runif(.N, 0, 10)), mrn, visit_number, site_code, ward, bed,
                consultant_code, specialty_code, admission_method = NA_character_, admission_source = NA_character_, intended_management, patient_class, decision_to_admit_date = as.Date(NA),
                discharge_method = NA_character_, discharge_destination = NA_character_, discharge_ready_date = as.Date(NA), prior_mrn = NA_character_)]
    log_mess(ml, "M-PAS-12", "pas_adt_events", a$message_id, "ward", a$ward, "A01 moved to decision-to-admit time on ward ED; arrival on the ward is the A02 that follows")
    ev[message_id %in% a$message_id, `:=`(ward = "ED", bed = NA_character_, event_datetime = a$dta[match(message_id, a$message_id)], recorded_datetime = a$dta[match(message_id, a$message_id)] + mins(runif(.N, 0, 10)))]
    ev <- reseq(rbind(ev, mv))
  }
  # M-PAS-05 cancelled admission: elective A01 then A11, patient never arrived; later events removed
  el <- sp[origin %in% c("elective", "planned") & !open_at_end]
  i <- pick(nrow(el), r("M-PAS-05"))
  if (length(i)) {
    v <- el$visit_number[i]
    a <- ev[event_type == "A01" & visit_number %in% v]
    a11 <- a[, .(message_id = NA_integer_, event_type = "A11", event_datetime = event_datetime + mins(runif(.N, 30, 180)), recorded_datetime = event_datetime + mins(runif(.N, 31, 190)), mrn, visit_number, site_code,
                 ward, bed = NA_character_, consultant_code, specialty_code, admission_method = NA_character_, admission_source = NA_character_, intended_management, patient_class, decision_to_admit_date = as.Date(NA),
                 discharge_method = NA_character_, discharge_destination = NA_character_, discharge_ready_date = as.Date(NA), prior_mrn = NA_character_)]
    gone <- ev[visit_number %in% v & event_type %in% c("A02", "A03", "A08")]
    log_mess(ml, "M-PAS-05", "pas_adt_events", a$message_id, "event_type", "A01", "admission cancelled by A11; the spell never happened")
    log_mess(ml, "M-PAS-05", "pas_adt_events", gone$message_id, "event_type", gone$event_type, "event removed: admission was cancelled")
    ev <- reseq(rbind(ev[!(visit_number %in% v & event_type %in% c("A02", "A03", "A08"))], a11))
    sp[visit_number %in% v, cancelled := TRUE]
  }
  sp[is.na(cancelled), cancelled := FALSE]
  # M-PAS-06 cancelled discharge and M-BOUNCE-08 discharge bounce (same mechanism, different timing)
  dis_bounce <- function(code, p, hours_back, hours_fwd, with_a02) {
    a03 <- ev[event_type == "A03" & visit_number %in% sp[!cancelled & los >= 1 & !died, visit_number]]
    i <- pick(nrow(a03), p); if (!length(i)) return(invisible())
    a <- a03[i]
    t13 <- a$event_datetime + hours(runif(nrow(a), hours_back[1], hours_back[2]))
    t03 <- a$event_datetime + hours(runif(nrow(a), hours_fwd[1], hours_fwd[2]))
    mk <- function(type, t, ward = NA_character_) a[, .(message_id = NA_integer_, event_type = type, event_datetime = t, recorded_datetime = t + mins(runif(.N, 0, 10)), mrn, visit_number, site_code, ward = ward, bed = NA_character_,
                                                        consultant_code, specialty_code, admission_method = NA_character_, admission_source = NA_character_, intended_management, patient_class, decision_to_admit_date = as.Date(NA),
                                                        discharge_method = if (type == "A03") a$discharge_method else NA_character_, discharge_destination = if (type == "A03") a$discharge_destination else NA_character_,
                                                        discharge_ready_date = as.Date(NA), prior_mrn = NA_character_)]
    new <- rbind(mk("A13", t13), if (with_a02) mk("A02", t13 + mins(runif(nrow(a), 5, 40)), a$ward) else NULL, mk("A03", t03, a$ward))
    log_mess(ml, code, "pas_adt_events", a$message_id, "event_datetime", chr(a$event_datetime), "first A03 cancelled by A13; the later A03 is the real discharge")
    ev <<- reseq(rbind(ev, new))
    sp[visit_number %in% a$visit_number, `:=`(discharge = t03[match(visit_number, a$visit_number)])]
    sp[visit_number %in% a$visit_number, los := as.numeric(as.Date(discharge) - as.Date(admit))]
  }
  dis_bounce("M-PAS-06", r("M-PAS-06"), c(1, 4), c(6, 30), FALSE)
  dis_bounce("M-BOUNCE-08", r("M-BOUNCE-08"), c(1, 5), c(14, 26), TRUE)
  # M-BOUNCE-09 admit, cancel admit, admit again under a new visit number
  edsp <- sp[origin == "ed" & !cancelled]
  i <- pick(nrow(edsp), r("M-BOUNCE-09"))
  if (length(i)) {
    v <- edsp$visit_number[i]
    a <- ev[event_type == "A01" & visit_number %in% v]
    newv <- paste0(sub("^V", "V9", a$visit_number))
    a11 <- a[, .(message_id = NA_integer_, event_type = "A11", event_datetime = event_datetime + hours(runif(.N, 1, 3)), recorded_datetime = event_datetime + hours(runif(.N, 1, 3)) + mins(5), mrn, visit_number, site_code,
                 ward, bed = NA_character_, consultant_code, specialty_code, admission_method = NA_character_, admission_source = NA_character_, intended_management, patient_class, decision_to_admit_date = as.Date(NA),
                 discharge_method = NA_character_, discharge_destination = NA_character_, discharge_ready_date = as.Date(NA), prior_mrn = NA_character_)]
    a01b <- copy(a); a01b[, `:=`(message_id = NA_integer_, visit_number = newv, event_datetime = event_datetime + hours(runif(.N, 3, 5)), ward = "AMU 2")]
    a01b[, recorded_datetime := event_datetime + mins(runif(.N, 0, 10))]
    later <- ev[visit_number %in% v & event_type %in% c("A02", "A03", "A08")]
    log_mess(ml, "M-BOUNCE-09", "pas_adt_events", a$message_id, "visit_number", a$visit_number, "admission cancelled and re-admitted under a new visit number")
    log_mess(ml, "M-BOUNCE-09", "pas_adt_events", later$message_id, "visit_number", later$visit_number, "moved to the re-admission's visit number")
    ev[visit_number %in% v & event_type %in% c("A02", "A03", "A08"), visit_number := newv[match(visit_number, v)]]
    ev <- reseq(rbind(ev, a11, a01b))
    sp[visit_number %in% v, `:=`(visit_number = newv[match(visit_number, v)])]
    tr$stays[visit_number %in% v, visit_number := newv[match(visit_number, v)]]
  }
  # M-PAS-02 missing discharge for spells followed by a later admission
  nxt <- sp[!cancelled & !open_at_end][order(mrn, admit)][, has_next := shift(mrn, -1) == mrn][has_next == TRUE]
  i <- pick(nrow(nxt), r("M-PAS-02"))
  if (length(i)) {
    g <- ev[event_type == "A03" & visit_number %in% nxt$visit_number[i]]
    log_mess(ml, "M-PAS-02", "pas_adt_events", g$message_id, "event_type", "A03", "discharge message never sent; spell looks open until the next admission")
    ev <- ev[!(message_id %in% g$message_id)]
  }
  # M-PAS-01 duplicate events
  i <- ev[, which(event_type %in% c("A02", "A03"))]; i <- i[runif(length(i)) < r("M-PAS-01")]
  if (length(i)) { d <- copy(ev[i]); d[, `:=`(message_id = NA_integer_, recorded_datetime = recorded_datetime + runif(.N, 2, 50))]
    log_mess(ml, "M-PAS-01", "pas_adt_events", ev$message_id[i], NA, NA, "this event is sent twice"); ev <- rbind(ev, d) }
  # M-PAS-04 batch-entered transfers at shift handover
  i <- ev[, which(event_type == "A02")]; i <- i[runif(length(i)) < r("M-PAS-04")]
  if (length(i)) {
    log_mess(ml, "M-PAS-04", "pas_adt_events", ev$message_id[i], "event_datetime", chr(ev$event_datetime[i]), "entered in the handover batch; time rounded to the hour")
    h <- as.numeric(format(ev$event_datetime[i], "%H", tz = "UTC"))
    day0 <- as_dt(as.Date(ev$event_datetime[i], tz = "UTC"))
    batch <- day0 + hours(ifelse(h < 7, 7, ifelse(h < 19, 19, 31)))
    ev[i, `:=`(event_datetime = day0 + hours(h), recorded_datetime = batch + mins(runif(.N, 0, 25)))]
  }
  # M-PAS-10 zero-length ward stay and M-BOUNCE-10 three-move bounce
  for (code in c("M-PAS-10", "M-BOUNCE-10")) {
    i <- ev[, which(event_type == "A02" & !is.na(ward))]; i <- i[runif(length(i)) < r(code)]
    if (!length(i)) next
    a <- ev[i]; wards <- ctx$ref$wards[kind == "bed", ward_name]
    wrong <- a[, .(message_id = NA_integer_, event_type = "A02", event_datetime = event_datetime - mins(runif(.N, 1, 3)), recorded_datetime = event_datetime - mins(runif(.N, 0, 2)), mrn, visit_number, site_code,
                   ward = sample(wards, .N, TRUE), bed = NA_character_, consultant_code, specialty_code, admission_method = NA_character_, admission_source = NA_character_, intended_management, patient_class,
                   decision_to_admit_date = as.Date(NA), discharge_method = NA_character_, discharge_destination = NA_character_, discharge_ready_date = as.Date(NA), prior_mrn = NA_character_)]
    new <- wrong
    if (code == "M-BOUNCE-10") {
      back <- copy(a); back[, `:=`(message_id = NA_integer_, event_datetime = wrong$event_datetime + mins(2), recorded_datetime = wrong$event_datetime + mins(3))]
      # the original A02 becomes the third move an hour later
      ev[i, `:=`(event_datetime = event_datetime + mins(60), recorded_datetime = recorded_datetime + mins(60))]
      new <- rbind(wrong, back[, names(wrong), with = FALSE])
    }
    log_mess(ml, code, "pas_adt_events", a$message_id, "ward", a$ward, if (code == "M-PAS-10") "preceded by a transfer to the wrong ward, corrected within minutes" else "moved out, back and out again within the hour")
    ev <- reseq(rbind(ev, new))
  }
  # M-BOUNCE-11 specialty bouncing 300 <-> 430
  med <- sp[!cancelled & specialty_first == "300" & los >= 1 & !day_case]
  i <- pick(nrow(med), r("M-BOUNCE-11"))
  if (length(i)) {
    a <- ev[event_type == "A01" & visit_number %in% med$visit_number[i]]
    mk <- function(k, spec) a[, .(message_id = NA_integer_, event_type = "A08", event_datetime = event_datetime + hours(k * runif(.N, 0.6, 1.3)), recorded_datetime = event_datetime + hours(k * runif(.N, 0.6, 1.3)) + mins(3), mrn, visit_number, site_code,
                                  ward = NA_character_, bed = NA_character_, consultant_code, specialty_code = spec, admission_method = NA_character_, admission_source = NA_character_, intended_management, patient_class,
                                  decision_to_admit_date = as.Date(NA), discharge_method = NA_character_, discharge_destination = NA_character_, discharge_ready_date = as.Date(NA), prior_mrn = NA_character_)]
    log_mess(ml, "M-BOUNCE-11", "pas_adt_events", a$message_id, "specialty_code", "300", "specialty flips 300/430/300/430 in a morning; only the last is a transfer of care")
    ev <- reseq(rbind(ev, mk(1, "430"), mk(2, "300"), mk(3, "430")))
  }
  # M-PAS-03 out-of-order arrival: an A02 recorded after the A03
  cand <- ev[event_type %in% c("A02", "A03"), .N, by = visit_number][N >= 2, visit_number]
  cand <- cand[runif(length(cand)) < r("M-PAS-03")]
  if (length(cand)) {
    a02 <- ev[event_type == "A02" & visit_number %in% cand][, .SD[1], by = visit_number]
    a03 <- ev[event_type == "A03" & visit_number %in% cand][, .(visit_number, rec03 = recorded_datetime)]
    a02 <- merge(a02, a03, by = "visit_number")
    log_mess(ml, "M-PAS-03", "pas_adt_events", a02$message_id, "recorded_datetime", chr(a02$recorded_datetime), "received after the discharge message")
    ev[message_id %in% a02$message_id, recorded_datetime := a02$rec03[match(message_id, a02$message_id)] + mins(runif(.N, 5, 240))]
  }
  # M-PAS-13 Friday discharges recorded on Monday
  i <- ev[, which(event_type == "A03" & as.POSIXlt(event_datetime)$wday == 5L)]; i <- i[runif(length(i)) < r("M-PAS-13")]
  if (length(i)) { log_mess(ml, "M-PAS-13", "pas_adt_events", ev$message_id[i], "recorded_datetime", chr(ev$recorded_datetime[i]), "recorded 1-3 days late")
    ev[i, recorded_datetime := recorded_datetime + days(runif(.N, 1, 3))] }
  # M-PAS-15 activity after death: a demographic A08 on the last spell
  dead <- T$pas_patients[!is.na(date_of_death)]
  i <- pick(nrow(dead), r("M-PAS-15"))
  if (length(i)) {
    last <- ev[mrn %in% dead$mrn[i] & event_type == "A03"][, .SD[which.max(event_datetime)], by = mrn]
    if (nrow(last)) {
      up <- last[, .(message_id = NA_integer_, event_type = "A08", event_datetime = event_datetime + days(runif(.N, 2, 20)), recorded_datetime = event_datetime + days(runif(.N, 2, 20)) + mins(1), mrn, visit_number, site_code,
                     ward = NA_character_, bed = NA_character_, consultant_code, specialty_code, admission_method = NA_character_, admission_source = NA_character_, intended_management, patient_class,
                     decision_to_admit_date = as.Date(NA), discharge_method = NA_character_, discharge_destination = NA_character_, discharge_ready_date = as.Date(NA), prior_mrn = NA_character_)]
      log_mess(ml, "M-PAS-15", "pas_adt_events", last$message_id, "event_datetime", chr(last$event_datetime), "a demographic update recorded after the date of death")
      ev <- reseq(rbind(ev, up))
    }
  }
  # M-PAS-09 ward name drift (plus the two renames carried in ref_wards validity)
  ren <- data.table(ward_name = c("Ward 11 Frailty", "Ward 4 Gastro"), old_name = c("Ward 11 Elderly Care", "Ward 4 GI Medicine"), valid_from = as.Date(c("2024-06-01", "2024-11-01")))
  for (k in seq_len(nrow(ren))) ev[ward == ren$ward_name[k] & event_datetime < as_dt(ren$valid_from[k]), ward := ren$old_name[k]]
  i <- ev[, which(!is.na(ward) & !(ward %in% c("ED", "ICU", "HDU", "SAU", "SDEC", "CCU", "UTC")))]; i <- i[runif(length(i)) < r("M-PAS-09")]
  if (length(i)) { log_mess(ml, "M-PAS-09", "pas_adt_events", ev$message_id[i], "ward", ev$ward[i], "ward name typed differently"); ev[i, ward := ward_variant(ward)] }
  T$pas_adt_events <- ev; tr$spells <- sp
  list(T = T, tr = tr)
}

# ---- ED --------------------------------------------------------------------
mess_ed <- function(T, tr, r, ml, ctx) {
  ed <- T$ed_attendances; lg <- T$ed_status_log; pts <- ctx$pts
  K <- "uec_activity_identifier"
  # true re-attendance category first (not logged), then M-ED-06 errors
  setorder(ed, mrn, activity_start_datetime)
  ed[, prev := shift(activity_start_datetime), by = mrn]
  re <- ed[, which(!is.na(prev) & as.numeric(activity_start_datetime - prev, units = "hours") <= 72)]
  ed[re, attendance_category := "2"]
  i <- re[runif(length(re)) < r("M-ED-06")]
  if (length(i)) { log_mess(ml, "M-ED-06", "ed_attendances", ed[[K]][i], "attendance_category", "2", "unplanned re-attendance within 72 h recorded as a first attendance"); ed[i, attendance_category := "1"] }
  ed[, prev := NULL]
  # M-ED-03 departure auto-closed at decision to admit
  i <- ed[, which(!is.na(decided_to_admit_datetime))]; i <- i[runif(length(i)) < r("M-ED-03")]
  if (length(i)) { log_mess(ml, "M-ED-03", "ed_attendances", ed[[K]][i], "activity_end_timestamp", chr(ed$activity_end_timestamp[i]), "ED record auto-closed when the admission was keyed")
    newt <- ed$decided_to_admit_datetime[i] + mins(runif(length(i), 0, 2))
    ed[i, activity_end_timestamp := newt]
    lg[uec_activity_identifier %in% ed[[K]][i] & status == "departed", recorded_datetime := ed$activity_end_timestamp[match(uec_activity_identifier, ed[[K]])] + mins(runif(.N, 0, 2))] }
  # M-ED-04 breach-shaped departures
  i <- ed[, which(is.na(decided_to_admit_datetime) & discharge_status == "Treatment complete" & as.numeric(activity_end_timestamp - activity_start_datetime, units = "hours") > 4)]
  i <- i[runif(length(i)) < r("M-ED-04") / 0.4]
  if (length(i)) { log_mess(ml, "M-ED-04", "ed_attendances", ed[[K]][i], "activity_end_timestamp", chr(ed$activity_end_timestamp[i]), "departure recorded just inside four hours")
    newt <- ed$activity_start_datetime[i] + mins(runif(length(i), 235, 239))
    ed[i, activity_end_timestamp := newt]
    lg[uec_activity_identifier %in% ed[[K]][i] & status == "departed", recorded_datetime := ed$activity_end_timestamp[match(uec_activity_identifier, ed[[K]])] + mins(runif(.N, 0, 2))] }
  # M-ED-05 missing assessment times for UTC
  i <- ed[, which(uec_activity_type == "UTC" & !is.na(initial_assessment_timestamp))]; i <- i[runif(length(i)) < r("M-ED-05")]
  if (length(i)) { log_mess(ml, "M-ED-05", "ed_attendances", ed[[K]][i], "initial_assessment_timestamp", chr(ed$initial_assessment_timestamp[i]), "streamed to UTC: assessment time not recorded")
    ed[i, initial_assessment_timestamp := as_dt(NA)]
    lg <- lg[!(uec_activity_identifier %in% ed[[K]][i] & status == "triaged")] }
  # M-BOUNCE-05 departure bounce, M-BOUNCE-06 DTA bounce, M-BOUNCE-07 triage bounce
  adm <- ed[, which(!is.na(decided_to_admit_datetime))]
  i <- adm[runif(length(adm)) < r("M-BOUNCE-05")]
  if (length(i)) {
    t1 <- ed$activity_end_timestamp[i]; ids <- ed[[K]][i]
    log_mess(ml, "M-BOUNCE-05", "ed_attendances", ids, "activity_end_timestamp", chr(t1), "departed, re-opened, departed again 90 minutes later")
    ed[i, activity_end_timestamp := t1 + mins(90)]
    lg <- rbind(lg, data.table(uec_activity_identifier = ids, status = c(rep("re-opened", length(ids)), rep("departed", length(ids))), recorded_datetime = c(t1 + mins(10), t1 + mins(91)), user_role = c(rep("nurse", length(ids)), rep("bed manager", length(ids))), log_id = NA_integer_))
  }
  i <- adm[runif(length(adm)) < r("M-BOUNCE-06")]
  if (length(i)) {
    t <- ed$decided_to_admit_datetime[i]; ids <- ed[[K]][i]
    log_mess(ml, "M-BOUNCE-06", "ed_attendances", ids, "decided_to_admit_datetime", chr(t), "DTA set, removed when SDEC accepted, re-set three hours later")
    ed[i, decided_to_admit_datetime := t + hours(3)]
    ed[i, activity_end_timestamp := pmax(activity_end_timestamp, decided_to_admit_datetime + mins(30))]
    lg <- rbind(lg, data.table(uec_activity_identifier = ids, status = c(rep("decision to admit removed", length(ids)), rep("decision to admit", length(ids))), recorded_datetime = c(t + mins(30), t + hours(3)), user_role = "clinician", log_id = NA_integer_))
  }
  i <- ed[, which(!is.na(initial_assessment_timestamp))]; i <- i[runif(length(i)) < r("M-BOUNCE-07")]
  if (length(i)) {
    ids <- ed[[K]][i]; t <- ed$initial_assessment_timestamp[i]; a0 <- ed$acuity[i]
    a1 <- pmin(pmax(a0 + sample(c(-1L, 1L), length(i), TRUE), 1L), 5L)
    log_mess(ml, "M-BOUNCE-07", "ed_attendances", ids, "acuity", a0, "triaged twice after a wrong-patient selection; second acuity survived")
    ed[i, acuity := a1]
    lg <- rbind(lg, data.table(uec_activity_identifier = ids, status = c(rep("arrived", length(ids)), rep("triaged", length(ids))), recorded_datetime = c(t + mins(4), t + mins(9)), user_role = c(rep("receptionist", length(ids)), rep("nurse", length(ids))), log_id = NA_integer_))
  }
  # M-ED-01 MRN not populated, M-ED-02 wrong MRN, M-ED-07 hand-typed NHS number
  i <- pick(nrow(ed), r("M-ED-01"))
  if (length(i)) { log_mess(ml, "M-ED-01", "ed_attendances", ed[[K]][i], "mrn", ed$mrn[i], "interface failed to match"); ed[i, mrn := NA_character_] }
  i <- pick(nrow(ed), r("M-ED-02"))
  if (length(i)) { log_mess(ml, "M-ED-02", "ed_attendances", ed[[K]][i], "mrn", ed$mrn[i], "interface matched a different person with the same sex and birth year")
    ed[i, mrn := pts$mrn[sample.int(nrow(pts), length(i), TRUE)]] }
  i <- pick(nrow(ed), r("M-ED-07"))
  # the fake_ prefix survives every formatting variant so no value can ever pass for a real NHS number
  if (length(i)) { log_mess(ml, "M-ED-07", "ed_attendances", ed[[K]][i], "nhs_number", ed$nhs_number[i], "typed by hand: spaces in 3-3-4 groups")
    d <- sub("^fake_", "", ed$nhs_number[i]); ed[i, nhs_number := paste0("fake_", substr(d, 1, 3), " ", substr(d, 4, 6), " ", substr(d, 7, 10))] }
  setorder(ed, activity_start_datetime)
  T$ed_attendances <- ed; T$ed_status_log <- lg
  list(T = T, tr = tr)
}

# ---- outpatients -----------------------------------------------------------
mess_op <- function(T, tr, r, ml, ctx) {
  ap <- T$pas_outpatient_appointments; lg <- T$pas_op_status_log; rf <- T$pas_referrals
  K <- "appointment_id"
  if (!".keep" %in% names(lg)) lg[, .keep := TRUE]
  lg_add <- list(); drop_outcome <- character(); drop_all <- character()
  # M-OP-01 extra hospital-cancelled slot before an attended one (rebooking churn)
  i <- ap[, which(attendance_status %in% c("5", "6"))]; i <- i[runif(length(i)) < r("M-OP-01")]
  if (length(i)) {
    d <- copy(ap[i]); d[, `:=`(appointment_id = paste0(appointment_id, "C"), attendance_status = "4", outcome = NA_character_,
                               appointment_datetime = appointment_datetime - days(round(runif(.N, 3, 21))), dna_date = as.Date(NA))]
    d[, cancelled_datetime := appointment_datetime - days(round(runif(.N, 1, 10)))]
    d[cancelled_datetime <= booked_datetime, cancelled_datetime := booked_datetime + hours(2)]
    log_mess(ml, "M-OP-01", "pas_outpatient_appointments", d$appointment_id, NA, NA, "hospital-cancelled slot that was rebooked as the attended one")
    ap <- rbind(ap, d)
    lg_add$op01a <- d[, .(appointment_id, field = "attendance_status", old_value = NA_character_, new_value = "booked", recorded_datetime = booked_datetime, workstation = "central booking", user_id = sprintf("U%04d", sample.int(600L, .N, TRUE)), log_id = NA_integer_)]
    lg_add$op01b <- d[, .(appointment_id, field = "attendance_status", old_value = "booked", new_value = "4", recorded_datetime = cancelled_datetime, workstation = "central booking", user_id = sprintf("U%04d", sample.int(600L, .N, TRUE)), log_id = NA_integer_)]
  }
  # M-OP-02 telephone contact "attended" with no outcome
  i <- ap[, which(attendance_status == "5" & first_attendance %in% c("3", "4") & !is.na(outcome))]; i <- i[runif(length(i)) < r("M-OP-02")]
  if (length(i)) { log_mess(ml, "M-OP-02", "pas_outpatient_appointments", ap[[K]][i], "outcome", ap$outcome[i], "status 5 defaulted for a telephone contact nobody closed")
    drop_outcome <- ap[[K]][i]; ap[i, outcome := NA_character_] }
  # M-OP-03 referral lost: appointments removed, clock never stopped
  i <- rf[, which(!is.na(rtt_pathway_id) & !is.na(rtt_period_end_date))]; i <- i[runif(length(i)) < r("M-OP-03")]
  if (length(i)) {
    rid <- rf$referral_id[i]
    gone <- ap[referral_id %in% rid]
    log_mess(ml, "M-OP-03", "pas_referrals", rid, "rtt_period_end_date", chr(rf$rtt_period_end_date[i]), "referral lost: no appointments were ever booked and the clock still runs")
    log_mess(ml, "M-OP-03", "pas_outpatient_appointments", gone$appointment_id, NA, NA, "removed: the referral was lost")
    rf[i, `:=`(rtt_period_end_date = as.Date(NA), rtt_period_status = "20")]
    drop_all <- gone$appointment_id; ap <- ap[!(referral_id %in% rid)]
  }
  # M-OP-04 clock stop recorded late
  i <- rf[, which(!is.na(rtt_period_end_date))]; i <- i[runif(length(i)) < r("M-OP-04")]
  if (length(i)) { log_mess(ml, "M-OP-04", "pas_referrals", rf$referral_id[i], "rtt_period_end_date", chr(rf$rtt_period_end_date[i]), "clock stop validated 1-3 weeks after the event")
    rf[i, rtt_period_end_date := rtt_period_end_date + round(runif(.N, 7, 21))] }
  if (length(drop_all)) lg[appointment_id %in% drop_all, .keep := FALSE]
  if (length(drop_outcome)) lg[appointment_id %in% drop_outcome & field == "outcome", .keep := FALSE]
  T$op_log_add <- c(T$op_log_add, lg_add)
  T$pas_outpatient_appointments <- ap; T$pas_op_status_log <- lg; T$pas_referrals <- rf
  list(T = T, tr = tr)
}

# ---- bouncing in the outpatient audit trail --------------------------------
mess_bounce <- function(T, tr, r, ml, ctx) {
  ap <- T$pas_outpatient_appointments; lg <- T$pas_op_status_log
  if (!".keep" %in% names(lg)) lg[, .keep := TRUE]
  lg_add <- list(); drop_arrived <- character()
  att <- ap[, which(attendance_status %in% c("5", "6") & !is.na(appointment_datetime))]
  mkrow <- function(ids, field, old, new, t, ws = "clinic reception") data.table(appointment_id = ids, field = field, old_value = old, new_value = new, recorded_datetime = t, workstation = ws, user_id = sprintf("U%04d", sample.int(600L, length(ids), TRUE)), log_id = NA_integer_)
  # M-BOUNCE-01 DNA -> discharged -> arrived within minutes
  i <- att[runif(length(att)) < r("M-BOUNCE-01")]
  if (length(i)) {
    ids <- ap$appointment_id[i]; t0 <- ap$appointment_datetime[i] + mins(runif(length(i), 5, 25))
    log_mess(ml, "M-BOUNCE-01", "pas_op_status_log", ids, "attendance_status", ap$attendance_status[i], "DNA, discharged, arrived inside four minutes; final value is attended")
    drop_arrived <- ids
    rev <- runif(length(i)) < 0.8
    lg_add$b01 <- rbind(mkrow(ids, "attendance_status", "booked", "3", t0), mkrow(ids, "outcome", NA_character_, "1", t0 + mins(1), "clinic reception"),
                        mkrow(ids, "attendance_status", "3", "arrived", t0 + mins(3)), mkrow(ids[rev], "outcome", "1", NA_character_, t0[rev] + mins(20)))
  }
  # M-BOUNCE-02 attended/DNA flip-flop across the close-down batch; ends as DNA
  i <- att[runif(length(att)) < r("M-BOUNCE-02")]
  if (length(i)) {
    ids <- ap$appointment_id[i]; tb <- as_dt(as.Date(ap$appointment_datetime[i])) + hours(17) + mins(58)
    log_mess(ml, "M-BOUNCE-02", "pas_outpatient_appointments", ids, "attendance_status", ap$attendance_status[i], "two clerks reconciling one list; the record ends as DNA though the patient was seen")
    ap[i, `:=`(attendance_status = "3", dna_date = as.Date(appointment_datetime))]
    lg_add$b02 <- rbind(mkrow(ids, "attendance_status", "5", "3", tb), mkrow(ids, "attendance_status", "3", "5", tb), mkrow(ids, "attendance_status", "5", "3", tb))
  }
  # M-BOUNCE-03 clinic closed in a batch at 17:58
  ap[, clinic_day := paste(clinic_code, as.Date(appointment_datetime))]
  cl <- unique(ap$clinic_day); cl <- cl[runif(length(cl)) < r("M-BOUNCE-03")]
  if (length(cl)) {
    ids <- ap[clinic_day %in% cl & attendance_status %in% c("5", "6"), appointment_id]
    sel <- lg[, which(appointment_id %in% ids & new_value %in% c("arrived", "5", "6"))]
    # logged once per clinic session (row_key = clinic code and date), not per audit row
    log_mess(ml, "M-BOUNCE-03", "pas_op_status_log", cl, "recorded_datetime", NA, "arrived and seen for the whole session written at clinic close-down")
    lg[sel, recorded_datetime := as_dt(as.Date(recorded_datetime)) + hours(17) + mins(58) + runif(.N, 0, 50)]
  }
  ap[, clinic_day := NULL]
  # M-BOUNCE-04 outcome flips; ends as waiting list
  i <- att[runif(length(att)) < r("M-BOUNCE-04") & !is.na(ap$outcome[att])]
  if (length(i)) {
    ids <- ap$appointment_id[i]; t0 <- ap$appointment_datetime[i] + hours(runif(length(i), 1, 4))
    log_mess(ml, "M-BOUNCE-04", "pas_outpatient_appointments", ids, "outcome", ap$outcome[i], "outcome edited four times in an afternoon; ends as added to waiting list")
    ap[i, outcome := "5"]
    lg_add$b04 <- rbind(mkrow(ids, "outcome", ap$outcome[i], "2", t0 + mins(10)), mkrow(ids, "outcome", "2", "1", t0 + mins(40)), mkrow(ids, "outcome", "1", "5", t0 + mins(75)))
  }
  if (length(drop_arrived)) lg[appointment_id %in% drop_arrived & new_value == "arrived", .keep := FALSE]
  T$op_log_add <- c(T$op_log_add, lg_add)
  T$pas_outpatient_appointments <- ap; T$pas_op_status_log <- lg
  list(T = T, tr = tr)
}

# ---- radiology -------------------------------------------------------------
mess_ris <- function(T, tr, r, ml, ctx) {
  x <- T$ris_imaging; K <- "accession_number"; start <- ctx$start
  x[, mi := month_index(as.Date(request_datetime), start) + 1L]
  # CT
  ct <- x[, which(modality == "CT")]
  i <- ct[runif(length(ct)) < r("M-CT-01") & x$status[ct] == "verified"]
  if (length(i)) { d <- copy(x[i]); d[, `:=`(accession_number = paste0(accession_number, "X"), status = "cancelled", cancel_reason = rcat(.N, c("rebooked", "duplicate request", "patient unwell"), c(6, 3, 1)),
                                           request_datetime = request_datetime - mins(runif(.N, 3, 30)), scan_start_datetime = as_dt(NA), scan_end_datetime = as_dt(NA), reported_datetime = as_dt(NA), verified_datetime = as_dt(NA), vetted_datetime = as_dt(NA))]
    d[, request_received_datetime := request_datetime]
    log_mess(ml, "M-CT-01", "ris_imaging", d$accession_number, NA, NA, "cancelled-and-rebooked request kept as its own row"); x <- rbind(x, d) }
  i <- ct[runif(length(ct)) < r("M-CT-02") & x$patient_source_setting[ct] == "05" & x$status[ct] == "verified"]
  if (length(i)) { log_mess(ml, "M-CT-02", "ris_imaging", x[[K]][i], "request_datetime", chr(x$request_datetime[i]), "scan done on a verbal request; order entered afterwards")
    x[i, `:=`(request_datetime = scan_start_datetime + mins(runif(.N, 10, 60)))]; x[i, request_received_datetime := request_datetime] }
  i <- ct[runif(length(ct)) < r("M-CT-03")]
  if (length(i)) { log_mess(ml, "M-CT-03", "ris_imaging", x[[K]][i], "body_area", x$body_area[i], "body area blank; free text carries it")
    x[i, `:=`(body_area = NA_character_, exam_description = rcat(.N, c("CT abdo pelv w contrast", "CTAP", "CT A/P", "ct chest", "CT HEAD", "ct kub", "CT thorax"), rep(1, 7)))] }
  i <- ct[runif(length(ct)) < r("M-CT-05") & !is.na(x$reported_datetime[ct])]
  if (length(i)) { log_mess(ml, "M-CT-05", "ris_imaging", x[[K]][i], "verified_datetime", chr(x$verified_datetime[i]), "auto-verified by the reporting radiologist"); x[i, verified_datetime := reported_datetime] }
  i <- ct[runif(length(ct)) < r("M-CT-06") & x$mi[ct] %in% 20:22]
  if (length(i)) { j <- ct[runif(length(ct)) < 0.5 & x$mi[ct] %in% 20:22]; j <- j[seq_len(min(length(i), length(j)))]; i <- i[seq_along(j)]
    log_mess(ml, "M-CT-06", "ris_imaging", x[[K]][j], "accession_number", x[[K]][j], "accession number reused after the RIS upgrade"); x[j, accession_number := x[[K]][i]] }
  # MR
  mr <- x[, which(modality == "MR" & status == "verified")]
  i <- mr[runif(length(mr)) < r("M-MR-01")]
  if (length(i)) { log_mess(ml, "M-MR-01", "ris_imaging", x[[K]][i], "reported_datetime", chr(x$reported_datetime[i]), "backfilled in a Friday batch")
    fri <- as.Date(x$scan_end_datetime[i]) + (5 - as.POSIXlt(x$scan_end_datetime[i])$wday) %% 7 + 7
    x[i, `:=`(reported_datetime = as_dt(fri) + hours(15) + mins(30), verified_datetime = as_dt(fri) + hours(15) + mins(45))] }
  i <- mr[runif(length(mr)) < r("M-MR-02")]
  if (length(i)) { log_mess(ml, "M-MR-02", "ris_imaging", x[[K]][i], "scan_end_datetime", chr(x$scan_end_datetime[i]), "end time derived from the slot"); x[i, scan_end_datetime := scan_start_datetime + mins(slot_minutes)] }
  i <- mr[runif(length(mr)) < r("M-MR-03")]
  if (length(i)) { log_mess(ml, "M-MR-03", "ris_imaging", x[[K]][i], "body_area", x$body_area[i], "body area typed inconsistently")
    x[i, body_area := paste0(sample(c("", "", "L ", "R "), .N, TRUE), ifelse(runif(.N) < 0.5, tolower(body_area), body_area), sample(c("", " (L)", " region", ""), .N, TRUE))] }
  if (r("M-MR-04") > 0) { i <- mr[x$patient_source_setting[mr] %in% c("03", "04") & (x$mi[mr] %% 12) %in% 3:6]
    log_mess(ml, "M-MR-04", "ris_imaging", x[[K]][i], "reported_datetime", chr(x$reported_datetime[i]), "summer reporting backlog")
    x[i, `:=`(reported_datetime = reported_datetime + days(rln(.N, 12, 0.6)))]; x[i, verified_datetime := reported_datetime + mins(runif(.N, 5, 90))] }
  i <- mr[runif(length(mr)) < r("M-MR-05") & !is.na(x$vetted_datetime[mr])]
  if (length(i)) { log_mess(ml, "M-MR-05", "ris_imaging", x[[K]][i], "vetted_datetime", chr(x$vetted_datetime[i]), "vetting clock defaulted on the form"); x[i, vetted_datetime := request_datetime - days(1)] }
  i <- mr[runif(length(mr)) < r("M-MR-06") & x$site_code[mr] == "RZ902" & as.POSIXlt(x$scan_start_datetime[mr])$wday == 6L]
  if (length(i)) { d <- copy(x[i]); d[, `:=`(accession_number = paste0(accession_number, "R"), booked_datetime = booked_datetime + days(2), scan_start_datetime = scan_start_datetime + days(21), scan_end_datetime = scan_end_datetime + days(21), reported_datetime = reported_datetime + days(21), verified_datetime = verified_datetime + days(21))]
    log_mess(ml, "M-MR-06", "ris_imaging", x[[K]][i], "status", "verified", "Saturday extended-hours DNA; rebooked three weeks later")
    x[i, `:=`(status = "DNA", scan_end_datetime = as_dt(NA), reported_datetime = as_dt(NA), verified_datetime = as_dt(NA))]; x <- rbind(x, d) }
  i <- x[, which(modality == "MR" & nicip_code == "MSPNW")]; i <- i[runif(length(i)) < r("M-MR-07")]
  if (length(i)) { d1 <- copy(x[i]); d1[, `:=`(accession_number = paste0(accession_number, "A"), nicip_code = "MCSPI", exam_description = "MRI Cervical spine", snomed_code = NA_character_)]
    d2 <- copy(x[i]); d2[, `:=`(accession_number = paste0(accession_number, "B"), nicip_code = "MTSPI", exam_description = "MRI Thoracic spine", snomed_code = NA_character_)]
    log_mess(ml, "M-MR-07", "ris_imaging", x[[K]][i], NA, NA, "whole spine booked as three rows sharing one slot"); x <- rbind(x, d1, d2) }
  # US
  us <- x[, which(modality == "US")]
  i <- us[runif(length(us)) < r("M-US-01") & x$status[us] == "verified"]
  if (length(i)) { log_mess(ml, "M-US-01", "ris_imaging", x[[K]][i], "verified_datetime", chr(x$verified_datetime[i]), "verified in the room"); x[i, `:=`(reported_datetime = scan_end_datetime + mins(2))]; x[i, verified_datetime := reported_datetime] }
  i <- us[runif(length(us)) < r("M-US-02") & x$nicip_code[us] == "UABDO" & x$status[us] == "verified"]
  if (length(i)) { d <- copy(x[i]); d[, `:=`(accession_number = paste0(accession_number, "P"), nicip_code = "UPELV", exam_description = "US Pelvis", snomed_code = "24848001", body_area = "Pelvis")]
    log_mess(ml, "M-US-02", "ris_imaging", x[[K]][i], NA, NA, "abdomen and pelvis booked as two rows on one slot"); x <- rbind(x, d) }
  i <- x[, which(modality == "US" & status == "DNA" & site_code == "RZ902" & patient_source_setting == "04")]; i <- i[runif(length(i)) < r("M-US-03")]
  if (length(i)) { log_mess(ml, "M-US-03", "ris_imaging", x[[K]][i], "status", "DNA", "DNA recorded as a patient cancellation"); x[i, `:=`(status = "cancelled", cancel_reason = NA_character_)] }
  i <- us[runif(length(us)) < r("M-US-04") & x$site_code[us] == "RZ902" & x$mi[us] %in% 13:19]
  if (length(i)) { log_mess(ml, "M-US-04", "ris_imaging", x[[K]][i], "patient_source_setting", x$patient_source_setting[i], "defaulted to Other by the community booking hub"); x[i, patient_source_setting := "07"] }
  i <- x[, which(modality == "US" & nicip_code == "UPELV")]; i <- i[runif(length(i)) < r("M-US-05")]
  if (length(i)) { log_mess(ml, "M-US-05", "ris_imaging", x[[K]][i], "exam_description", x$exam_description[i], "obstetric scan in the non-obstetric stream"); x[i, `:=`(exam_description = "US pelvis obstetric dating", dm01_countable = 0L)] }
  # all modalities (DID-shaped)
  i <- pick(nrow(x), r("M-RIS-01"))
  if (length(i)) { log_mess(ml, "M-RIS-01", "ris_imaging", x[[K]][i], "request_datetime", chr(x$request_datetime[i]), "request date missing; received date present"); x[i, request_datetime := as_dt(NA)] }
  if (r("M-RIS-02") > 0) { yr <- (x$mi - 1L) %/% 12L + 1L; p <- c(0.45, 0.30, 0.05)[pmin(pmax(yr, 1L), 3L)]
    i <- x[, which(site_code == "RZ901" & modality %in% c("CT", "MR") & patient_source_setting %in% c("03", "04") & status == "verified")]; i <- i[runif(length(i)) < p[i]]
    log_mess(ml, "M-RIS-02", "ris_imaging", x[[K]][i], "verified_datetime", chr(x$verified_datetime[i]), "report filed outside the RIS; no issue date")
    x[i, `:=`(reported_datetime = as_dt(NA), verified_datetime = as_dt(NA))] }
  i <- x[, which(site_code == "RZ902" & modality %in% c("CT", "MR") & patient_source_setting == "03" & mi %in% 13:19)]; i <- i[runif(length(i)) < r("M-RIS-03")]
  if (length(i)) { log_mess(ml, "M-RIS-03", "ris_imaging", x[[K]][i], "patient_source_setting", "03", "defaulted to Other"); x[i, patient_source_setting := "07"] }
  i <- x[, which(mi == 25L & status == "verified")]; i <- i[runif(length(i)) < r("M-RIS-04")]
  if (length(i)) { d <- copy(x[i]); d[, accession_number := paste0(accession_number, "D")]; log_mess(ml, "M-RIS-04", "ris_imaging", d$accession_number, NA, NA, "duplicate record after the archive rebuild"); x <- rbind(x, d) }
  i <- x[, which(nicip_code == "CCHAPC" & status == "verified")]; i <- i[runif(length(i)) < r("M-RIS-05")]
  if (length(i)) { d1 <- copy(x[i]); d1[, `:=`(accession_number = paste0(accession_number, "/2"), nicip_code = "CABPEC", exam_description = "CT Abdomen and pelvis with contrast")]
    d2 <- copy(x[i]); d2[, `:=`(accession_number = paste0(accession_number, "/3"), nicip_code = "CCHEC", exam_description = "CT Chest with contrast")]
    x[i, accession_number := paste0(accession_number, "/1")]; log_mess(ml, "M-RIS-05", "ris_imaging", x[[K]][i], NA, NA, "staging CT submitted as three records"); x <- rbind(x, d1, d2) }
  i <- pick(nrow(x), r("M-RIS-06"))
  if (length(i)) { log_mess(ml, "M-RIS-06", "ris_imaging", x[[K]][i], "nhs_number", x$nhs_number[i], "untraced number differs from the PAS by one digit")
    d <- x$nhs_number[i]; pos <- sample(6:15, length(i), TRUE); substr(d, pos, pos) <- as.character((as.integer(substr(d, pos, pos)) + 1L) %% 10L)
    x[i, `:=`(nhs_number = d, nhs_number_status = "02")] }
  x[, mi := NULL]
  T$ris_imaging <- x
  list(T = T, tr = tr)
}

# ---- endoscopy -------------------------------------------------------------
mess_endo <- function(T, tr, r, ml, ctx) {
  e <- T$endo_procedures; K <- "ProcID"
  pd <- as.Date(e$ProcDate, "%d/%m/%Y"); mi <- month_index(pd, ctx$start) + 1L
  i <- which(mi == 9L); i <- i[runif(length(i)) < r("M-EN-01") * 12]
  if (length(i)) { log_mess(ml, "M-EN-01", "endo_procedures", e[[K]][i], "ProcDate", e$ProcDate[i], "US locale on one workstation: MM/DD/YYYY"); e[i, ProcDate := format(pd[i], "%m/%d/%Y")] }
  i <- which(e$Category == "BCSP"); i <- i[runif(length(i)) < r("M-EN-02")]
  if (length(i)) { log_mess(ml, "M-EN-02", "endo_procedures", e[[K]][i], "HospNo", e$HospNo[i], "registered by the screening hub; no hospital number"); e[i, HospNo := NA_character_] }
  if (r("M-EN-03") > 0) { log_mess(ml, "M-EN-03", "endo_procedures", e[[K]], "Site", e$Site, "site as free text")
    e[Site == "Hospital A", Site := rcat(.N, c("HA", "Hosp A", "Hospital A", "HOSPITAL A"), c(3, 2, 4, 1))]
    e[Site == "Hospital B", Site := rcat(.N, c("HB", "Hosp B", "Hospital B", "HOSPITAL B"), c(3, 2, 4, 1))] }
  i <- which(e$Category == "IP-NEL" & !is.na(e$StartTime)); i <- i[runif(length(i)) < r("M-EN-04")]
  if (length(i)) { log_mess(ml, "M-EN-04", "endo_procedures", e[[K]][i], "StartTime", e$StartTime[i], "done on the ward; times not recorded"); e[i, `:=`(StartTime = NA_character_, EndTime = NA_character_)] }
  i <- which(e$Category == "SURV"); i <- i[runif(length(i)) < r("M-EN-06")]
  if (length(i)) { log_mess(ml, "M-EN-06", "endo_procedures", e[[K]][i], "ReferralDate", e$ReferralDate[i], "recall booked months late; ReferralDate is the original recall date")
    e[i, ReferralDate := format(as.Date(ReferralDate, "%d/%m/%Y") - round(runif(.N, 90, 270)), "%d/%m/%Y")] }
  i <- which(!(e$Outcome %in% c("DNA", "cancelled on the day", "abandoned")) & !is.na(e$Comfort)); i <- i[runif(length(i)) < r("M-EN-07")]
  if (length(i)) { log_mess(ml, "M-EN-07", "endo_procedures", e[[K]][i], "Comfort", e$Comfort[i], "comfort and extent not filled in"); e[i, `:=`(Comfort = NA_integer_, Extent = NA_character_)] }
  i <- pick(nrow(e), r("M-EN-08"))
  if (length(i)) { d <- copy(e[i]); d[, ProcID := sprintf("%07d", nrow(e) + seq_len(.N))]; log_mess(ml, "M-EN-08", "endo_procedures", d$ProcID, NA, NA, "re-exported after a report amendment"); e <- rbind(e, d) }
  T$endo_procedures <- e
  list(T = T, tr = tr)
}

# ---- identity: duplicate MRNs, merged (M-PAS-07) and unmerged (M-PAS-08) ---
mess_identity <- function(T, tr, r, ml, ctx) {
  pts <- T$pas_patients; ev <- T$pas_adt_events
  active <- unique(ev$mrn)
  T$endo_procedures[, ProcDate_d := as.Date(ProcDate, "%d/%m/%Y")]
  for (code in c("M-PAS-07", "M-PAS-08")) {
    p <- r(code); if (p <= 0) next
    sel <- active[runif(length(active)) < p]
    if (!length(sel)) next
    # the duplicate registration's MRN must not collide with any MRN already in use
    taken <- c(pts$mrn, ev$mrn)
    old <- setdiff(sprintf("T%07d", sample.int(9000000L, length(sel) * 2L + 100L) + 999999L), taken)[seq_along(sel)]
    m <- data.table(mrn = sel, old_mrn = old)
    # split time: the earliest ADT event plus a random share of the patient's span
    span <- ev[mrn %in% sel, .(t0 = min(event_datetime), t1 = max(event_datetime)), by = mrn]
    m <- merge(m, span, by = "mrn")
    m[, split := t0 + (t1 - t0) * runif(.N, 0.2, 0.8)]
    # duplicate demographics row
    dup <- pts[m, on = "mrn", nomatch = 0L]
    dup <- dup[, .(mrn = old_mrn, nhs_number = ifelse(runif(.N) < 0.5, NA_character_, nhs_number), nhs_number_status = ifelse(is.na(nhs_number) | runif(.N) < 0.5, "02", "01"), sex, dob, ethnicity, gp_practice,
                   postcode = ifelse(runif(.N) < 0.5, postcode, paste0(substr(postcode, 1, 4), sample(LETTERS, .N, TRUE), sample(LETTERS, .N, TRUE))), registered_datetime = t0 - days(runif(.N, 0, 30)), date_of_death = as.Date(NA))]
    log_mess(ml, code, "pas_patients", dup$mrn, "mrn", m$mrn, if (code == "M-PAS-07") "duplicate registration, later merged by A40" else "duplicate registration never merged")
    pts <- rbind(pts, dup)
    # events before the split go to the old MRN (for M-PAS-08, a random 40% of all events)
    swap <- function(dt, tname, datecol, keycol, mrncol = "mrn") {
      mm <- m[match(dt[[mrncol]], m$mrn)]
      hit <- !is.na(mm$mrn) & if (code == "M-PAS-07") as_dt(dt[[datecol]]) < mm$split else runif(nrow(dt)) < 0.4
      hit[is.na(hit)] <- FALSE  # a row whose date is unparseable stays with its MRN
      if (any(hit)) { log_mess(ml, code, tname, dt[[keycol]][hit], mrncol, dt[[mrncol]][hit], "recorded under the duplicate MRN"); set(dt, which(hit), mrncol, mm$old_mrn[hit]) }
      dt
    }
    ev <- swap(ev, "pas_adt_events", "event_datetime", "message_id")
    T$ed_attendances <- swap(T$ed_attendances, "ed_attendances", "activity_start_datetime", "uec_activity_identifier")
    T$pas_outpatient_appointments <- swap(T$pas_outpatient_appointments, "pas_outpatient_appointments", "appointment_datetime", "appointment_id")
    T$pas_referrals <- swap(T$pas_referrals, "pas_referrals", "referral_received_date", "referral_id")
    T$ris_imaging <- swap(T$ris_imaging, "ris_imaging", "request_received_datetime", "accession_number")
    T$endo_procedures <- swap(T$endo_procedures, "endo_procedures", "ProcDate_d", "ProcID", "HospNo")
    if (code == "M-PAS-07") {
      a40 <- ev[mrn %in% m$mrn | mrn %in% m$old_mrn][, .SD[1], by = visit_number][, .(message_id = NA_integer_, event_type = "A40", event_datetime = m$split[match(ifelse(mrn %in% m$mrn, mrn, m$mrn[match(mrn, m$old_mrn)]), m$mrn)] + days(runif(.N, 1, 30)),
                                                                                       mrn = ifelse(mrn %in% m$mrn, mrn, m$mrn[match(mrn, m$old_mrn)]), visit_number = NA_character_, site_code = "RZ901", ward = NA_character_, bed = NA_character_, consultant_code = NA_character_,
                                                                                       specialty_code = NA_character_, admission_method = NA_character_, admission_source = NA_character_, intended_management = NA_character_, patient_class = NA_character_,
                                                                                       decision_to_admit_date = as.Date(NA), discharge_method = NA_character_, discharge_destination = NA_character_, discharge_ready_date = as.Date(NA))]
      a40 <- a40[!duplicated(mrn)]
      a40[, prior_mrn := m$old_mrn[match(mrn, m$mrn)]]
      a40[, recorded_datetime := event_datetime + mins(1)]
      ev <- reseq(rbind(ev, a40[, names(ev), with = FALSE]))
    }
    tr$mrn_aliases <- rbind(tr$mrn_aliases, m[, .(mrn, alias_mrn = old_mrn, merged = code == "M-PAS-07")])
  }
  T$endo_procedures[, ProcDate_d := NULL]
  T$pas_patients <- pts; T$pas_adt_events <- ev
  list(T = T, tr = tr)
}

# ---- clocks (M-X-02): ED two minutes fast; RIS writes UTC during BST --------
mess_clocks <- function(T, tr, r, ml, ctx) {
  if (r("M-X-02") <= 0) return(list(T = T, tr = tr))
  ed <- T$ed_attendances
  for (col in c("activity_start_datetime", "initial_assessment_timestamp", "seen_for_treatment_timestamp", "decided_to_admit_datetime", "clinically_ready_to_proceed_timestamp", "activity_end_timestamp"))
    set(ed, j = col, value = ed[[col]] + mins(2))
  T$ed_status_log[, recorded_datetime := recorded_datetime + mins(2)]
  log_mess(ml, "M-X-02", "ed_attendances", NA_character_, NA, NA, "every ED timestamp is two minutes ahead of the PAS clock")
  x <- T$ris_imaging
  bst <- function(t) { lt <- as.POSIXlt(t, tz = "Europe/London"); !is.na(t) & lt$isdst == 1L }
  for (col in c("request_datetime", "request_received_datetime", "vetted_datetime", "booked_datetime", "scan_start_datetime", "scan_end_datetime", "reported_datetime", "verified_datetime")) {
    h <- bst(x[[col]]); set(x, which(h), col, x[[col]][h] - hours(1))
  }
  log_mess(ml, "M-X-02", "ris_imaging", NA_character_, NA, NA, "RIS timestamps are UTC: one hour behind local time during British Summer Time")
  T$ed_attendances <- ed; T$ris_imaging <- x
  list(T = T, tr = tr)
}
