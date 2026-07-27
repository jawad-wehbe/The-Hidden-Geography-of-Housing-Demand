library(ggspatial)
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
library(leaflet)
library(ncdf4)
library(stars)
library(ncmeta)
library(htmlwidgets)
library(lwgeom)
library(fixest)
library(broom)
library(stringr)

rm(list = ls())
gc()


###################
# Paths
###################

floods_england_path <- "/home/jawad/Desktop/Raw_Data/Shapefiles etc/Other/Floods/NRW_HISTORIC_FLOODMAP.gpkg"
  
floods_wales_path <- "/home/jawad/Desktop/Raw_Data/Shapefiles etc/Other/Floods/Recorded_Flood_Outlines.gpkg"

building_addressbook_path <- "/home/jawad/Desktop/Raw_Data/Shapefiles etc/OS/AddressBasePremium_FULL_2025-05-09_001.gpkg"

os_zoomstack_path <- "/home/jawad/Desktop/Raw_Data/Shapefiles etc/OS/OS_Open_Zoomstack.gpkg"

oa_path <- "/home/jawad/Desktop/Raw_Data/Shapefiles etc/output_areas_2021.gpkg"

ttwa_oa_path <- "/home/jawad/Desktop/Raw_Data/Shapefiles etc/Crosswalks/oa_ttwa.parquet"

fig_dir <-"~/Desktop/Projects/housing_targets/output/figures/nature/nonbots/saved_or_contacted/"


weekly_path <- "~/Desktop/Projects/housing_targets/produced/nature/nonbots/saved_or_contacted/oa_weekly_search_with_geos.parquet"


weekly_reg_dataset_path <- "~/Desktop/Projects/housing_targets/produced/nature/nonbots/saved_or_contacted/floods_weekly_reg_dataset.parquet"

results_path <- "~/Desktop/Projects/housing_targets/produced/nature/nonbots/saved_or_contacted/saved_or_contacted_results_floods_event_weekly.csv"

####################
# Read in the data
####################

# floods data
floods_england <- st_read(floods_england_path)

floods_wales <- st_read(floods_wales_path)

# combine floods

floods_ew <- bind_rows(floods_england %>% select(name, start_date, end_date),
                       floods_wales %>% select(name, start_date, end_date, geom = shape)) %>%
  filter(
    year(start_date) >= 2019,
    start_date < as.Date("2024-05-30")
  )

# public green space Great Britain (REMEMBER THIS HAS SCOTLAND IN IT AS WELL)
greenspace <- st_read(os_zoomstack_path, layer = "greenspace") %>%
  st_make_valid() %>%
  st_transform(27700)


# building address book (this will  be used to classify residential vs non residential buildings)

buildings_address_book <- st_read(building_addressbook_path, layer = "blpu")

# now read in the building classification table

building_classification <- st_read(building_addressbook_path, layer = "classification")

# output area
oa <- st_read(oa_path) %>%
  filter(grepl("^[EW]", oa_code)) %>%
  st_transform(27700)


# weekly searches

weekly_searches <- read_parquet(weekly_path) 

#############################################
# First step: specify residential buildings
############################################

# filter classifications to only residential (the classification scheme can be found on google)
residential_building_classification <- building_classification %>%
  filter(class_scheme == "AddressBase Premium Classification Scheme",
         str_starts(classification_code, "R")) 

# now keep buildings that are only residential
# AND REMOVE SCOTLAND 
# AND REMOVE RECORDS THAT WERE REMOVED AFTER 2019

residential_building <- buildings_address_book %>%
  semi_join(residential_building_classification, by = "uprn") %>%
  filter(country != "S", 
         (year(end_date) >= 2019 | is.na(end_date))) %>%
  st_transform(27700)


############################################
# Next, assign buildings to OA
#############################################

# Assign buildings to OA but keep only OAs that have a building
buildings_in_oa <- st_join (residential_building %>% select(uprn, blpu_state, addressbase_postal), oa, join = st_intersects, left = FALSE)

#########################################################
# Now intersect the residential buildings with the floods 
# to see how many buildings are affected in each OA
#########################################################

buildins_in_flood <- st_join (buildings_in_oa, floods_ew, join = st_intersects, left = FALSE)


# now get total number of buildings per OA

