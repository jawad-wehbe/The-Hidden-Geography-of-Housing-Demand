# ────────────────────────────────────────────────────────────────────────────────
#   LOAD LIBRARIES 
# ────────────────────────────────────────────────────────────────────────────────
library(arrow)    
library(dplyr)     
library(fixest)    
library(broom)     
library(tidyr)     
library(stringr)   
library(dplyr)
library(tidyr)
library(ggplot2)

rm(list = ls())    # clear all existing objects from the environment

# ────────────────────────────────────────────────────────────────────────────────
# Structure:
#   IDENTIFY TREATED OAS (OAs that ever have a shock)
#   BUILD TREATED DATASET:
#      - Keep only treated OAs, tag treatment weeks, add shock info
#   LOOP OVER EACH SHOCK SITE:
#      For each construction_site_id:
#      a. Pull all treated rows for this site
#      b. Identify all assigned TTWAs for treated OAs of this site
#      c. Pull all control OAs in same TTWA(s) from control_weekly
#         - SKIP SITE IF NO CONTROLS AVAILABLE
#      d. Bind treated and controls for this site
#      e. Compute relative week (rel_yw) for each row, based on shock date
#      f. Filter to event-study window (-26 to 52)
#      g. SKIP SITE IF ANY WEEK IN WINDOW IS MISSING
#      h. For included sites, generate event-study dummies for each week in window
#      i. Store processed data for included sites in list
#      j. Clean up memory
#    COMBINE ALL SITES INTO STACKED EVENT-STUDY DATASET
#    SAVE FINAL DATASET FOR FUTURE REGRESSIONS/ANALYSIS
# ─────────────────────────────────────────────────────────────────────────────


# ────────────────────────────────────────────────────────────────────────────────
#   DEFINE FILE PATHS AND READ IN DATA
# ────────────────────────────────────────────────────────────────────────────────
weekly_path     <- "~/Desktop/Projects/housing_targets/produced/search_on_build_shock/setup/oa_weekly_search_with_geos.parquet"
shock_path      <- "~/Desktop/Projects/housing_targets/produced/search_on_build_shock/setup/ed_shock_oa.parquet"
cw_oa_msoa_path <- "~/Desktop/Raw_Data/Shapefiles/Crosswalks/oa_msoa.parquet"
output_path     <- "~/Desktop/Projects/housing_targets/output/tables/"
control_path    <- "~/Desktop/Projects/housing_targets/produced/search_on_build_shock/analysis/ed_control_oa_weekly.parquet"
reg_dataset_path <- "~/Desktop/Projects/housing_targets/produced/search_on_build_shock/analysis/"

# read data
weekly <- read_parquet(weekly_path) %>%
  mutate(week = if_else(week == 53, 52L, week))

shock    <- read_parquet(shock_path)
cw_xwalk <- read_parquet(cw_oa_msoa_path) # used for reference to all OAs
control_weekly <- read_parquet(control_path)

# FIND TREATED OAs
treated_oas <- unique(shock$intersecting_oa)

# ────────────────────────────────────────────────────────────────────────────────
#  BUILD THE MASTER TREATED TABLE
# ────────────────────────────────────────────────────────────────────────────────
treated <- weekly %>%
  filter(oa_code %in% treated_oas) %>%
  inner_join(shock, by = c("oa_code" = "intersecting_oa")) %>%
  mutate(
    Group         = "Treat",
    treated_today = if_else(year == shock_year & week == shock_week, 1L, 0L)
  ) %>%
  select(
    construction_site_id,
    oa_code, year, week,
    buying_searches, letting_searches,
    assigned_lsoa, assigned_msoa, assigned_la, assigned_ttwa,
    Group, site_size, treated_today
  ) %>%
  group_by(construction_site_id) %>%
  filter(any(treated_today == 1L)) %>%
  ungroup()

# ────────────────────────────────────────────────────────────────────────────────
#  LOOP OVER EACH SHOCK SITE: EVENT-STUDY & REGRESSIONS
# ────────────────────────────────────────────────────────────────────────────────

# choose event window
window_lower <- -26
window_upper <- 52
window_range <- window_lower:window_upper

# extract site ids
site_ids <- unique(treated$construction_site_id)
all_shock_dfs <- list()

for (i in seq_along(site_ids)) {
  this_id <- site_ids[i]
  message("Running site ", this_id, " (", i, " of ", length(site_ids), ")")
  
  # Treated: OA×YW rows for this site
  treat_site <- treated %>%
    filter(construction_site_id == this_id)
  
  # TTWA(s) "hit" by this shock
  ttw_as_hit <- unique(treat_site$assigned_ttwa)
  
  # Control: all OAs in control table, in those TTWAs
  ttwa_controls <- control_weekly %>%
    filter(assigned_ttwa %in% ttw_as_hit) %>%
    mutate(
      construction_site_id = this_id,
      Group = "Control",
      treated_today = 0L,
      site_size = 0L
    ) %>%
    select(
      construction_site_id,
      oa_code, year, week,
      buying_searches, letting_searches,
      assigned_lsoa, assigned_msoa, assigned_la, assigned_ttwa,
      Group, site_size, treated_today
    )
  
  # Bind treated and control for this site
  output <- bind_rows(treat_site, ttwa_controls)
  
  # Shock date for this site
  site_shock <- shock %>%
    filter(construction_site_id == this_id) %>%
    distinct(shock_year, shock_week) %>%
    slice(1)
  
  # Compute rel_yw and filter to window
  df <- output %>%
    mutate(
      rel_yw = (year - site_shock$shock_year) * 52 + (week - site_shock$shock_week)
    ) %>%
    filter(rel_yw >= window_lower, rel_yw <= window_upper)
  
  # Only proceed if this site has a complete -26:26 window
  if (all(window_range %in% df$rel_yw)) {
    for (k in window_range) {
      varname <- if (k < 0) paste0("Treated_m", abs(k)) else paste0("Treated_", k)
      df <- df %>%
        mutate(
          !!varname := as.integer(Group == "Treat" & rel_yw == k)
        )
    }
    # rename
    output_cleaned <- df
    # add results to vector
    all_shock_dfs[[length(all_shock_dfs) + 1]] <- output_cleaned %>% mutate(construction_site_id = this_id)
    message("Included site ", this_id)
    
    #count how many rows so far
    total_so_far <- sum(sapply(all_shock_dfs, nrow))
    cat("Current total rows in stacked dataset (so far):", total_so_far, "\n")
  } else {
    message("Site ", this_id, " skipped (not a full window)")
  }
  
  # clear memory for ram usage
  if (exists("output_cleaned")) rm(output_cleaned)
  rm(treat_site, ttw_as_hit, ttwa_controls, output, site_shock, df)
  gc()
}

stacked_df <- bind_rows(all_shock_dfs)


# Identify sites that DO have a Control group
sites_with_control <- stacked_df %>%
  group_by(construction_site_id) %>%
  summarise(has_control = any(Group == "Control")) %>%
  filter(has_control) %>%
  pull(construction_site_id)

# Filter the original data to keep only these sites
stacked_df <- stacked_df %>%
  filter(construction_site_id %in% sites_with_control)

# Save for future use
write_parquet(
  stacked_df,
  file.path(reg_dataset_path, "ed_reg_dataset.parquet")
)


rm(list=ls())
gc()



