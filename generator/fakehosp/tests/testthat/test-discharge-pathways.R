codes <- c("P0", "P1", "P2", "P3")

test_that("pathways sit on the A03 only and follow the configured shape", {
  g <- gen_small(); ev <- g$tables$pas_adt_events; sp <- g$truth$spells
  a03 <- ev[event_type == "A03"]
  other <- ev[event_type != "A03"]
  expect_true(all(is.na(other$planned_discharge_pathway) & is.na(other$discharge_pathway) & is.na(other$discharge_ready_date)))
  expect_true(all(is.na(a03$discharge_pathway) | a03$discharge_pathway %in% codes))
  expect_true(all(is.na(a03$planned_discharge_pathway) | a03$planned_discharge_pathway %in% codes))
  # deaths and day cases have none; every other finished spell has an actual pathway
  live <- sp[!open_at_end & !died & !day_case]
  expect_true(all(live$discharge_pathway %in% codes))
  expect_true(all(is.na(sp[died == TRUE | day_case == TRUE, discharge_pathway])))
  expect_true(all(is.na(sp[died == TRUE | day_case == TRUE, planned_discharge_pathway])))
  # the pooled shape: mostly P0, a P1 minority, P2 and P3 small
  share <- prop.table(table(factor(live$discharge_pathway, codes)))
  expect_true(share[["P0"]] > 0.70 && share[["P0"]] < 0.90)
  expect_true(share[["P1"]] > 0.08 && share[["P1"]] < 0.22)
  expect_true(share[["P3"]] > 0.005 && share[["P3"]] < 0.05)
  # simple discharges are rarely planned; supported ones nearly always are
  expect_true(mean(!is.na(live[discharge_pathway == "P0", planned_discharge_pathway])) < 0.6)
  expect_true(mean(!is.na(live[discharge_pathway %in% c("P1", "P2", "P3"), planned_discharge_pathway])) > 0.8)  # some P1 arrive from unplanned P0
  # the plan usually holds
  both <- live[!is.na(planned_discharge_pathway)]
  expect_true(mean(both$planned_discharge_pathway == both$discharge_pathway) > 0.85)
  # the destination follows the pathway
  expect_true(all(a03[discharge_pathway == "P3", discharge_destination] %in% c("54", "85")))
  expect_true(all(a03[discharge_pathway == "P2", discharge_destination] %in% c("51", "87")))
  expect_true(all(a03[discharge_pathway %in% c("P0", "P1"), discharge_destination] %in% c("19", "29", "51")))
})

test_that("the discharge ready date sits inside the spell and the delay grows with the pathway", {
  g <- gen_small(); sp <- g$truth$spells[!open_at_end & !died & !day_case]
  r <- sp[!is.na(discharge_ready_date)]
  expect_true(all(r$discharge_ready_date <= as.Date(r$discharge)))
  expect_true(all(r$discharge_ready_date >= as.Date(r$admit)))
  expect_true(mean(!is.na(sp[discharge_pathway == "P0", discharge_ready_date])) < 0.4)
  expect_true(mean(!is.na(sp[discharge_pathway %in% c("P2", "P3"), discharge_ready_date])) > 0.85)
  delay <- r[, .(d = mean(as.numeric(as.Date(discharge) - discharge_ready_date))), by = discharge_pathway]
  expect_true(delay[discharge_pathway == "P0", d] < delay[discharge_pathway == "P1", d])
  expect_true(delay[discharge_pathway == "P1", d] < delay[discharge_pathway == "P3", d])
  expect_true(delay[discharge_pathway == "P3", d] > 5)
  # supported pathways mean longer stays
  los <- sp[, .(los = mean(los)), by = discharge_pathway]
  expect_true(los[discharge_pathway == "P3", los] > los[discharge_pathway == "P0", los])
})

test_that("the pathway shape is a configuration, not a constant", {
  pw <- default_discharge_pathways()
  expect_equal(rownames(pw$actual_given_planned), codes)
  expect_true(all(abs(rowSums(pw$actual_given_planned) - 1) < 1e-9))
  for (b in pw$planned_by_age) expect_true(abs(sum(b) - 1) < 1e-9)
  expect_equal(names(pw$delay), codes)
  pw$planned_by_age <- lapply(pw$planned_by_age, function(x) c(P0 = 0, P1 = 0, P2 = 0, P3 = 1))
  pw$actual_given_planned[] <- 0; diag(pw$actual_given_planned) <- 1
  pw$elective_support_factor <- 1
  g <- generate(seed = 3L, n_patients = 3000L, mess = NULL, pathways = pw, verbose = FALSE)
  live <- g$truth$spells[!open_at_end & !died & !day_case]
  expect_true(mean(live$discharge_pathway == "P3") > 0.99)   # the rest are deaths undone after the clock check, which default to P0
  expect_true(all(g$tables$pas_adt_events[event_type == "A03" & discharge_pathway == "P3", discharge_destination] %in% c("54", "85")))
})

test_that("the pathway mess entries are injected at their rates and logged", {
  g <- gen_messy(); ev <- g$tables$pas_adt_events; ml <- g$mess_log; sp <- g$truth$spells
  a03 <- ev[event_type == "A03"]
  # M-PAS-17: planned P1-P3, actual blank, discharge happened
  m17 <- a03[planned_discharge_pathway %in% c("P1", "P2", "P3") & is.na(discharge_pathway)]
  expect_true(nrow(m17) > 0)
  expect_true(all(ml[mess_id == "M-PAS-17", field] == "discharge_pathway"))
  expect_true(approx_rel(ml[mess_id == "M-PAS-17", .N] / sp[discharge_pathway %in% c("P1", "P2", "P3") & !open_at_end, .N], 0.06, 0.5))
  # M-PAS-18: actual P1-P3, no plan
  expect_true(ml[mess_id == "M-PAS-18", .N] > 0)
  expect_true(all(ml[mess_id == "M-PAS-18", original_value] %in% codes))
  expect_true(nrow(a03[discharge_pathway %in% c("P1", "P2", "P3") & is.na(planned_discharge_pathway)]) > 0)
  # M-PAS-19: other forms survive in the raw field, and the truth keeps the clean code
  raw <- a03[!is.na(discharge_pathway) & !discharge_pathway %in% codes, discharge_pathway]
  expect_true(length(raw) > 0)
  expect_true(all(grepl("^(p[0-3]|[0-3]|Pathway [0-3]|P [0-3])$", raw)))
  expect_true(all(sp$discharge_pathway %in% c(codes, NA)))
  # M-PAS-20: ready date pulled to the discharge date, never after it
  m20 <- ml[mess_id == "M-PAS-20"]
  expect_true(nrow(m20) > 0)
  expect_true(all(a03[!is.na(discharge_ready_date), discharge_ready_date <= as.Date(event_datetime)]))
})
