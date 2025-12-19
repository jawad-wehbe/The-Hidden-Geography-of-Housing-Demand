
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

#-----------------------------------------------------------------------------------------------------------------------
# Note this will produce less sites 6000 vs 6700 compared to the other shock construction (using end date) script 
# as there it was possible for a site to have completed after 2019 but started before 2019, this code filters them out
# also this code does not carry all the variables produced in the original code, it only carries the shock week and year
#----------------------------------------------------------------------------------------------------------------------


rm(list =ls())

# Define paths (edit as needed)
base_data_dir <- path.expand("~/Desktop/Raw_Data/NHBC")
out_dir <- "~/Desktop/Projects/housing_targets/produced/search_on_build_shock/setup"

gpkg_path <- file.path(
  path.expand("~/Desktop/Raw_Data/Shapefiles etc"),
  "output_areas_2021.gpkg"
)

# Read and clean CSVs
plots <- read_csv(file.path(base_data_dir, "plot.csv")) %>%
  clean_names()

snin <- read_csv(file.path(base_data_dir, "SNIN.csv")) %>%
  clean_names()

# Flag invalid storeys
plots <- plots %>%
  mutate(invalid_storeys = number_of_storeys >= 999)

# Join with construction site data BEFORE any date filtering
plots_sited <- plots %>%
  inner_join(snin, by = "snin_reference")

# Assign 'first_date' = 'start_date' for each plot (everything that follows is referenced as first date)
plots_sited <- plots_sited %>%
  mutate(first_date = start_date)

# Drop only plots with missing first_date 
snin_plots <- plots_sited %>%
  filter(!is.na(first_date))

#----------------------------------------------------------------------------------
# Filtering the main data post-2019 for shock construction now
#----------------------------------------------------------------------------------

# Cutoff date
cutoff <- as.Date("2019-01-01")

# find sites whose first completion ≥ cutoff
sites_to_keep <- snin_plots %>%
  group_by(construction_site_id) %>%
  summarise(
    first_plot = min(first_date, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  filter(first_plot >= cutoff) %>%
  pull(construction_site_id)

# subset the dataset
plots_2019_orig <- snin_plots %>%
  filter(construction_site_id %in% sites_to_keep)

message("Total plots in filtered sites: ", nrow(plots_2019_orig))

#--------------------------------------------------------------
# 4. Identify “big” sites (≥20 distinct plots)
#----------------------------------------------------------------

# Pull site is for sites with more than 20 plots
big_sites <- plots_2019_orig %>%
  # 1) one row per real, dated plot
  distinct(construction_site_id, plot_id) %>%
  
  # 2) count completed plots per site
  count(construction_site_id, name = "n_plots") %>%
  
  # 3) keep only sites with ≥ 20 completed plots
  filter(n_plots >= 20) %>%
  
  # 4) pull the site IDs
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
# Note: We are keeping only sites that had a first plot started

site_summary <- plots_big_orig %>%
  group_by(construction_site_id) %>%
  
  # Keep only sites with at least one completed plot (this is just validation check)
  filter(any(!is.na(first_date))) %>%
  
  summarise(
    # Earliest plot start date (any status)
    shock_week = floor_date(min(first_date, na.rm = TRUE), "week", week_start = 1)
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
# Read & parse WKT → sf
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
  select(-wkt_clean) %>%
  st_drop_geometry(site_weekly_oa)


# format date to match search data
site_weekly_oa <- site_weekly_oa %>%
  mutate(
    # pull year 
    shock_year            = isoyear(shock_week),
    # pull week
    shock_week            = isoweek(shock_week)
  ) %>%
  select(
    construction_site_id,
    shock_year,   shock_week,
    site_size,
    intersecting_oa
  ) %>%
  group_by(construction_site_id) %>%
  filter(all(shock_year < 2025)) %>%
  ungroup()%>%
  unnest(intersecting_oa)

#  Define the full file path
out_parquet <- file.path(out_dir, "sd_shock_oa.parquet")

#  Write to Parquet 
write_parquet(site_weekly_oa, out_parquet)