buildings_in_oa_summary <- buildings_in_oa %>%
  st_drop_geometry() %>%
  group_by (oa_code) %>%
  summarise(
    total_nb_buildings_oa = n_distinct(uprn),
    .groups = 'drop'
  )

# get buildings per OA affect by floods

buildings_floods_summary <- buildins_in_flood %>%
  st_drop_geometry() %>%
  group_by (oa_code) %>%
  summarise(
    flooded_nb_buildings_oa = n_distinct(uprn),
    .groups = 'drop'
  )

# combine both summaries and set those OAs without any flooded houses to 0

buildings_all_summary <- buildings_in_oa_summary %>%
  left_join(buildings_floods_summary, by = "oa_code") %>%
  mutate(flooded_nb_buildings_oa = replace_na(flooded_nb_buildings_oa, 0), 
         proportion_affected_homes = flooded_nb_buildings_oa / total_nb_buildings_oa) 


# plot distribution of proportion of affected houses within each OA
ggplot(buildings_all_summary %>% filter(proportion_affected_homes > 0),
       aes(x = proportion_affected_homes)) +
  geom_histogram(binwidth = 0.1, fill = "steelblue", color = "white") +
  labs(
    x = "Proportion of flooded buildings",
    y = "Number of Output Areas"
  ) +
  theme_classic()

# plot distribution of number of affected houses within each OA
ggplot(buildings_floods_summary,
       aes(x = flooded_nb_buildings_oa)) +
  geom_histogram(binwidth = 10, fill = "steelblue", color = "white") +
  labs(
    x = "Number of flooded buildings",
    y = "Number of Output Areas"
  ) +
  theme_classic()



#######################################################################
# Run event study with the ones that made national news in the top 20
#######################################################################

# 1- largest floods by area covered

floods_area <- floods_ew %>%
  mutate(
    flooded_area = as.numeric(st_area(geom))
  ) %>%
  st_drop_geometry() %>%
  group_by(name) %>%
  summarise(
    total_area = sum(flooded_area)
  ) %>%
  arrange(desc(total_area)) %>%
  slice(1:20)

# create treated OAs by those

flooded_oa_filtered <- buildins_in_flood %>%
  semi_join(floods_area, by = "name") %>%
  st_drop_geometry() %>%
  distinct(oa_code, name, start_date) %>%
  mutate(
    shock_year = isoyear(start_date),
    shock_week = isoweek(start_date)
  ) %>% 
  group_by(shock_year, shock_week) %>%
  mutate(
    shock_id = cur_group_id()
  ) %>%
  ungroup() %>%
  select(-name) #%>% # WATCH OUT, THIS IS WHERE YOU LOSE TRACK OF FLOODING SOURCES
  # filter(
  #   !shock_id %in% c(5) # this is will drop a river flooding that affected farmers
  # )



# create week index
weekly_searches <- weekly_searches %>%
  mutate(
    yw_index = year * 52 + week
  )

flooded_oa_filtered <- flooded_oa_filtered %>%
  mutate(
    shock_yw_index = shock_year * 52 + shock_week
  )


# create full treated data set
treated <- weekly_searches  %>%    # only rows for OAs in shock list
  filter(oa_code %in% flooded_oa_filtered$oa_code) %>%
  inner_join(flooded_oa_filtered, by = "oa_code") %>%  
  mutate(
    Group         = "Treat",      # label all these rows as “Treat”
    treated_today = if_else(       # mark 1 only on the actual shock week
      year  == shock_year & 
        week  == shock_week,
      1L, 0L
    )       
  ) 



# create the control for every shock
stack_list <- list()

shock_names <- unique(flooded_oa_filtered$shock_id)

