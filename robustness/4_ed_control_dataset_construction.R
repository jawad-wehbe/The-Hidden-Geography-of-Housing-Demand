library(arrow)
library(dplyr)
library(haven)

rm(list =ls())

# ────────────────────────────────────────────────────────────────────────────
# VIP: USES SHOCK AS PLOT COMPLETION DATE
# ────────────────────────────────────────────────────────────────────────────


# Paths
weekly_path      <- "~/Desktop/Projects/housing_targets/produced/nature/nonbots/saved_or_contacted/oa_weekly_search_with_geos.parquet"
shock_path       <- "~/Desktop/Projects/housing_targets/produced/search_on_build_shock/setup/ed_shock_oa.parquet"
cw_msoa_path     <- "~/Desktop/Raw_Data/Shapefiles etc/Crosswalks/oa_msoa.parquet"
control_out_path <- "~/Desktop/Projects/housing_targets/produced/nature/nonbots/saved_or_contacted/ed_control_oa_weekly.parquet"


#  Read in the data
weekly      <- read_parquet(weekly_path)
shock       <- read_parquet(shock_path)
cw_oa_msoa  <- read_parquet(cw_msoa_path)


#recast 53 weeks to 52
weekly <- weekly %>%
  mutate(
    week = if_else(week == 53, 52L, week)
  )

#  Find every MSOA touched by any shock-OA
shock_msos_all <- cw_oa_msoa %>%
  filter(oa_code %in% shock$intersecting_oa) %>%  # all crosswalk rows for shock OAs
  pull(msoa_code) %>%
  unique()

# Find all OAs that intersect those MSOAs
oas_to_exclude <- cw_oa_msoa %>%
  filter(msoa_code %in% shock_msos_all) %>%
  pull(oa_code) %>%
  unique()

# Build the control group table, excluding by OA not just assigned msoa
control <- weekly %>%
  filter(
    !oa_code %in% oas_to_exclude  # kick out any OA that physically intersects a shocked MSOA
  ) %>%
  mutate(
    Group         = "Control",
    site_size     = 0,
    treated_today = 0
  ) %>%
  select(
    oa_code, year, week,
    buying_searches, letting_searches,
    assigned_lsoa, assigned_msoa, assigned_la, assigned_ttwa,
    Group, site_size, treated_today
  )

# Write it back out
write_parquet(control, control_out_path)
