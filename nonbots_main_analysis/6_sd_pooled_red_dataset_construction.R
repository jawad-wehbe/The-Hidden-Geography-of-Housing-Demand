# ────────────────────────────────────────────────────────────────────────────────
#   LOAD LIBRARIES 
# ────────────────────────────────────────────────────────────────────────────────
library(arrow)    
library(dplyr)     
library(fixest)    
library(broom)     
library(tidyr)     
library(stringr)   
library(ggplot2)

rm(list = ls())    # clear all existing objects from the environment
gc()

# ────────────────────────────────────────────────────────────────────────────────
# Structure:
# same as the ed_pooled_red_dataset_construction.R but using start date
# ────────────────────────────────────────────────────────────────────────────────

# ────────────────────────────────────────────────────────────────────────────────
#   DEFINE FILE PATHS AND READ IN DATA
# ────────────────────────────────────────────────────────────────────────────────
weekly_path     <- "~/Desktop/Projects/housing_targets/produced/nature/nonbots/all/oa_weekly_search_with_geos.parquet"
shock_path      <- "~/Desktop/Projects/housing_targets/produced/search_on_build_shock/setup/sd_shock_oa.parquet" # SAME AS ORIGINAL ONE NOT RELATED TO SEARCHES
cw_oa_msoa_path <- "~/Desktop/Raw_Data/Shapefiles/Crosswalks/oa_msoa.parquet"
control_path <- "/home/jawad/Desktop/Projects/housing_targets/produced/nature/nonbots/all/sd_control_oa_weekly.parquet"
reg_dataset_path <- "~/Desktop/Projects/housing_targets/produced/nature/nonbots/all/"

# read weekly search data and collapse any week == 53 into week == 52 for consistency
weekly <- read_parquet(weekly_path) %>%
  mutate(week = if_else(week == 53, 52L, week))

# read the shock events (one row per OA shock) 
shock    <- read_parquet(shock_path)

# read the OA → MSOA crosswalk (as reference for OA completeness)
cw_xwalk <- read_parquet(cw_oa_msoa_path)

# read in the control data (contains only OAs in never-shocked MSOAs)
control_weekly <- read_parquet(control_path)

# list of all OA codes that ever appear in a shock
treated_oas <- unique(shock$intersecting_oa)

# ────────────────────────────────────────────────────────────────────────────────
#  BUILD THE MASTER TREATED TABLE
# ────────────────────────────────────────────────────────────────────────────────
# start from weekly, keep only OAs that ever have a shock, tags shock‐weeks
treated <- weekly %>%
  filter(oa_code %in% treated_oas) %>%    # only rows for OAs in shock list
  inner_join(shock, by = c("oa_code" = "intersecting_oa")) %>%  # join in shock_year, shock_week, construction_site_id
  mutate(
    Group         = "Treat",      # label all these rows as “Treat”
    treated_today = if_else(       # mark 1 only on the actual shock week
      year  == shock_year & 
        week  == shock_week,
      1L, 0L
    )       
  ) %>%
  select(
    # keep just the columns we need, now including assigned_ttwa
    construction_site_id,
    oa_code, year, week,
    buying_searches, letting_searches,
    assigned_lsoa, assigned_msoa, assigned_la, assigned_ttwa,
    Group, site_size, treated_today
  ) %>%
  group_by(construction_site_id) %>%   # drop any site IDs that ended up with no shock‐week 
  filter(any(treated_today == 1L)) %>%  
  ungroup()

# ────────────────────────────────────────────────────────────────────────────────
#  LOOP OVER EACH SHOCK SITE: EVENT‐STUDY & REGRESSIONS
# ────────────────────────────────────────────────────────────────────────────────

# Extract site IDs

site_ids    <- unique(treated$construction_site_id)
all_shock_dfs <- list()  # Store all per-shock dataframes

for (i in seq_along(site_ids)) {
  this_id <- site_ids[i]
  message("Running site ", this_id, " (", i, " of ", length(site_ids), ")")
  
  # Grab the treated OA×YW rows for this site
  treat_site <- treated %>%
    filter(construction_site_id == this_id)
  
  # Identify all TTWAs "hit" by this shock (all assigned_ttwa values for the treated OAs)
  ttw_as_hit <- unique(treat_site$assigned_ttwa)
  
  # CONTROL: All OAs from the control table, in the same TTWA(s) as the treated OAs
  ttwa_controls <- control_weekly %>%
    filter(
      assigned_ttwa %in% ttw_as_hit
    ) %>%
    mutate(
      construction_site_id = this_id
    ) %>%
    select(
      construction_site_id,
      oa_code, year, week,
      buying_searches, letting_searches,
      assigned_lsoa, assigned_msoa, assigned_la, assigned_ttwa,
      Group, site_size, treated_today
    )
  
  # bind treated and control for this site
  output <- bind_rows(treat_site, ttwa_controls)
  
  # compute relative year‑week index (zero = shock week)
  site_shock <- shock %>%
    filter(construction_site_id == this_id) %>%
    distinct(shock_year, shock_week) %>%
    slice(1)
  
  df <- output %>%
    mutate(
      rel_yw = (year - site_shock$shock_year) * 52 +
        (week - site_shock$shock_week)
    ) %>%
    filter(rel_yw >= -26, rel_yw <= 52)  
  
  # Only proceed if this site has a complete -26:55 window
  if (all((-26):52 %in% df$rel_yw)) {
    
    # generate event-study dummies as before
    for (k in -26:52) {
      varname <- if (k < 0) paste0("Treated_m", abs(k)) else paste0("Treated_", k)
      df <- df %>%
        mutate(
          !!varname := as.integer(Group == "Treat" & rel_yw == k)
        )
    }
    output_cleaned <- df  # final per site data ready for regression
    
    all_shock_dfs[[length(all_shock_dfs) + 1]] <- output_cleaned %>% 
      mutate(construction_site_id = this_id)
    
    #  print message:
    message("Included site ", this_id)
    
    total_so_far <- sum(sapply(all_shock_dfs, nrow))
    
    cat("Current total rows in stacked dataset (so far):", total_so_far, "\n")
    
  } else {
    
    #  print message if dropped:
    message("Site ", this_id, " skipped (not a full window)")
    
  }
  
  # clear memory 
  if (exists("output_cleaned")) rm(output_cleaned) # this is because the output cleaned is formed in the if condition
  
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

# save data set so we can use for later for any regression 
write_parquet(
  stacked_df,
  file.path(reg_dataset_path, "sd_reg_dataset.parquet")
)

rm(list=ls())
gc()

