# Spells, ward stays, consultant episodes and the PAS ADT event log.

los_median_emergency <- c("300"=3,"430"=8,"320"=3,"340"=4,"301"=3,"361"=5,"400"=4,"100"=3,"104"=4,"107"=5,"110"=6,"101"=2,"120"=1,"130"=1,"502"=1,"420"=1,"410"=3,"330"=2,"180"=1,"192"=4)
los_median_elective  <- c("300"=2,"430"=4,"320"=2,"340"=2,"301"=2,"361"=3,"400"=3,"100"=3,"104"=5,"107"=4,"110"=3,"101"=2,"120"=1,"130"=1,"502"=1,"420"=1,"410"=2,"330"=1,"180"=1,"192"=3)
daycase_prob <- c("300"=0.55,"430"=0.3,"320"=0.7,"340"=0.5,"301"=0.95,"361"=0.8,"400"=0.5,"100"=0.65,"104"=0.6,"107"=0.3,"110"=0.45,"101"=0.7,"120"=0.75,"130"=0.98,"502"=0.75,"420"=0.6,"410"=0.9,"330"=0.9)
elective_mix <- c("110"=14,"100"=10,"104"=5,"101"=11,"130"=10,"120"=6,"502"=8,"301"=8,"320"=6,"420"=3,"107"=2,"361"=4,"410"=1,"400"=2,"300"=5,"340"=3,"430"=1)
planned_mix  <- c("301"=25,"320"=12,"361"=15,"100"=8,"101"=12,"420"=8,"400"=5,"110"=5,"104"=5,"340"=5)

