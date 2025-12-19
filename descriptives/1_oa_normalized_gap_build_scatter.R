library(sf)
library(dplyr)
library(ggplot2)
library(readr)
library(janitor)  
library(ggmap)
library(arrow)
library(lubridate)
library(scales)
library(patchwork)
library(tidyr)
library(rnaturalearth)   # for a simple UK outline
library(Hmisc)
rm(list = ls())

####################
# Load paths
####################

sites_path <- "~/Desktop/Raw_Data/NHBC/"

base_data_dir <- path.expand("~/Desktop/Raw_Data/NHBC")

oa_path <- "~/Desktop/Raw_Data/Shapefiles etc/output_areas_2021.gpkg"

gap_path <- "~/Desktop/Raw_Data/Shapefiles etc/Other/oa_la_combined_stats.csv"

temp <- "~/Desktop/Projects/housing_targets/temp/gap/build_gap.csv"

# fig dir

fig_dir <- "~/Desktop/Projects/housing_targets/output/figures/gap/"

####################
# Read in the data
######################
# Sites
sites_df <- read_csv(file.path(base_data_dir, "SNIN.csv")) %>% 
  clean_names() 


# Plots data

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

# Inspection data
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


# OA data

oa <- st_read(oa_path)


# Gap Data

gap <- read_csv(gap_path) 


###############################
###############################
# Create the completion date
##############################
##############################

#------------------------------------------------------------------------
# Creating a DATE variable with the first of warrant and bc an if both are missing fall back to legal date
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

plots_df <- bind_rows(plots_done, plots_todo)

# for our purposes keep only completed plots
plots_df <- plots_df %>%
  filter(!is.na(first_date))


########################################################################
# Cleaning up sites data
####################################################################


#------------------------------------------------------------------------------------
# Now reattaching site location and repairing the snin data: 
# Issue 1: some polygons are invalid
# Issue 2: some construction site ids have multiple polygons (need to union them)
#-----------------------------------------------------------------------------------
snin <- sites_df %>%
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

# 2b. Union just the multi-polygon sites, using st_geometry(.)
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

# 2c. Do the same for single‐polygon sites (also keep as sf)

single_sf <- snin_repaired %>%
  filter(!construction_site_id %in% multi_geom_sites) %>%
  distinct(construction_site_id, wkt_clean) %>%
  st_as_sf(wkt = "wkt_clean", crs = 27700)

# 2d. Bind them together as one sf

site_geom_clean <- bind_rows(unioned_wkts, single_sf)

# make valid

site_geom_clean <- st_make_valid(site_geom_clean)

#######################################################
# Intersect Sites with OAa
#######################################################

#  Ensure both  have the same CRS 
oa_proj <- st_transform(oa, st_crs(site_geom_clean))

# Get original site area
area <- site_geom_clean %>%
  st_make_valid() %>%
  mutate(site_area = st_area(wkt_clean)) %>%
  st_drop_geometry()

# intersect them
site_oa <- st_intersection(
  site_geom_clean %>% select(construction_site_id, wkt_clean),
  oa_proj
)

# Assign intersection area and proportion
site_oa_metrics <- site_oa %>%
  mutate(
    intersection_area = st_area(wkt_clean)
  ) %>%
  left_join(area, by = "construction_site_id") %>%
  mutate(
    intersection_prop = as.numeric(intersection_area / site_area)
  )

# Keep OA with highest intersection proportion for each site
site_oa_highest <- site_oa_metrics %>%
  group_by(construction_site_id) %>%
  slice_max(intersection_prop, n = 1, with_ties = FALSE) %>%
  ungroup()


# Drop geometery once and for all
site_oa_highest <- site_oa_highest %>%
  st_drop_geometry() %>%
  select(oa_code, construction_site_id)

# bring this back to sites

sites_final <- sites_df %>%
  select(construction_site_id, snin_reference) %>%
  inner_join(site_oa_highest, by = "construction_site_id")

################################################
# Bring in the plots
#################################################

plots_final <- plots_df %>%
  inner_join(sites_final, by = "snin_reference")

# select relevant columns

plots_final <- plots_final %>%
  select(plot_id, snin_reference, construction_site_id, first_date, oa_code)


# filter to year 2010 and 2020

plots_final <- plots_final %>%
  filter(year(first_date) >= 2010 & year(first_date) <= 2020)


####################################
# Get number of plots built per OA
####################################

plots_per_oa <- plots_final %>%
  group_by(oa_code) %>%
  summarise(
    n_plots = n_distinct(plot_id)
  )


################################################
# Bring in the gap
###############################################

# Select relavnt columns
gap_per_oa <- gap %>%
  select(oa_code, gap, gap_per_km2)


# merge everything and INCLUDE OAs with no builds
plot_gap <- gap_per_oa %>%
  left_join(plots_per_oa, by = "oa_code") %>%
  mutate(
    n_plots = replace_na(n_plots, 0)
  )


# normalize total gap across uk to total builds in the period
# first find scaling factor

normalizing_factor <- sum(plot_gap$n_plots)/sum(plot_gap$gap)

normalize_plot_gap <- plot_gap %>%
  mutate(
    normalized_gap = gap * normalizing_factor
  )
  


###################################################
# Plotting
################################################
max_val <- max(
  c(normalize_plot_gap$normalized_gap, normalize_plot_gap$n_plots),
  na.rm = TRUE
)
min_x <- min(normalize_plot_gap$normalized_gap, na.rm = TRUE)

# Plot 1: Builds vs Normalized GAP
p1 <- ggplot(normalize_plot_gap, aes(x = normalized_gap, y = n_plots)) +
  geom_point(alpha = 0.25, size = 1.5) +
  geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "blue") +
  annotate(
    "text",
    x = max_val,
    y = max_val,
    label = "45 degree line",
    hjust = 1.1, vjust = 1.1, size = 5, color = "blue", angle = 45
  ) +
  geom_vline(xintercept = 0, linetype = "dashed", color = "red") +
  geom_hline(yintercept = 0, linetype = "dashed", color = "black") +
  scale_x_continuous(
    limits = c(min_x, max_val),
    labels = comma,
    breaks = pretty(c(min_x, max_val), n = 8)
  ) +
  scale_y_continuous(
    limits = c(0, max_val),
    labels = comma,
    breaks = pretty(c(0, max_val), n = 8)
  ) +
  labs(
    x = "Normalised Gap",
    y = "Number of builds"
  ) +
  theme_classic() +
  theme(
    axis.text.x  = element_text( size = 16, face = "bold"),
    axis.text.y  = element_text(size = 16, face = "bold"),
    axis.title.x = element_text(size = 16, face = "bold"),
    axis.title.y = element_text(size = 16, face = "bold"),
    plot.title   = element_text(size = 16, face = "bold", hjust = 0.5),
    plot.subtitle= element_text(size = 16, face = "plain", hjust = 0.5),
    legend.text  = element_text(size = 14),
    legend.title = element_text(size = 16)
  )

print(p1)



# Save plot 1
ggsave(
  filename = file.path(fig_dir, "builds_vs_normalized_gap.png"),
  plot     = p1,
  width    = 9, height = 7, dpi = 300
)
