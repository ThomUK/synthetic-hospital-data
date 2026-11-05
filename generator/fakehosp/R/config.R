#' Default annual volumes at full scale (800,000 patients)
#'
#' Every figure is sourced in docs/CALIBRATION.md. The generator scales them
#' by n_patients / 800000.
#' @export
default_volumes <- function() {
  list(
    patients_full_scale   = 800000,
    ed_type1              = 165000,
    ed_utc                = 100000,
    ed_type1_admit_rate   = 0.28,
    emergency_other       = 49000,     # not via ED: GP, bed bureau, clinic, transfers
    elective_wl           = 140000,    # waiting list + booked (ADMIMETH 11/12)
    elective_planned      = 15000,     # ADMIMETH 13
    day_case_share_elective = 0.55,    # of elective_wl; with planned gives ~90k day cases
    day_case_share_planned  = 0.80,
    endoscopy_daycase     = 7200,      # of the day cases, endoscopy lists (301/104/101)
    referrals             = 560000,
    rtt_share_referrals   = 0.36,
    ct                    = 125000,
    mr                    = 68000,
    us                    = 115000,
    endoscopy             = 24000,
    bcsp_age              = c(50, 74)
  )
}

# Monthly index for ED Type 1 arrivals, Apr 2023 - Mar 2026, from the national
# series (attendances per day relative to the mean). Source: CALIBRATION.md s2.
ed_month_index <- function() {
  att <- c(1271145,1400815,1389009,1379854,1323647,1369045,1413597,1386008,1384220,1397975,1347642,1462878,
           1372028,1472721,1405658,1425569,1320157,1364482,1453242,1428050,1440311,1359026,1271336,1450686,
           1388613,1453480,1428563,1469050,1383870,1417440,1481222,1450144,1438207,1434757,1298005,1478144)
  dim <- c(30,31,30,31,31,30,31,30,31,31,29,31, 30,31,30,31,31,30,31,30,31,31,28,31, 30,31,30,31,31,30,31,30,31,31,28,31)
  r <- att / dim
  r / mean(r)
}

# Monthly index for winter pressure (bed waits, LOS): 1 in summer, peaks in Dec/Jan.
winter_index <- function() {
  base <- c(0.95,0.95,0.95,0.95,0.95,1.00,1.10,1.15,1.25,1.30,1.15,1.05)   # Apr..Mar
  rep(base, 3)
}

# Monthly index for elective activity (assumption): dips in Aug and Dec.
elective_month_index <- function() {
  base <- c(1.00,1.03,1.03,1.00,0.90,1.03,1.05,1.05,0.78,1.00,1.02,1.08)
  rep(base, 3)
}

# Monthly index for imaging, DID 2023/24 per-day rates per modality (CALIBRATION s5.4).
imaging_month_index <- function(modality) {
  dim <- c(30,31,30,31,31,30,31,30,31,31,29,31)
  m <- switch(modality,
    CT = c(588425,626980,633580,637505,631790,634960,660335,658190,620700,684235,647685,656745),
    MR = c(351750,362600,365395,373630,361705,362105,375920,376780,348095,383985,371150,382365),
    US = c(814160,904670,934310,899195,896255,910300,940445,966120,825135,980910,917285,872240))
  r <- m / dim
  rep(r / mean(r), 3)
}

dow_index_ed  <- function() c(1.00, 1.09, 1.03, 1.00, 0.98, 0.98, 0.96, 0.96)[c(1,2,3,4,5,6,7)] # Sun..Sat (index 1 = Sunday)
# Sunday first to match POSIXlt$wday + 1
dow_ed  <- c(Sun=0.96, Mon=1.09, Tue=1.03, Wed=1.00, Thu=0.98, Fri=0.98, Sat=0.96)
dow_elective <- c(Sun=0.02, Mon=1.15, Tue=1.20, Wed=1.15, Thu=1.15, Fri=1.05, Sat=0.18)
dow_op <- c(Sun=0.00, Mon=1.10, Tue=1.15, Wed=1.10, Thu=1.10, Fri=0.95, Sat=0.08)