generate_admissions <- function(pts, ref, vol, scale, seed, start, end, ed, op, verbose = FALSE, pathways = default_discharge_pathways()) {
  stage_seed(seed, 5L)
  start <- as.Date(start); end <- as.Date(end)
  sp <- ref$specialties
  cons <- ref$consultants
  wi <- winter_index()

  pick_spec_patient <- function(spec, n) {
    if (spec == "420") pick_patients(pts, n, pts$age_mid < 16)
    else if (spec == "430") pick_patients(pts, n, pts$age_mid >= 70)
    else if (spec == "502") pick_patients(pts, n, pts$sex == "2" & pts$age_mid >= 16)
    else if (spec == "101") pick_patients(pts, n, pts$age_mid >= 16 & (pts$sex == "1" | runif(nrow(pts)) < 0.35))
    else pick_patients(pts, n, pts$age_mid >= 16)
  }

  # ---- 1. emergency admissions via the ED ----
  eda <- ed$attendances[admitted == TRUE]
  s1 <- eda[, .(mrn, admit = activity_end_timestamp, admission_method = "21", specialty_code = tfc_decision_to_admit,
                site_code = "RZ901", origin = "ed", uec_activity_identifier)]
  # ---- 2. other emergency admissions ----
  dates <- seq(start - 60, end, by = "day")
  n2 <- daily_counts(vol$emergency_other * scale, dates, start - 60, c(rep(1, 2), wi), dow_ed)
  s2 <- data.table(date = rep(dates, n2))
  s2[, admit := dt_of(date, sample_tod(.N, tod_other_emergency))]
  s2[, admission_method := rcat(.N, c("22", "23", "24", "28", "2B", "2D"), c(40, 5, 20, 25, 5, 5))]
  em <- sp[emergency_share > 0]
  s2[, specialty_code := em$tfc[wsample(.N, em$emergency_share)]]
  s2[, mrn := NA_character_]
  for (s in unique(s2$specialty_code)) s2[specialty_code == s, mrn := pick_spec_patient(s, .N)]
  s2[, site_code := ifelse(specialty_code %in% sp[ip_b == 1, tfc] & runif(.N) < 0.06, "RZ902", "RZ901")]
  s2[, `:=`(origin = "other_em", uec_activity_identifier = NA_character_)]
  s2[, date := NULL]
  # ---- 3. elective waiting list / booked ----
  n3_total <- round(vol$elective_wl * scale * as.numeric(end - start + 61) / 365.25)
  dates3 <- seq(start - 60, end, by = "day")
  n3 <- daily_counts(vol$elective_wl * scale, dates3, start - 60, c(rep(1, 2), elective_month_index()), dow_elective)
  s3 <- data.table(date = rep(dates3, n3))
  s3[, admit := dt_of(date, sample_tod(.N, tod_elective_admit))]
  # link a share to outpatient waiting-list decisions
  wl <- op$referrals[!is.na(wl_decision_date), .(referral_id, mrn, specialty_code, decision = wl_decision_date, rtt_pathway_id)]
  wl[, admit_date := decision + round(rln(.N, 55, 0.8))]
  wl_pre <- wl[admit_date < start - 60]              # admitted before the window: clock stopped, no spell generated
  wl <- wl[admit_date <= end & admit_date >= start - 60]
  n_link <- min(nrow(wl), nrow(s3))
  s3[, `:=`(referral_id = NA_character_, rtt_pathway_id = NA_character_, specialty_code = NA_character_, mrn = NA_character_, decision_to_admit_date = as.Date(NA))]
  if (n_link > 0L) {
    wl <- wl[sample.int(nrow(wl), n_link)]
    setorder(s3, admit); idx <- sort(sample.int(nrow(s3), n_link))
    s3[idx, `:=`(referral_id = wl$referral_id, rtt_pathway_id = wl$rtt_pathway_id, specialty_code = wl$specialty_code, mrn = wl$mrn,
                 decision_to_admit_date = wl$decision, admit = dt_of(wl$admit_date, sample_tod(n_link, tod_elective_admit)))]
  }
  s3[is.na(specialty_code), specialty_code := names(elective_mix)[wsample(.N, elective_mix)]]
  for (s in unique(s3$specialty_code)) s3[specialty_code == s & is.na(mrn), mrn := pick_spec_patient(s, .N)]
  s3[is.na(decision_to_admit_date), decision_to_admit_date := as.Date(admit) - pmax(1, round(rln(.N, 28, 1.0)))]
  s3[, admission_method := rcat(.N, c("11", "12"), c(70, 30))]
  s3[, `:=`(origin = "elective", uec_activity_identifier = NA_character_)]
  s3[, date := NULL]
  # ---- 4. planned ----
  n4 <- daily_counts(vol$elective_planned * scale, dates3, start - 60, c(rep(1, 2), elective_month_index()), dow_elective)
  s4 <- data.table(date = rep(dates3, n4))
  s4[, admit := dt_of(date, sample_tod(.N, tod_elective_admit))]
  s4[, specialty_code := names(planned_mix)[wsample(.N, planned_mix)]]
  s4[, mrn := NA_character_]
  for (s in unique(s4$specialty_code)) s4[specialty_code == s, mrn := pick_spec_patient(s, .N)]
  s4[, decision_to_admit_date := as.Date(admit) - round(rln(.N, 90, 0.7))]
  s4[, `:=`(admission_method = "13", origin = "planned", uec_activity_identifier = NA_character_, referral_id = NA_character_, rtt_pathway_id = NA_character_)]
  s4[, date := NULL]

  spl <- rbindlist(list(s1, s2, s3, s4), fill = TRUE)
  spl <- merge(spl, pts[, .(mrn, dob, sex)], by = "mrn", sort = FALSE)
  spl[, age := age_at(dob, admit)]
  spl[, emergency := admission_method %in% c("21", "22", "23", "24", "28", "2B", "2D")]
  # site for elective/planned by specialty
  bsh <- setNames(sp$elective_b_share, sp$tfc)
  spl[emergency == FALSE, site_code := ifelse(runif(.N) < bsh[specialty_code], "RZ902", "RZ901")]
  # patient class
  spl[, day_case := FALSE]
  spl[origin == "elective", day_case := runif(.N) < daycase_prob[specialty_code] * vol$day_case_share_elective / 0.7]
  spl[origin == "planned",  day_case := runif(.N) < vol$day_case_share_planned]
  spl[, endoscopy := FALSE]
  endo_pool <- which(spl$day_case & spl$specialty_code %in% c("301", "104", "101") & spl$origin %in% c("elective", "planned"))
  endo_w <- ifelse(spl$specialty_code[endo_pool] == "101", 0.25, 1)
  n_endo <- min(length(endo_pool), round(vol$endoscopy_daycase * scale * as.numeric(end - start + 61) / 365.25))
  if (n_endo > 0L) spl[endo_pool[wsample(n_endo, endo_w, replace = FALSE)], endoscopy := TRUE]
  # length of stay
  spl[, mi := pmin(pmax(month_index(as.Date(admit), start), 0L) + 1L, 36L)]
  spl[, los := 0]
  spl[emergency == TRUE, same_day := runif(.N) < 0.30]
  spl[emergency == TRUE & same_day == FALSE, los := pmin(round(rln(.N, 0.75 * los_median_emergency[specialty_code] * wi[mi]^0.5, 1.0)), 120)]
  spl[emergency == TRUE & same_day == FALSE & los < 1, los := 1]
  spl[emergency == FALSE & day_case == FALSE, los := pmax(1, pmin(round(rln(.N, 0.8 * los_median_elective[specialty_code], 0.8)), 60))]
  spl[, patient_class := ifelse(day_case, "2", "1")]
  spl[, intended_management := ifelse(day_case, "2", "1")]
  # discharge
  spl[, discharge := as_dt(as.Date(admit)) + days(los) + sample_tod(.N, tod_discharge)]
  spl[los == 0 & emergency == TRUE, discharge := admit + hours(runif(.N, 4, 14))]
  spl[day_case == TRUE, discharge := admit + hours(runif(.N, 3, 9))]
  spl[discharge <= admit + hours(1), discharge := admit + hours(runif(.N, 2, 8))]
  # deaths (emergency inpatients)
  agef <- function(a) ifelse(a < 65, 0.3, ifelse(a < 75, 0.8, ifelse(a < 85, 1.4, 2.2)))
  spl[, died := FALSE]
  spl[emergency == TRUE & los >= 1, died := runif(.N) < 0.045 * agef(age)]
  # weekend discharges pushed to Monday (not deaths, not day cases)
  spl[died == FALSE & day_case == FALSE & los >= 1, discharge := weekday_shift(discharge, 0.35)]
  spl[, los := as.numeric(as.Date(discharge) - as.Date(admit))]
  spl[, discharge_method := ifelse(died, "4", rcat(.N, c("1", "6", "7"), c(97.5, 2, 0.5)))]
  # discharge pathway (planned, then actual), the discharge ready date and the destination that follows
  spl <- assign_discharge_pathways(spl, pathways)
  spl[died == TRUE, discharge_destination := "79"]
  spl[, admission_source := ifelse(admission_method == "2B", "51", ifelse(age >= 75 & runif(.N) < 0.08, "54", rcat(.N, c("19", "29"), c(97, 3))))]
  # keep spells that touch the window
  spl <- spl[as.Date(admit) <= end & as.Date(discharge) >= start]
  spl[, open_at_end := as.Date(discharge) > end]
  setorder(spl, admit)
  spl[, visit_number := sprintf("V%010d", .I)]
  # consultant
  spl[, consultant_code := {
    cc <- cons[tfc == .BY$specialty_code & main_site == .BY$site_code, consultant_code]
    if (length(cc) == 0L) cc <- cons[tfc == .BY$specialty_code, consultant_code]
    if (length(cc) == 0L) cc <- cons$consultant_code
    sample(cc, .N, TRUE)
  }, by = .(specialty_code, site_code)]
  vmsg(verbose, "Spells: ", nrow(spl), " (day cases ", sum(spl$day_case), ")")

  # ---- ward stays ----
  wards <- ref$wards
  ward_for <- function(tfc, site, kind = "bed") {
    w <- wards[kind == kind & site_code == site & tfc == tfc, ward_name]
    if (length(w) == 0L) w <- wards[kind == "bed" & site_code == site & tfc == "300", ward_name]
    if (length(w) == 0L) w <- wards[kind == "bed" & site_code == site, ward_name]
    w
  }
  pick_ward <- function(tfc, site, kind = "bed") {
    w <- wards[wards$kind == kind & wards$site_code == site & wards$tfc == tfc, ward_name]
    if (length(w) == 0L && kind == "bed") w <- wards[wards$kind == "bed" & wards$site_code == site & wards$tfc == "300", ward_name]
    if (length(w) == 0L) w <- wards[wards$kind %in% c("bed", "daycase") & wards$site_code == site, ward_name]
    w
  }
  medical <- c("300", "430", "320", "340", "301", "361", "400", "410")
  spl[, first_ward := NA_character_]
  # day cases
  spl[day_case == TRUE & endoscopy == TRUE, first_ward := ifelse(site_code == "RZ901", "Endoscopy Unit A", "Endoscopy Unit B")]
  spl[day_case == TRUE & endoscopy == FALSE & specialty_code == "130", first_ward := "Eye Unit"]
  spl[day_case == TRUE & is.na(first_ward), first_ward := ifelse(site_code == "RZ901", "Day Case Unit A", rcat(.N, c("Day Surgery Unit 1", "Day Surgery Unit 2", "Treatment Unit"), c(4, 4, 2)))]
  # emergency admissions
  spl[emergency == TRUE & age < 16, first_ward := rcat(.N, c("Childrens Ward 1", "Childrens Ward 2"), c(6, 4))]
  spl[emergency == TRUE & is.na(first_ward) & specialty_code %in% medical, first_ward := rcat(.N, c("AMU 1", "AMU 2"), c(1, 1))]
  spl[emergency == TRUE & is.na(first_ward) & specialty_code == "320" & runif(.N) < 0.3, first_ward := "CCU"]
  spl[emergency == TRUE & is.na(first_ward) & specialty_code == "110" & runif(.N) < 0.5, first_ward := rcat(.N, c("Ward 18 Trauma", "Ward 19 Trauma"), c(1, 1))]
  spl[emergency == TRUE & is.na(first_ward) & site_code == "RZ901", first_ward := "SAU"]
  spl[emergency == TRUE & is.na(first_ward), first_ward := "Ward W1 Surgery"]
  # elective inpatients straight to a specialty ward
  for (s in unique(spl[is.na(first_ward), specialty_code])) for (st in c("RZ901", "RZ902")) {
    w <- pick_ward(s, st); spl[is.na(first_ward) & specialty_code == s & site_code == st, first_ward := sample(w, .N, TRUE)]
  }
  # stays table: first stay, optional critical care, specialty ward transfer, discharge lounge
  st1 <- spl[, .(visit_number, ward = first_ward, from = admit, to = discharge, seq = 1L)]
  stays <- list(st1)
  mv <- spl[emergency == TRUE & los >= 1 & first_ward %in% c("AMU 1", "AMU 2", "SAU", "CCU") & runif(.N) < 0.78]
  if (nrow(mv) > 0L) {
    mv[, t_move := admit + hours(rln(.N, 20, 0.5))]
    mv <- mv[t_move < discharge - hours(2)]
    mv[, ward2 := NA_character_]
    for (s in unique(mv$specialty_code)) { w <- pick_ward(s, "RZ901"); mv[specialty_code == s, ward2 := sample(w, .N, TRUE)] }
    mv[wi[mi] >= 1.15 & runif(.N) < 0.08, ward2 := rcat(.N, c("Escalation Ward 1", "Escalation Ward 2", "Escalation Ward 3"), c(1, 1, 1))]
    # critical care insert
    mv[, cc := los >= 2 & runif(.N) < 0.035]
    mv[cc == TRUE, `:=`(cc_ward = rcat(.N, c("ICU", "HDU"), c(6, 4)), cc_end = pmin(t_move + days(rln(.N, 2.5, 0.6)), discharge - hours(6)))]
    st1[visit_number %in% mv$visit_number, to := mv$t_move[match(visit_number, mv$visit_number)]]
    stays[[2]] <- mv[cc == TRUE, .(visit_number, ward = cc_ward, from = t_move, to = cc_end, seq = 2L)]
    stays[[3]] <- mv[, .(visit_number, ward = ward2, from = ifelse(cc, cc_end, t_move), to = discharge, seq = ifelse(cc, 3L, 2L))]
    stays[[3]][, from := as_dt(from)]
    spl[visit_number %in% mv$visit_number, specialty_ward := mv$ward2[match(visit_number, mv$visit_number)]]
  }
  stays[[1]] <- st1
  stays <- rbindlist(stays)
  # discharge lounge
  dl <- spl[site_code == "RZ901" & day_case == FALSE & died == FALSE & los >= 1 & open_at_end == FALSE & runif(.N) < 0.15, .(visit_number, discharge)]
  if (nrow(dl) > 0L) {
    dl[, t_dl := discharge - hours(runif(.N, 2, 5))]
    last <- stays[visit_number %in% dl$visit_number][, .SD[which.max(seq)], by = visit_number]
    last[, t_dl := dl$t_dl[match(visit_number, dl$visit_number)]]
    last <- last[t_dl > from + hours(1)]
    stays[last, on = .(visit_number, seq), to := i.t_dl]
    stays <- rbind(stays, last[, .(visit_number, ward = "Discharge Lounge", from = t_dl, to = to, seq = seq + 1L)])
  }
  setorder(stays, visit_number, seq)
  stays <- merge(stays, spl[, .(visit_number, site_code)], by = "visit_number")
  # ---- episodes: specialty/consultant change at the transfer for a share of emergency medical spells ----
  spl[, n_episodes := 1L]
  ep <- spl[emergency == TRUE & day_case == FALSE & los >= 1 & runif(.N) < 0.62]
  ep <- rbind(ep, spl[emergency == FALSE & day_case == FALSE & runif(.N) < 0.08])
  ep <- ep[!duplicated(visit_number)]
  ep[, new_spec := specialty_code]
  ep[specialty_code == "300" & age >= 75 & runif(.N) < 0.6, new_spec := "430"]
  ep[, new_consultant := {
    cc <- cons[tfc == .BY$new_spec, consultant_code]; if (length(cc) == 0L) cc <- cons$consultant_code; sample(cc, .N, TRUE)
  }, by = new_spec]
  ep[, t_change := admit + hours(rln(.N, 22, 0.4))]
  ep <- ep[t_change < discharge - hours(1)]
  spl[visit_number %in% ep$visit_number, n_episodes := 2L]
  spl[, first_specialty := specialty_code]
  spl[, first_consultant := consultant_code]
  spl[visit_number %in% ep$visit_number, `:=`(specialty_code = ep$new_spec[match(visit_number, ep$visit_number)], consultant_code = ep$new_consultant[match(visit_number, ep$visit_number)])]

  # ---- ADT events ----
  bed <- function(n) paste0("Bay", sample.int(6L, n, TRUE), "-", formatC(sample.int(7L, n, TRUE), width = 2, flag = "0"))
  ev <- list()
  # A04 registration
  ev$a04 <- spl[, .(visit_number, event_type = "A04",
                    event_datetime = fifelse(origin == "ed", admit - hours(rln(.N, 5, 0.6)),
                                     fifelse(origin %in% c("elective", "planned"), as_dt(decision_to_admit_date) + hours(10) + mins(runif(.N, 0, 300)), admit - hours(runif(.N, 1, 6)))),
                    ward = NA_character_, specialty_code = first_specialty, consultant_code = first_consultant)]
  ev$a01 <- merge(spl[, .(visit_number, event_type = "A01", event_datetime = admit, specialty_code = first_specialty, consultant_code = first_consultant)],
                  stays[seq == 1L, .(visit_number, ward)], by = "visit_number")
  ev$a02 <- merge(stays[seq > 1L, .(visit_number, event_type = "A02", event_datetime = from, ward)],
                  spl[, .(visit_number, specialty_code, consultant_code)], by = "visit_number")
  ev$a08 <- ep[, .(visit_number, event_type = "A08", event_datetime = t_change, ward = NA_character_, specialty_code = new_spec, consultant_code = new_consultant)]
  ev$a03 <- merge(spl[open_at_end == FALSE, .(visit_number, event_type = "A03", event_datetime = discharge, specialty_code, consultant_code)],
                  stays[, .SD[which.max(seq)], by = visit_number][, .(visit_number, ward)], by = "visit_number")
  events <- rbindlist(ev, use.names = TRUE, fill = TRUE)
  events <- merge(events, spl[, .(visit_number, mrn, site_code, admission_method, admission_source, intended_management, patient_class,
                                  decision_to_admit_date, discharge_method, discharge_destination, planned_discharge_pathway, discharge_pathway,
                                  discharge_ready_date, los, died)], by = "visit_number")
  # a specialty/consultant change in A08 means the earlier events carry the first episode's values (already so)
  events[event_type != "A01", `:=`(admission_method = NA_character_, admission_source = NA_character_, decision_to_admit_date = as.Date(NA))]
  events[event_type != "A03", `:=`(discharge_method = NA_character_, discharge_destination = NA_character_,
                                   planned_discharge_pathway = NA_character_, discharge_pathway = NA_character_, discharge_ready_date = as.Date(NA))]
  events[event_type %in% c("A01", "A02"), bed := bed(.N)]
  events[event_type %in% c("A01", "A02") & ward %in% c("Discharge Lounge", "ED"), bed := NA_character_]
  events[, recorded_datetime := event_datetime + mins(runif(.N, 0, 10))]
  events[, prior_mrn := NA_character_]
  setorder(events, recorded_datetime)
  events[, message_id := .I]
  events <- events[, .(message_id, event_type, event_datetime, recorded_datetime, mrn, visit_number, site_code, ward, bed,
                       consultant_code, specialty_code, admission_method, admission_source, intended_management, patient_class,
                       decision_to_admit_date, discharge_method, discharge_destination, planned_discharge_pathway, discharge_pathway,
                       discharge_ready_date, prior_mrn)]
  vmsg(verbose, "ADT events: ", nrow(events))
  # linked RTT clock stops
  rtt_stops <- rbind(spl[!is.na(rtt_pathway_id), .(referral_id, admit_date = as.Date(admit))],
                     wl_pre[!is.na(rtt_pathway_id), .(referral_id, admit_date)])
  list(spells = spl, stays = stays, events = events, rtt_stops = rtt_stops)
}


