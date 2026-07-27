
library(here)
library(lubridate)
library(ggplot2)
library(readr)       
library(dplyr)
library(zoo)        
library(survival)
library(janitor)
library(sf)
library(tidyverse)
library(arrow)

# Clear environment
rm(list = setdiff(ls(), "prop_summary")); gc()

# define paths

base_data_dir <- path.expand("~/Desktop/Raw_Data/NHBC")
out_dir <- "~/Desktop/Projects/housing_targets/produced/search_on_build_shock/setup"


gpkg_path <- file.path(
  path.expand("~/Desktop/Raw_Data/Shapefiles"),
  "output_areas_2021.gpkg"
)

# Read and clean CSVs

plots <- read_csv(file.path(base_data_dir, "plot.csv")) %>%
  clean_names() %>%
  mutate(
    registered_date        = as.Date(registered_date),
    warranty_final_date    = as.Date(warranty_final_date),
    bc_final_date          = as.Date(bc_final_date),
    legal_completion_date  = as.Date(legal_completion_date),
    start_date  = as.Date(start_date),
    first_pho_date = as.Date(first_pho_date)
  ) 

snin  <- read_csv(file.path(base_data_dir, "SNIN.csv")) %>%
  clean_names() %>%
  mutate(
    site_status_date = as.Date(site_status_date)
    ) 

inspection <- read_csv(file.path(base_data_dir, "inspection.csv")) %>%
  clean_names() %>%
  mutate(inspection_date = as.Date(inspection_date)) %>%
  filter(insp_group == "Handover") # keep only handover here


# keep the last inspection date for a given plot

handover_dates <- inspection %>%
  group_by(snin_reference, plot_no) %>%
  summarise(
    handover_date = max(inspection_date, na.rm = TRUE),
    .groups = "drop"
  )

# flag those with more than or equal to 999 stories

plots <- plots %>%
  mutate(
    invalid_storeys = number_of_storeys >= 999
  )
#------------------------------------------------------------------------
# Creating a DATE variable with the first of warrant amd bc an if both are missing fall back to legal date
#-------------------------------------------------------------------------
plots_init <- plots %>%
  mutate(
    # 1. Get the earliest of BC vs. warranty, but stay NA if both are missing
    bc_or_warranty = case_when(
      !is.na(bc_final_date) & !is.na(warranty_final_date) ~ 
        pmin(bc_final_date, warranty_final_date),
      !is.na(bc_final_date) ~ bc_final_date,
      !is.na(warranty_final_date) ~ warranty_final_date,
      TRUE ~ as.Date(NA_character_)
    ),
    
    # 2. Fallback to legal_completion_date if bc_or_warranty is still NA
    first_date = coalesce(bc_or_warranty, legal_completion_date),
    
    # 3. Record which source we actually used
    first_var = case_when(
      !is.na(bc_or_warranty) & bc_or_warranty == bc_final_date        ~ "bc_final_date",
      !is.na(bc_or_warranty) & bc_or_warranty == warranty_final_date  ~ "warranty_final_date",
      is.na(bc_or_warranty) & !is.na(legal_completion_date)           ~ "legal_completion_date",
      TRUE                                                            ~ NA_character_
    )
  ) %>%
  select(-bc_or_warranty)
#--------------------------------------------------------------------------------
#  Extract plots that has first date var without inspection or first_pho_date
# ------------------------------------------------------------------------------
plots_done <- plots_init %>%
  filter(!is.na(first_date))

# sanity check to see those missing still
plots_missing <- plots_init %>%
  filter(is.na(first_date))

#------------------------------------------------------------------------------
# For remaining plots, join handover & fallback to first_pho_date or incomplete
# ----------------------------------------------------------------------------

plots_todo <- plots_init %>%
  # only those still missing a milestone date
  filter(is.na(first_date)) %>%
  
  # bring in the last handover date
  left_join(handover_dates, by = c("snin_reference", "plot_no")) %>%
  
  # compute fallbacks
  mutate(
    # only use first_pho_date if it didn’t fail
    valid_first_pho = if_else(
      failed_first_pho == "N", 
      first_pho_date, 
      as.Date(NA_character_)
    ),
    
    # pick handover first, then valid_first_pho
    first_date = coalesce(handover_date, valid_first_pho),
    
    # label which source we used
    first_var = case_when(
      !is.na(handover_date)    ~ "handover_inspection_date",
      !is.na(valid_first_pho)  ~ "first_pho_date",
      TRUE                     ~ "incomplete"
    )
  )

# ----------------------
# Bring it all together
# -----------------------

plots_final <- bind_rows(plots_done, plots_todo)


#------------------------------
# Merge plot & project tables
#------------------------------

snin_plots <- plots_final %>%
  inner_join(snin, by = "snin_reference")