for (i in shock_names) {
  
  ## TTWA(s) affected by this shock name
  ttwa_treated <- treated %>%
    filter(shock_id == i) %>%
    distinct(assigned_ttwa)
  
  ## treated rows for this shock
  treated_stack <- treated %>%
    filter(shock_id == i) %>%
    mutate(
      Group = "Treat",
      shock_id = i,
      rel_week = yw_index - shock_yw_index
    ) %>%
    filter(
      rel_week >= -24,
      rel_week <= 52
    )
  
  ## controls: same TTWA, never treated by any shock
  controls_stack <- weekly_searches %>%
    filter(
      assigned_ttwa %in% ttwa_treated$assigned_ttwa,
      !oa_code %in% flooded_oa_filtered$oa_code
    ) %>%
    mutate(
      Group = "Control",
      treated_today = 0L,
      shock_id = i,
      shock_yw_index = unique(treated_stack$shock_yw_index),
      rel_week = yw_index - shock_yw_index,
    ) %>%
    filter(
      rel_week >= -24,
      rel_week <= 52
    )
  
  ## combine treated + controls for this shock
  stack_list[[i]] <- bind_rows(treated_stack, controls_stack)
}

# combine everything together
stacked_data <- bind_rows(stack_list)


# Some states pre-treatment
stats <- stacked_data %>%
  filter(Group == "Treat", rel_week < 0, rel_week >= -24) %>%
  summarise(
    avg_searched = mean(buying_searches)
  )

###########################################################
# Some descriptive stats used to compare later with prices
###########################################################

# create the month variable
stacked_data_with_month <- stacked_data %>%
  mutate(
    week_start = as.Date(paste0(year, "-01-01")) + 7 * (week - 1),
    month = lubridate::month(week_start)
  )
    

# OA-Week
oa_weeks <- stacked_data_with_month %>%
  distinct(oa_code, year, week, shock_id) %>%
  nrow()

# OA-Month
oa_months <- stacked_data_with_month %>%
  distinct(oa_code, year, month, shock_id) %>%
  nrow()

# Oa-Year
oa_years <- stacked_data_with_month %>%
  distinct(oa_code, year, shock_id) %>%
  nrow()



# Now restrict to treated OAs and GET SAME STATS AS ABOVE
full_treatment_group <- stacked_data_with_month %>%
  filter(Group == "Treat")


# OA count
treated_oa <- full_treatment_group %>%
  distinct(oa_code, shock_id) %>%
  nrow()


# OA-Week
treated_oa_weeks <- full_treatment_group %>%
  distinct(oa_code, year, week, shock_id) %>%
  nrow()

# OA-Month
treated_oa_months <- full_treatment_group %>%
  distinct(oa_code, year, month, shock_id) %>%
  nrow()

# OA-Year
treated_oa_years <- full_treatment_group %>%
  distinct(oa_code, year, shock_id) %>%
  nrow()


######################################
# Add required columns for regression
#####################################