# Planned and actual discharge pathway, discharge ready date and destination
# for every spell, from the shape in default_discharge_pathways(). Deaths and
# day cases have no pathway; the ready date is never before the admission
# date nor after the discharge date, and a delay longer than the planned stay
# lengthens the stay.
assign_discharge_pathways <- function(spl, pw) {
  codes <- c("P0", "P1", "P2", "P3")
  spl[, `:=`(planned_discharge_pathway = NA_character_, discharge_pathway = NA_character_,
             discharge_ready_date = as.Date(NA), discharge_destination = NA_character_)]
  live <- spl[, which(died == FALSE & day_case == FALSE)]
  n <- length(live)
  if (n == 0L) {
    spl[died == TRUE, discharge_destination := "79"]
    spl[died == FALSE & day_case == TRUE, discharge_destination := rcat(.N, c("19", "29"), c(97, 3))]
    return(spl)
  }
  # planned pathway: shares by age band, with less support after elective admissions
  band <- as.integer(cut(spl$age[live], breaks = c(-Inf, pw$age_breaks, Inf), right = FALSE))
  shares <- do.call(rbind, pw$planned_by_age)[band, , drop = FALSE]
  elective <- spl$emergency[live] == FALSE
  shares[elective, -1] <- shares[elective, -1, drop = FALSE] * pw$elective_support_factor
  shares[, 1] <- 1 - rowSums(shares[, -1, drop = FALSE])
  cum <- t(apply(shares, 1, cumsum))
  planned <- codes[pmin(rowSums(cum < runif(n)) + 1L, 4L)]
  # actual pathway given the planned one, then what follows from the actual one
  actual <- planned
  delay <- numeric(n)
  dest <- character(n)
  for (p in codes) {
    k <- which(planned == p)
    if (length(k)) actual[k] <- rcat(length(k), codes, pw$actual_given_planned[p, ])
  }
  for (a in codes) {
    k <- which(actual == a)
    if (!length(k)) next
    z <- pw$delay[[a]]
    delay[k] <- ifelse(runif(length(k)) < z[["zero"]], 0, round(rln(length(k), z[["median"]], z[["sigma"]])))
    dest[k] <- rcat(length(k), pw$destination[[a]]$codes, pw$destination[[a]]$weights)
  }
  # a delay longer than the stay so far extends the stay: the patient was ready
  # on the day of admission at the earliest and the bed is held until the
  # pathway is in place
  los_days <- as.numeric(as.Date(spl$discharge[live]) - as.Date(spl$admit[live]))
  extend <- pmax(delay - los_days, 0)
  new_discharge <- spl$discharge[live] + days(extend)
  ready <- as.Date(new_discharge) - delay
  recorded <- runif(n) < pw$planned_recorded[planned]
  has_ready <- runif(n) < pw$ready_date_recorded[actual]
  ready[!has_ready] <- NA
  planned_recorded <- ifelse(recorded, planned, NA_character_)
  spl[live, `:=`(discharge = new_discharge, planned_discharge_pathway = planned_recorded, discharge_pathway = actual,
                 discharge_ready_date = ready, discharge_destination = dest)]
  spl[, los := as.numeric(as.Date(discharge) - as.Date(admit))]
  spl[died == TRUE, discharge_destination := "79"]
  spl[died == FALSE & day_case == TRUE, discharge_destination := rcat(.N, c("19", "29"), c(97, 3))]
  spl
}