# remove na start dates

snin_plots <- snin_plots %>%
  filter(!is.na(start_date))


#----------------------------------------------------------------------------------
# Filtering the main data post-2019 for shock construction now
#----------------------------------------------------------------------------------

# Cutoff date
cutoff <- as.Date("2019-01-01")

# Step A: drop every project (snin_reference) that has no recorded first_date
# Otherwise, we might have a site that has 2 projects one that works and another that is just random data error(ex: error 6000 plots planned)
snin_plots_valid <- snin_plots %>%
  group_by(construction_site_id, snin_reference) %>%
  filter(any(!is.na(first_date))) %>%  # keep projects with at least one non-NA
  ungroup()

# Step B: find sites whose first completion ≥ cutoff
sites_to_keep <- snin_plots_valid %>%
  group_by(construction_site_id) %>%
  summarise(
    first_plot = min(first_date, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  filter(first_plot >= cutoff) %>%
  pull(construction_site_id)

# Step C: subset the dataset
plots_2019_orig <- snin_plots_valid %>%
  filter(construction_site_id %in% sites_to_keep)

message("Total plots in filtered sites: ", nrow(plots_2019_orig))

#--------------------------------------------------------------
# 4. Identify “big” sites (≥20 distinct plots)
#----------------------------------------------------------------

# Pull site is for sites with more than 20 plots
big_sites <- plots_2019_orig %>%
  # 1) build a completion_date from first_date only, drop any rows without it
  mutate(completion_date = first_date) %>%
  
  # 2) one row per real, dated plot
  distinct(construction_site_id, plot_id) %>%
  
  # 3) count completed plots per site
  count(construction_site_id, name = "n_plots") %>%
  
  # 4) keep only sites with ≥ 20 completed plots
  filter(n_plots >= 20) %>%
  
  # 5) pull the site IDs
  pull(construction_site_id)

message("Big sites found: ", length(big_sites), " IDs")

# Keep only those data sites
plots_big_orig <- plots_2019_orig %>%
  filter(construction_site_id %in% big_sites)

# Define the site statuses we want to keep
keep_status <- c("ACTIVE", "COMPLETED", "ENQUIRY", "RESURECTED")

# Filter the dataset to keep only those sites
plots_big_orig <- plots_big_orig %>%
  filter(site_status %in% keep_status)

# Sum over distinct number of plots planned within a site across different projects
site_size <- plots_big_orig %>%
  # one row per project, per site
  distinct(construction_site_id, snin_reference, no_of_plots_planned) %>%
  # sum planned plots across projects
  group_by(construction_site_id) %>%
  summarise(
    site_size = sum(no_of_plots_planned),
    .groups   = "drop"
  )

# Site‐level summary (dates, YW codes, planned size)
# Note: We are keeping only sites that had a first plot completed (can be incomplete sites)

site_summary <- plots_big_orig %>%
  group_by(construction_site_id) %>%
  
  # Keep only sites with at least one completed plot
  filter(any(!is.na(first_date))) %>%
  
  summarise(
    # Earliest completed plot (any status)
    shock_week = floor_date(min(first_date, na.rm = TRUE), "week", week_start = 1),
    first_plot_start_week = floor_date(start_date[which.min(first_date)], "week", week_start = 1),
    
    # first plot, weeks only if COMPLETED, else NA
    last_plot_start_week = if_else(
      site_status[which.max(first_date)] == "COMPLETED",
      floor_date(start_date[which.max(first_date)], "week", week_start = 1),
      as.Date(NA)
    ),
    last_plot_end_week = if_else(
      site_status[which.max(first_date)] == "COMPLETED",
      floor_date(first_date[which.max(first_date)], "week", week_start = 1),
      as.Date(NA)
    )
  ) %>%
  ungroup()


# 3) Bring them together
site_summary <- site_summary %>%
  left_join(site_size, by = "construction_site_id")


#------------------------------------------------------------------------------------
# Now reattaching site location and repairing the snin data: 
# Issue 1: some polygons are invalid
# Issue 2: some construction site ids have multiple polygons (need to union them)
#-----------------------------------------------------------------------------------
snin <- snin %>%
  filter(!is.na(wkt), wkt != "")   # drop missing/blank WKT right away

# ───────────────────────────────────────────────────────────────────────────────
# 1. Issue 1: Parse to sf & repair invalid geometries, then undo the sf
# ───────────────────────────────────────────────────────────────────────────────
# Read and parse WKT to sf
snin_sf <- snin %>%
  filter(!is.na(wkt), wkt != "") %>%
  st_as_sf(wkt = "wkt", crs = 27700)

# Drop the one row that is not connected and make valid everything else:

snin_fixed <- snin_sf %>%
  slice(-8536) %>%
  st_make_valid()
stopifnot(all(st_is_valid(snin_fixed)))

# Back to tibble with cleaned WKT
snin_repaired <- snin_fixed %>%
  mutate(wkt_clean = st_as_text(st_geometry(.))) %>%
  st_drop_geometry()

# ───────────────────────────────────────────────────────────────────────────────
# 2. Issue 2: Union only the IDs with >1 distinct WKT
# ───────────────────────────────────────────────────────────────────────────────
# 2a. Find the “multi‐WKT” IDs

# 2a. Identify sites with more than one distinct WKT geometry
multi_geom_sites <- snin_repaired %>%
  distinct(construction_site_id, wkt_clean) %>%
  count(construction_site_id, name = "n_geom") %>%
  filter(n_geom > 1) %>%
  pull(construction_site_id)
message("Sites with multiple geometries: ", length(multi_geom_sites))

# 2b. Union just the multi-polygon sites
unioned_wkts <- snin_repaired %>%
  filter(construction_site_id %in% multi_geom_sites) %>%
  # parse back into an sf so we get a real geometry column
  st_as_sf(wkt = "wkt_clean", crs = 27700) %>%
  group_by(construction_site_id) %>%
  summarise(
    wkt_clean = st_as_text(          #  final text
      st_union(                      #  union all parts
        st_geometry(.)               # extract the geometry list-column
      )
    ),
    .groups = "drop"
  ) 

# 2c. keep single‐polygon sites

single_sf <- snin_repaired %>%
  filter(!construction_site_id %in% multi_geom_sites) %>%
  distinct(construction_site_id, wkt_clean) %>%
  st_as_sf(wkt = "wkt_clean", crs = 27700)

# 2d. Bind them together as one sf

site_geom_clean <- bind_rows(unioned_wkts, single_sf)

# 3. Join to our monthly data (now both are sf)

site_weekly_sf <- site_geom_clean %>%
  inner_join(site_summary, by="construction_site_id")


#-----------------------------------------------------------------------------
# CHECK THE SITES THAT INTERSECT OUTPUT AREAS 
#----------------------------------------------------------------------------------



# Read the Output Areas
output_areas <- st_read(
  dsn   = gpkg_path,
  layer = "output_areas_2021") %>% 
st_transform(
   crs = st_crs(site_weekly_sf)
 )


# 2. For each row in site_monthly_sf, get the indices of output_areas it intersects
ia_list <- st_intersects(site_weekly_sf, output_areas)

# 3. Add oa_code 
site_weekly_oa <- site_weekly_sf %>%
  mutate(
    intersecting_oa = map(ia_list, ~ {
      if (length(.x) > 0) {
        output_areas$oa_code[.x]
      } else {
        NA_character_
      }
    })
  )

# drop the polygon data
site_weekly_oa <- site_weekly_oa %>%
  select(-wkt_clean) 

site_weekly_oa  %>% st_drop_geometry()

# Measure the duration it took for first plot to be completed
site_weekly_oa <- site_weekly_oa %>%
  mutate(
    # both shock_week and first_plot_start_week are already at week‐start
    weeks_until_first_plot_completion = 
      as.integer( (shock_week- first_plot_start_week) / 7 )
  ) 


# There are 2 sites with negative weeks in between due to data reporting errors
# Drop them
site_weekly_oa <- site_weekly_oa %>%
  filter(weeks_until_first_plot_completion >= 0) %>%
  unnest(intersecting_oa)
  
# formate date to match search data
site_weekly_oa <- site_weekly_oa %>%
  mutate(
    # pull year
    shock_year            = isoyear(shock_week),
    # pull week
    shock_week            = isoweek(shock_week),
    
    first_plot_start_year = isoyear(first_plot_start_week),
    first_plot_start_week = isoweek(first_plot_start_week),
    
    last_plot_start_year  = isoyear(last_plot_start_week),
    last_plot_start_week  = isoweek(last_plot_start_week),
    
    last_plot_end_year    = isoyear(last_plot_end_week),
    last_plot_end_week    = isoweek(last_plot_end_week)
  ) %>%
  select(
    construction_site_id,
    shock_year,   shock_week,
    first_plot_start_year,  first_plot_start_week,
    last_plot_start_year,   last_plot_start_week,
    last_plot_end_year,     last_plot_end_week,
    site_size,
    weeks_until_first_plot_completion,
    intersecting_oa
  ) %>%
  group_by(construction_site_id) %>%
  filter(all(shock_year < 2025)) %>%
  ungroup()


#  Define the full file path 
out_parquet <- file.path(out_dir, "ed_shock_oa.parquet")

#  Write to Parquet
write_parquet(site_weekly_oa, out_parquet)