# create the columns
stacked_data <- stacked_data %>%
  mutate(
    treated_flag = as.integer(Group == "Treat"),
    
    treated_m24 = as.integer(rel_week == -24 & treated_flag == 1),
    treated_m23 = as.integer(rel_week == -23 & treated_flag == 1),
    treated_m22 = as.integer(rel_week == -22 & treated_flag == 1),
    treated_m21 = as.integer(rel_week == -21 & treated_flag == 1),
    treated_m20 = as.integer(rel_week == -20 & treated_flag == 1),
    treated_m19 = as.integer(rel_week == -19 & treated_flag == 1),
    treated_m18 = as.integer(rel_week == -18 & treated_flag == 1),
    treated_m17 = as.integer(rel_week == -17 & treated_flag == 1),
    treated_m16 = as.integer(rel_week == -16 & treated_flag == 1),
    treated_m15 = as.integer(rel_week == -15 & treated_flag == 1),
    treated_m14 = as.integer(rel_week == -14 & treated_flag == 1),
    treated_m13 = as.integer(rel_week == -13 & treated_flag == 1),
    treated_m12 = as.integer(rel_week == -12 & treated_flag == 1),
    treated_m11 = as.integer(rel_week == -11 & treated_flag == 1),
    treated_m10 = as.integer(rel_week == -10 & treated_flag == 1),
    treated_m9  = as.integer(rel_week ==  -9 & treated_flag == 1),
    treated_m8  = as.integer(rel_week ==  -8 & treated_flag == 1),
    treated_m7  = as.integer(rel_week ==  -7 & treated_flag == 1),
    treated_m6  = as.integer(rel_week ==  -6 & treated_flag == 1),
    treated_m5  = as.integer(rel_week ==  -5 & treated_flag == 1),
    treated_m4  = as.integer(rel_week ==  -4 & treated_flag == 1),
    treated_m3  = as.integer(rel_week ==  -3 & treated_flag == 1),
    treated_m2  = as.integer(rel_week ==  -2 & treated_flag == 1),
    
    treated_0   = as.integer(rel_week ==   0 & treated_flag == 1),
    
    treated_1   = as.integer(rel_week ==   1 & treated_flag == 1),
    treated_2   = as.integer(rel_week ==   2 & treated_flag == 1),
    treated_3   = as.integer(rel_week ==   3 & treated_flag == 1),
    treated_4   = as.integer(rel_week ==   4 & treated_flag == 1),
    treated_5   = as.integer(rel_week ==   5 & treated_flag == 1),
    treated_6   = as.integer(rel_week ==   6 & treated_flag == 1),
    treated_7   = as.integer(rel_week ==   7 & treated_flag == 1),
    treated_8   = as.integer(rel_week ==   8 & treated_flag == 1),
    treated_9   = as.integer(rel_week ==   9 & treated_flag == 1),
    treated_10  = as.integer(rel_week ==  10 & treated_flag == 1),
    treated_11  = as.integer(rel_week ==  11 & treated_flag == 1),
    treated_12  = as.integer(rel_week ==  12 & treated_flag == 1),
    treated_13  = as.integer(rel_week ==  13 & treated_flag == 1),
    treated_14  = as.integer(rel_week ==  14 & treated_flag == 1),
    treated_15  = as.integer(rel_week ==  15 & treated_flag == 1),
    treated_16  = as.integer(rel_week ==  16 & treated_flag == 1),
    treated_17  = as.integer(rel_week ==  17 & treated_flag == 1),
    treated_18  = as.integer(rel_week ==  18 & treated_flag == 1),
    treated_19  = as.integer(rel_week ==  19 & treated_flag == 1),
    treated_20  = as.integer(rel_week ==  20 & treated_flag == 1),
    treated_21  = as.integer(rel_week ==  21 & treated_flag == 1),
    treated_22  = as.integer(rel_week ==  22 & treated_flag == 1),
    treated_23  = as.integer(rel_week ==  23 & treated_flag == 1),
    treated_24  = as.integer(rel_week ==  24 & treated_flag == 1),
    treated_25  = as.integer(rel_week ==  25 & treated_flag == 1),
    treated_26  = as.integer(rel_week ==  26 & treated_flag == 1),
    treated_27  = as.integer(rel_week ==  27 & treated_flag == 1),
    treated_28  = as.integer(rel_week ==  28 & treated_flag == 1),
    treated_29  = as.integer(rel_week ==  29 & treated_flag == 1),
    treated_30  = as.integer(rel_week ==  30 & treated_flag == 1),
    treated_31  = as.integer(rel_week ==  31 & treated_flag == 1),
    treated_32  = as.integer(rel_week ==  32 & treated_flag == 1),
    treated_33  = as.integer(rel_week ==  33 & treated_flag == 1),
    treated_34  = as.integer(rel_week ==  34 & treated_flag == 1),
    treated_35  = as.integer(rel_week ==  35 & treated_flag == 1),
    treated_36  = as.integer(rel_week ==  36 & treated_flag == 1),
    treated_37  = as.integer(rel_week ==  37 & treated_flag == 1),
    treated_38  = as.integer(rel_week ==  38 & treated_flag == 1),
    treated_39  = as.integer(rel_week ==  39 & treated_flag == 1),
    treated_40  = as.integer(rel_week ==  40 & treated_flag == 1),
    treated_41  = as.integer(rel_week ==  41 & treated_flag == 1),
    treated_42  = as.integer(rel_week ==  42 & treated_flag == 1),
    treated_43  = as.integer(rel_week ==  43 & treated_flag == 1),
    treated_44  = as.integer(rel_week ==  44 & treated_flag == 1),
    treated_45  = as.integer(rel_week ==  45 & treated_flag == 1),
    treated_46  = as.integer(rel_week ==  46 & treated_flag == 1),
    treated_47  = as.integer(rel_week ==  47 & treated_flag == 1),
    treated_48  = as.integer(rel_week ==  48 & treated_flag == 1),
    treated_49  = as.integer(rel_week ==  49 & treated_flag == 1),
    treated_50  = as.integer(rel_week ==  50 & treated_flag == 1),
    treated_51  = as.integer(rel_week ==  51 & treated_flag == 1),
    treated_52  = as.integer(rel_week ==  52 & treated_flag == 1)
  ) %>% 
  select(-treated_today, - treated_flag)