# Hour-of-day weights (index 1 = 00:00).
tod_ed <- c(2.0,1.6,1.3,1.1,1.0,1.0,1.3,2.2,3.5,4.6,5.2,5.4,5.3,5.1,4.9,4.8,4.7,4.6,4.5,4.2,3.8,3.3,2.8,2.3)
tod_elective_admit <- c(0,0,0,0,0,0,1,8,6,2,1,1,1,1,1,0.5,0,0,0,0,0,0,0,0)
tod_discharge <- c(0,0,0,0,0,0,0,0.2,0.6,1.5,2.5,3.5,4.5,5,5.5,5.5,5,4.5,3.5,2.5,1.5,0.5,0.2,0.1)
tod_other_emergency <- c(0.2,0.1,0.1,0.1,0.1,0.2,0.5,1,2,3,3.5,3.5,3.5,3.5,3.5,3.5,3,2.5,2,1.5,1,0.8,0.5,0.3)

# Daily Poisson counts for an annual volume over a window with month/dow indices.
daily_counts <- function(annual, dates, start, month_idx, dow_w) {
  mi <- month_index(dates, start) + 1L
  wd <- as.POSIXlt(dates)$wday + 1L
  lam <- annual / 365.25 * month_idx[pmin(mi, length(month_idx))] * dow_w[wd] / mean(dow_w)
  rpois(length(dates), lam)
}

#' Default discharge pathway shape
#'
#' How inpatient discharges split across the discharge-to-assess pathways
#' (P0 home with no new support, P1 home with new or more support, P2 a
#' short-term bed, P3 long-term care) and how the planned pathway, the
#' discharge ready date and the destination follow from them. Deaths and
#' day cases have no pathway. Every figure is an assumption documented in
#' docs/CALIBRATION.md section 9; override any element to reshape a run.
#' @export
default_discharge_pathways <- function() {
  list(
    # share of live inpatient discharges planned for each pathway, by age band
    planned_by_age = list(
      `0-64`  = c(P0 = 0.94, P1 = 0.050, P2 = 0.008, P3 = 0.002),
      `65-74` = c(P0 = 0.82, P1 = 0.140, P2 = 0.030, P3 = 0.010),
      `75-84` = c(P0 = 0.64, P1 = 0.260, P2 = 0.070, P3 = 0.030),
      `85+`   = c(P0 = 0.45, P1 = 0.350, P2 = 0.120, P3 = 0.080)
    ),
    age_breaks = c(65, 75, 85),
    # elective spells need less support: the P1-P3 shares are scaled by this and P0 takes the rest
    elective_support_factor = 0.40,
    # the pathway the patient actually left on, given the one planned (rows planned, columns actual)
    actual_given_planned = matrix(c(
      0.97, 0.03, 0.00, 0.00,
      0.12, 0.80, 0.06, 0.02,
      0.00, 0.15, 0.75, 0.10,
      0.00, 0.02, 0.10, 0.88
    ), nrow = 4, byrow = TRUE, dimnames = list(c("P0", "P1", "P2", "P3"), c("P0", "P1", "P2", "P3"))),
    # share of each planned pathway that is written down before discharge; simple discharges mostly are not
    planned_recorded = c(P0 = 0.35, P1 = 0.97, P2 = 0.98, P3 = 0.99),
    # days from no longer meeting the criteria to reside to discharge, by actual pathway:
    # share with no delay, then the lognormal median and sigma of the delay when there is one
    delay = list(
      P0 = c(zero = 0.85, median = 1, sigma = 0.6),
      P1 = c(zero = 0.30, median = 2, sigma = 0.8),
      P2 = c(zero = 0.10, median = 5, sigma = 0.7),
      P3 = c(zero = 0.05, median = 9, sigma = 0.7)
    ),
    # share of discharges whose discharge ready date is recorded on the A03, by actual pathway
    ready_date_recorded = c(P0 = 0.25, P1 = 0.90, P2 = 0.95, P3 = 0.95),
    # HES discharge destination given the actual pathway (codes and weights)
    destination = list(
      P0 = list(codes = c("19", "29", "51"), weights = c(93, 3, 4)),
      P1 = list(codes = c("19", "29"), weights = c(96, 4)),
      P2 = list(codes = c("51", "87"), weights = c(70, 30)),
      P3 = list(codes = c("54", "85"), weights = c(60, 40))
    )
  )
}
