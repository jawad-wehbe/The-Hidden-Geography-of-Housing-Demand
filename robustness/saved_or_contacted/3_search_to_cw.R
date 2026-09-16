library(dplyr)
library(arrow)
library(here)

rm(list =ls())
source(file.path(here(), "config.R"))   # CONFIG (placed after rm(list = ls()) so the config survives): all data roots come from config.R (real or demo mode)

# set up paths 
search_out_dir <- path.expand(file.path(project_root, "produced/hidden_geography_of_housing_demand/nonbots/saved_or_contacted/"))   # CONFIG
out_fp <- file.path(search_out_dir, "oa_weekly_search_with_geos.parquet")
weekly_fp  <- file.path(search_out_dir, "oa_weekly_search.parquet")
cw_dir <- path.expand(file.path(shapefiles_root, "Crosswalks"))   # CONFIG

# read the crosswalk Parquets
cw_oa_lsoa <- read_parquet(file.path(cw_dir, "oa_lsoa.parquet"))
cw_oa_msoa <- read_parquet(file.path(cw_dir, "oa_msoa.parquet"))
cw_oa_la   <- read_parquet(file.path(cw_dir, "oa_la.parquet"))
cw_oa_ttwa <- read_parquet(file.path(cw_dir, "oa_ttwa.parquet"))

# 3) for each OA pick the *one* target with the max share
oa_to_lsoa <- cw_oa_lsoa %>%
  group_by(oa_code) %>%
  slice_max(share, n = 1, with_ties = FALSE) %>%
  ungroup() %>%
  select(oa_code, assigned_lsoa = lsoa_code)

oa_to_msoa <- cw_oa_msoa %>%
  group_by(oa_code) %>%
  slice_max(share, n = 1, with_ties = FALSE) %>%
  ungroup() %>%
  select(oa_code, assigned_msoa = msoa_code)

oa_to_la <- cw_oa_la %>%
  group_by(oa_code) %>%
  slice_max(share, n = 1, with_ties = FALSE) %>%
  ungroup() %>%
  select(oa_code, assigned_la = la_code)

oa_to_ttwa <- cw_oa_ttwa %>%
  group_by(oa_code) %>%
  slice_max(share, n = 1, with_ties = FALSE) %>%
  ungroup() %>%
  select(oa_code, assigned_ttwa = ttwa_code)  

# read weekly‐search dataset
search_weekly <- read_parquet(weekly_fp)


# join on the three assignment tables
search_weekly_assigned <- search_weekly %>%
  left_join(oa_to_lsoa, by = "oa_code") %>%
  left_join(oa_to_msoa, by = "oa_code") %>%
  left_join(oa_to_la,   by = "oa_code") %>%
  left_join(oa_to_ttwa, by = "oa_code")

# check the missing lsoa
missing_lsoa_rows <- search_weekly_assigned %>%
  filter(is.na(assigned_lsoa))

# write the augmented table back out

write_parquet(search_weekly_assigned, out_fp)

message("Wrote augmented weekly table to:\n  ", out_fp)

oa_weekly_search<- read_parquet(out_fp)