# add some FE

stacked_data <- stacked_data %>%
  mutate(
    ln_buying_searches  = log(buying_searches),
    ln_letting_searches = log(letting_searches),
    ttwa_yw_id = paste0(assigned_ttwa, "_", year, "_", week),
    oa_stack_id = paste0(oa_code, "_", shock_id)
  )

# save it

write_parquet(stacked_data, weekly_reg_dataset_path)

#######################################
# Run regression
#######################################

# read it back in

stacked_data <- read_parquet(weekly_reg_dataset_path)

# Dummy names
treat_vars <- stacked_data %>% dplyr::select(starts_with("treated_")) %>% names()

# Formulas for each outcome
fml_buying  <- as.formula(paste0("ln_buying_searches ~ ", paste(treat_vars, collapse = " + "), " | ttwa_yw_id + oa_stack_id"))

# Run Regressions 
buying_res  <- feols(fml_buying,  data = stacked_data, cluster = ~oa_stack_id)

# tidy results
buying_tidy <- tidy(buying_res) %>%
  dplyr::filter(str_detect(term, "^treated_")) %>%
  dplyr::select(term, estimate, std.error)


# clean up names
buying_tidy <- buying_tidy %>%
  dplyr::mutate(
    # Remove 'Treated_' 
    term_clean = str_remove_all(term, "treated_"),
    # If it starts with 'm', make it negative
    rel_week = case_when(
      str_detect(term_clean, "^m") ~ -as.integer(str_remove(term_clean, "^m")),
      TRUE ~ as.integer(term_clean)
    ),
    se = std.error,
    search_type = "buying"
  ) %>%
  dplyr::select(rel_week, estimate, se, search_type) %>%
  arrange(rel_week)



# Calculate CI columns 
results <- buying_tidy %>%
  dplyr::mutate(
    estimate = estimate * 100,
    se = se * 100,
    lower = estimate - 1.96 * se,
    upper = estimate + 1.96 * se
  )

# save results

write_csv(results,  results_path)


# Create a reference row for week -5
ref_row <- tibble(
  rel_week = -1,
  estimate = 0,
  se = 0,
  lower = 0,
  upper = 0,
  search_type = "buying"
)



# Bind the new row to your existing results
results <- bind_rows(results, ref_row)

# Plot Buying
buying_plot <- ggplot(
  results,
  aes(x = rel_week, y = estimate)
) +
  geom_ribbon(aes(ymin = lower, ymax = upper), fill = "#6BAED6", alpha = 0.4) +
  geom_line(color = "#08306B", size = 1.2) +
  geom_vline(xintercept = 0, linetype = "dashed", color = "black", size = 1) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "black", size = 1) +
  labs(
    x = "Weeks",
    y = "% change in searches"
  ) +
  scale_x_continuous(
    breaks = sort(unique(c(seq(-24, 52, by = 8))))
  ) +
  scale_y_continuous(
    n.breaks = 8
  ) +
  theme_classic() +
  theme(
    plot.title   = element_text(face = "bold", size = 21, hjust = 0.5),
    axis.title.x = element_text(face = "bold", size = 30),
    axis.title.y = element_text(face = "bold", size = 30),
    axis.text.x  = element_text(face = "bold", size = 34),
    axis.text.y  = element_text(face = "bold", size = 34),
    axis.line    = element_line(size = 1.3, color = "black"),
    axis.ticks   = element_line(size = 1.3, color = "black"),
    panel.grid   = element_blank()
  )

print(buying_plot)

# Save plot
ggsave(
  filename = file.path(fig_dir, "nonbots_saved_or_contacted_event_study_buying_searches.png"),
  plot = buying_plot,
  width = 18, 
  height = 7, 
  units = "in",
  dpi = 300
)



# find overall mean of searches to use in text
pre_period_mean <- stacked_data %>%
  filter(Group == "Treat" & rel_week < 0) %>%
  summarise(
    mean_pre_searches = mean(buying_searches, na.rm = TRUE)
  )







