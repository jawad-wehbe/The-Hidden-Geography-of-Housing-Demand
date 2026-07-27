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
library(fixest)
library(broom)
library(stringr)
library(penppml)
library(ISOweek)


rm(list = ls())
gc()


# =========================================================
# OVERVIEW
# =========================================================
# Identifies which buildings are residential and assigns them to OAs.
# Identifies OAs exposed to major floods, keeping the 20 largest flood events and grouping floods into shock periods by year-week.
# Geocodes property transactions from postcodes, converts them to spatial points, and assigns each transaction to an OA.
# Aggregates transactions to weekly and monthly OA panels.
# Builds treated and control groups for an event-study design, where:
#    - Treated OAs are flood-exposed OAs.
#    - Control OAs are non-flooded OAs in the same TTWA(s).
# Estimates flood impacts using:
#    - Weekly PPML regressions on transaction counts.
#    - Monthly fixed-effects regressions on log average sale prices.
#

###################
# Paths
###################

floods_england_path <- "/home/jawad/Desktop/Raw_Data/Shapefiles etc/Other/Floods/NRW_HISTORIC_FLOODMAP.gpkg"

floods_wales_path <- "/home/jawad/Desktop/Raw_Data/Shapefiles etc/Other/Floods/Recorded_Flood_Outlines.gpkg"

oa_path <- "/home/jawad/Desktop/Raw_Data/Shapefiles etc/output_areas_2021.gpkg"

output_path <- "/home/jawad/Desktop/Projects/housing_targets/produced/nature/"

ttwa_oa_path <- "/home/jawad/Desktop/Raw_Data/Shapefiles etc/Crosswalks/oa_ttwa.parquet"

fig_dir <-"/home/jawad/Desktop/Projects/housing_targets/output/figures/nature/nonbots/"

transactions_path <- "/home/jawad/Desktop/Raw_Data/HMLR/pp-complete.csv"


building_addressbook_path <- "/home/jawad/Desktop/Raw_Data/Shapefiles etc/OS/AddressBasePremium_FULL_2025-05-09_001.gpkg"


postcode_to_coord_path <- "/home/jawad/Desktop/Raw_Data/Shapefiles etc/ONSPD_FEB_2025/Data/ONSPD_FEB_2025_UK.csv"

cw_dir <- "~/Desktop/Raw_Data/Shapefiles etc/Crosswalks/"

weekly_path <- "~/Desktop/Projects/housing_targets/produced/nature/nonbots/all/oa_weekly_search_with_geos.parquet"

# Outputs
reg_dataset_weekly_path <-   "~/Desktop/Projects/housing_targets/produced/nature/nonbots/regression_datasets/floods_weekly_reg_dataset_complete.parquet"

reg_dataset_monthly_path <- "~/Desktop/Projects/housing_targets/produced/nature/nonbots/regression_datasets/floods_monthly_reg_dataset_complete.parquet"

results_dir <- "/home/jawad/Desktop/Projects/housing_targets/produced/nature/nonbots/regression_results/"

###################
# Read the data
###################

# weekly searches
weekly_searches <- read_parquet(weekly_path)

# READ THE TTWA CROSSWALK AND ASSIGN TO OA
cw_oa_ttwa <- read_parquet(file.path(cw_dir, "oa_ttwa.parquet"))

# assign each OA 1 TTWA
oa_to_ttwa <- cw_oa_ttwa %>%
  group_by(oa_code) %>%
  slice_max(share, n = 1, with_ties = FALSE) %>%
  ungroup() %>%
  select(oa_code, assigned_ttwa = ttwa_code)  

# output area
oa <- st_read(oa_path) %>%
  filter(grepl("^[EW]", oa_code)) %>%
  st_transform(27700)


############################
# READ IN MAIN data
###########################

# building address book (this will  be used to classify residential vs non residential buildings)

buildings_address_book <- st_read(building_addressbook_path, layer = "blpu")

# now read in the building classification table

building_classification <- st_read(building_addressbook_path, layer = "classification")

# floods data
floods_england <- st_read(floods_england_path)

floods_wales <- st_read(floods_wales_path)

# combine floods

floods_ew <- bind_rows(floods_england %>% select(name, start_date, end_date),
                       floods_wales %>% select(name, start_date, end_date, geom = shape)) %>%
  filter(
    year(start_date) >= 2019,
    start_date < as.Date("2024-05-30")
  ) %>%
  mutate(
    flood_year = year(start_date),
    flood_month = month(start_date),
    flood_week = isoweek(start_date)
  )



# standardize the transactions
transaction <- read_csv(transactions_path, col_names = FALSE) %>%
  rename(id =  X1, price = X2, date = X3, postcode = X4 ) %>%
  select(id, price, date, postcode) %>%
  mutate(postcode_key = str_to_upper(str_remove_all(postcode, "\\s+")))

# standardize the look up
postcode_lookup <- read_csv(postcode_to_coord_path) %>%
  select(pcd, pcd2, pcds, lat, long) %>%
  filter(!is.na(lat) & !is.na(long)) %>%
  mutate(postcode_key = str_to_upper(str_remove_all(pcds, "\\s+")))

# join them
test_with_coords <- transaction %>%
  left_join(postcode_lookup, by = "postcode_key") %>%
  filter(!is.na(pcds))

# make it spatial object
transactions_sf <- test_with_coords %>%
  st_as_sf(coords = c("long", "lat"), crs = 4326) %>%
  st_transform(27700) %>%
  mutate(
    selling_month = month(date),
    selling_week = isoweek(date),
    selling_year = isoyear(date)
    
  )

# add count of trasnaction id to ensure no duplicates
transactions_sf <- transactions_sf %>%
  add_count(id, name = "count")

# filter to transactions in our period
transactions_sf_filtered <- transactions_sf %>%
  filter(date >= as.Date("2019-01-01"), 
         date < as.Date("2024-05-01"))


#############################################
# Now we specify residential buildings
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
############################################

# Assign buildings to OA but keep only OAs that have a building
buildings_in_oa <- st_join (residential_building %>% select(uprn, blpu_state, addressbase_postal), oa, join = st_intersects, left = FALSE)

##############################
# Filter to 20 largest floods
##############################

# largest floods by area covered
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


#########################################################
# Now intersect the residential OAs with the floods 
#########################################################

residential_oa_floods <- st_join (buildings_in_oa, floods_ew, join = st_intersects, left = FALSE) 


# now group shocks within the same year-week
flooded_oa_filtered <- residential_oa_floods %>%
  semi_join(floods_area, by = "name") %>% # filter to top 20 floods
  st_drop_geometry() %>%
  distinct(oa_code, name, start_date) %>% # make sure no duplicated floods 
  mutate(
    shock_year = isoyear(start_date),
    shock_week = isoweek(start_date)
  ) %>% 
  group_by(shock_year, shock_week) %>% # group to same year-week
  mutate(
    shock_id = cur_group_id()
  ) %>%
  ungroup()  %>%
  select(-name) %>%
  distinct(oa_code, shock_id, shock_year, shock_week)#%>% # WATCH OUT, THIS IS WHERE YOU LOSE TRACK OF FLOODING SOURCES
# filter(
#   !shock_id %in% c(5) # this is will drop a river flooding that affected farmers
# )



#################################################
# Now assign ALL transactions POST 2019 to OAs
#################################################

transactions_oa <- st_join(oa, transactions_sf_filtered, join = st_intersects ,left = FALSE)


# group transactions at the OA level to the week-year level INITIALY AND THEN WE AGGREGATE
transactions_oa_weekly_summary<- transactions_oa %>%
  st_drop_geometry() %>%
  group_by(oa_code, selling_year, selling_week) %>%
  summarise(
    average_selling_price_weekly = mean(price, na.rm = TRUE),
    had_transaction = as.integer(any(price > 0)),
    n_transactions = n_distinct(id[price > 0]),
    .groups = 'drop'
  )


# create the weekly variable (we need to assign it this way other january 1 2019 would be the last week of 2018)
transactions_oa_weekly_summary <- transactions_oa_weekly_summary %>%
  mutate(
    week_date = ISOweek::ISOweek2date(
      sprintf("%d-W%02d-4", selling_year, selling_week)
    )
  )

# find the global variables
global_min_week <- min(transactions_oa_weekly_summary$week_date, na.rm = TRUE)
global_max_week <- max(transactions_oa_weekly_summary$week_date, na.rm = TRUE)


# fill in missing weeks
transactions_oa_weekly_full <- transactions_oa_weekly_summary %>%
  mutate(
    week_date = ISOweek2date(
      sprintf("%d-W%02d-4", selling_year, selling_week)
    )) %>%
  group_by(oa_code) %>%
  complete(
    week_date = seq.Date(
      from = global_min_week,
      to   =  global_max_week,
      by   = "1 week"
    ),
    fill = list(average_selling_price_weekly = 0,
                had_transaction = 0,
                n_transactions = 0)
  ) %>%
  ungroup() 

# extract again the year, week, and month after filling in the 0s
transactions_oa_weekly_full <- transactions_oa_weekly_full %>%
  mutate(
    selling_year = isoyear(week_date),
    selling_week = isoweek(week_date),
    selling_month = month(week_date)
  )


# ASSIGN TTWA
transactions_oa_weekly_full <- transactions_oa_weekly_full %>%
  inner_join(oa_to_ttwa, by = "oa_code")


# create week index
time_lookup <- bind_rows(
  transactions_oa_weekly_full %>%
    distinct(year = selling_year, week = selling_week),
  weekly_searches %>%
    distinct(year = year, week = week),          
  flooded_oa_filtered %>%
    distinct(year = shock_year, week = shock_week)
) %>%
  distinct(year, week) %>%
  arrange(year, week) %>%
  mutate(time_id = row_number())

# attach it to the datasets
transactions_oa_weekly_full <- transactions_oa_weekly_full %>%
  left_join(
    time_lookup %>%
      rename(
        selling_year = year,
        selling_week = week,
        selling_time_id = time_id
      ),
    by = c("selling_year", "selling_week")
  )

flooded_oa_filtered <- flooded_oa_filtered %>%
  left_join(
    time_lookup %>%
      rename(
        shock_year = year,
        shock_week = week,
        shock_time_id = time_id
      ),
    by = c("shock_year", "shock_week")
  )

#################################################################################################################
# Create the full treatment and control data set (Our main set is OAs where at least 1 transaction has happened)
##################################################################################################################


# create full treated data set
treated <- transactions_oa_weekly_full %>%
  inner_join(flooded_oa_filtered, by = "oa_code") %>%
  mutate(
    Group = "Treat",
    treated_today = if_else(
      selling_year == shock_year &
        selling_week == shock_week,
      1L, 0L
    )
  )



# create the control for every shock
stack_list <- list()

shock_names <- unique(flooded_oa_filtered$shock_id)

for (i in shock_names) {
  
  ttwa_treated <- treated %>%
    filter(shock_id == i) %>%
    distinct(assigned_ttwa)
  
  shock_time_i <- flooded_oa_filtered %>%
    filter(shock_id == i) %>%
    distinct(shock_time_id) %>%
    pull(shock_time_id)
  
  treated_stack <- treated %>%
    filter(shock_id == i) %>%
    mutate(
      Group = "Treat",
      rel_week = selling_time_id - shock_time_id
    ) %>%
    filter(rel_week >= -24, rel_week <= 52)
  
  controls_stack <- transactions_oa_weekly_full %>%
    filter(
      assigned_ttwa %in% ttwa_treated$assigned_ttwa,
      !oa_code %in% flooded_oa_filtered$oa_code
    ) %>%
    mutate(
      Group = "Control",
      treated_today = 0L,
      shock_id = i,
      shock_time_id = shock_time_i,
      rel_week = selling_time_id - shock_time_id
    ) %>%
    filter(rel_week >= -24, rel_week <=52)
  
  stack_list[[as.character(i)]] <- bind_rows(treated_stack, controls_stack)
}

stacked_data <- bind_rows(stack_list)


# attach searches to the stacked transactions panel
stacked_data <- stacked_data %>%
  left_join(
    weekly_searches %>% select(oa_code, year, week, buying_searches),
    by = c("oa_code", "selling_year" = "year", "selling_week" = "week")
  )


# find overall mean of transactions to use in text
pre_period_mean <- stacked_data %>%
  filter(Group == "Treat" & rel_week < 0) %>%
  summarise(
    mean_pre_transactions = mean(n_transactions, na.rm = TRUE),
    mean_searches = mean(buying_searches, na.rm = TRUE)
  )

################################################################
# Regression — ALL OUTCOMES IN ONE LOOP
################################################################

# transformed outcomes and FE ids
stacked_data <- stacked_data %>%
  mutate(
    asinh_n        = asinh(n_transactions),
    rad_n          = sqrt(n_transactions),
    asinh_price    = asinh(average_selling_price_weekly),
    rad_price      = sqrt(average_selling_price_weekly),
    asinh_searches = asinh(buying_searches),
    rad_searches   = sqrt(buying_searches),
    log_searches   = log(buying_searches),                 
    treat          = as.integer(Group == "Treat"),
    ttwa_year_week = paste(assigned_ttwa, selling_year, selling_week, sep = "_"),
    oa_shockid     = paste(oa_code, shock_id, sep = "_")
  )


# save regression dataset
write_parquet(stacked_data, reg_dataset_weekly_path)

stacked_data <- read_parquet(reg_dataset_weekly_path)

# specs: outcome column, base var (for ybar + filtering), transform, drop zeros, labels
specs <- tribble(
  ~name,           ~outcome,          ~base,                           ~tr,    ~drop_zero, ~ylab,                        ~fileprefix,
  "trans_ihs",     "asinh_n",         "n_transactions",                "ihs",  FALSE,      "% change in\n transactions",   "transactions_weekly_",
  #"trans_sqrt",    "rad_n",           "n_transactions",                "sqrt", FALSE,      "% change in transactions",   "transactions_weekly_",
  #"price_ihs",     "asinh_price",     "average_selling_price_weekly",  "ihs",  TRUE,       "% change in price",          "prices_weekly_",
  #"price_sqrt",    "rad_price",       "average_selling_price_weekly",  "sqrt", TRUE,       "% change in price",          "prices_weekly_",
  #"search_ihs",    "asinh_searches",  "buying_searches",               "ihs",  FALSE,      "% change in searches",       "searches_weekly_",
  #"search_sqrt",   "rad_searches",    "buying_searches",               "sqrt", FALSE,      "% change in searches",       "searches_weekly_",
  "search_log",    "log_searches",    "buying_searches",               "log",  TRUE,       "% change in\n searches",       "searches_weekly_"
)


# setFE threads
setFixest_nthreads(15) 

for (r in seq_len(nrow(specs))) {
  
  # pull this spec's settings
  nm     <- specs$name[r]
  y_var  <- specs$outcome[r]
  base   <- specs$base[r]
  dz     <- specs$drop_zero[r]
  ylab   <- specs$ylab[r]
  fpref  <- specs$fileprefix[r]
  
  # regression sample: drop NAs on the base var, and zeros where required
  n_start <- nrow(stacked_data)
  dat <- stacked_data %>% filter(!is.na(.data[[base]]))
  n_after_na <- nrow(dat)
  if (dz) dat <- dat %>% filter(.data[[base]] > 0)
  n_after_zero <- nrow(dat)
  
  # report drops for this spec
  message(sprintf(
    "%-12s | start %d | NA dropped %d | zero dropped %d | final %d (%.1f%% kept)",
    nm,
    n_start,
    n_start - n_after_na,
    n_after_na - n_after_zero,
    n_after_zero,
    100 * n_after_zero / n_start
  ))
  
  # multiplier at this sample's untransformed mean
  ybar <- mean(dat[[base]], na.rm = TRUE)
  
  # choose which transformation and switch based on the loop
  mult <- switch(specs$tr[r],
                 log  = 1,                          # log outcome: already a semi-elasticity
                 ihs  = sqrt(ybar^2 + 1) / ybar,
                 sqrt = 1 / (0.5 * ybar^0.5))
  
  # build event-study formula
  fml <- as.formula(paste0(
    y_var, " ~ i(rel_week, treat, ref = -1) | oa_shockid + ttwa_year_week"
  ))
  
  # run the regression
  es <- feols(fml, data = dat, cluster = ~ oa_shockid)
  
  # tidy and rescale to percent
  event_df_clean <- tidy(es) %>%
    filter(str_detect(term, "rel_week::")) %>%
    mutate(
      rel_week  = as.integer(str_extract(term, "(?<=rel_week::)-?\\d+")),
      estimate  = estimate * mult * 100,
      beta_low  = estimate - 1.96 * (std.error * mult * 100),
      beta_high = estimate + 1.96 * (std.error * mult * 100)
    ) %>%
    select(rel_week, estimate, beta_low, beta_high) %>%
    arrange(rel_week)
  
  
  # SAVE weekly results (
  write_csv(
    event_df_clean,
    file.path(results_dir, paste0(fpref, specs$tr[r], "_flood_ttwaxyw_oa_fe.csv"))
  )
  
  # add omitted reference week
  ref_row <- tibble(rel_week = -1, estimate = 0, beta_low = 0, beta_high = 0)
  results <- bind_rows(event_df_clean, ref_row) %>% arrange(rel_week)
  
  # build the event-study plot
  p <- ggplot(results, aes(x = rel_week, y = estimate)) +
    geom_ribbon(aes(ymin = beta_low, ymax = beta_high), fill = "#6BAED6", alpha = 0.4) +
    geom_line(color = "#08306B", size = 1.2) +
    geom_vline(xintercept = 0, linetype = "dashed", color = "black", size = 1) +
    geom_hline(yintercept = 0, linetype = "dashed", color = "black", size = 1) +
    labs(x = "Weeks", y = ylab) +
    scale_x_continuous(breaks = seq(-24, 52, by = 8)) +
    scale_y_continuous(n.breaks = 8) +
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
  
  print(p)
  
  # save this spec's figure
  ggsave(
    filename = file.path(fig_dir, paste0(fpref, specs$tr[r], "_flood_ttwaxyw_oa_fe.png")),
    plot = p, width = 18, height = 7, units = "in", dpi = 300
  )
  
  # free the fit and sample
  rm(es, dat); gc()
}




################################################################
################################################################
# MONTHLY VERSION
################################################################
################################################################

# group shocks within the same year-month
flooded_oa_filtered_monthly <- residential_oa_floods %>%
  semi_join(floods_area, by = "name") %>% # filter to top 20 floods
  st_drop_geometry() %>%
  distinct(oa_code, name, start_date) %>% # make sure no duplicated floods
  mutate(
    shock_year  = year(start_date),
    shock_month = month(start_date)
  ) %>%
  group_by(shock_year, shock_month) %>% # group to same year-month
  mutate(
    shock_id = cur_group_id()
  ) %>%
  ungroup() %>%
  select(-name) %>%
  distinct(oa_code, shock_id, shock_year, shock_month)


# group transactions at the OA level to the month-year level
transactions_oa_monthly_summary <- transactions_oa %>%
  st_drop_geometry() %>%
  mutate( 
    selling_year = isoyear(date), 
    selling_month = lubridate::month(date)) %>%
  group_by(oa_code, selling_year , selling_month) %>%
  summarise(
    average_selling_price_monthly = mean(price, na.rm = TRUE),
    had_transaction = as.integer(any(price > 0)),
    n_transactions = n_distinct(id[price > 0]),
    .groups = 'drop'
  )

# create the monthly date variable
transactions_oa_monthly_summary <- transactions_oa_monthly_summary %>%
  mutate(
    month_date = as.Date(sprintf("%d-%02d-01", selling_year, selling_month))
  )

# find the global variables
global_min_month <- min(transactions_oa_monthly_summary$month_date, na.rm = TRUE)
global_max_month <- max(transactions_oa_monthly_summary$month_date, na.rm = TRUE)

# fill in missing months
transactions_oa_monthly_full <- transactions_oa_monthly_summary %>%
  group_by(oa_code) %>%
  complete(
    month_date = seq.Date(
      from = global_min_month,
      to   = global_max_month,
      by   = "1 month"
    ),
    fill = list(average_selling_price_monthly = 0,
                had_transaction = 0,
                n_transactions = 0)
  ) %>%
  ungroup()

# extract again the year and month after filling in the 0s
transactions_oa_monthly_full <- transactions_oa_monthly_full %>%
  mutate(
    selling_year  = year(month_date),
    selling_month = month(month_date)
  )

# ASSIGN TTWA
transactions_oa_monthly_full <- transactions_oa_monthly_full %>%
  inner_join(oa_to_ttwa, by = "oa_code")


# aggregate searches to OA-month (month from the ISO week's Thursday)
monthly_searches <- weekly_searches %>%
  mutate(
    week_thursday = ISOweek2date(sprintf("%d-W%02d-4", year, week)),
    month = month(week_thursday),
    year  = year(week_thursday)
  ) %>%
  group_by(oa_code, year, month) %>%
  summarise(
    buying_searches = sum(buying_searches, na.rm = TRUE),
    .groups = "drop"
  )


# create month index
time_lookup_monthly <- bind_rows(
  transactions_oa_monthly_full %>%
    distinct(year = selling_year, month = selling_month),
  monthly_searches %>%
    distinct(year = year, month = month),
  flooded_oa_filtered_monthly %>%
    distinct(year = shock_year, month = shock_month)
) %>%
  distinct(year, month) %>%
  arrange(year, month) %>%
  mutate(time_id = row_number())

# attach it to the data sets
transactions_oa_monthly_full <- transactions_oa_monthly_full %>%
  left_join(
    time_lookup_monthly %>%
      rename(
        selling_year = year,
        selling_month = month,
        selling_time_id = time_id
      ),
    by = c("selling_year", "selling_month")
  )

flooded_oa_filtered_monthly <- flooded_oa_filtered_monthly %>%
  left_join(
    time_lookup_monthly %>%
      rename(
        shock_year = year,
        shock_month = month,
        shock_time_id = time_id
      ),
    by = c("shock_year", "shock_month")
  )


# create full treated data set
treated_monthly <- transactions_oa_monthly_full %>%
  inner_join(flooded_oa_filtered_monthly, by = "oa_code") %>%
  mutate(
    Group = "Treat",
    treated_today = if_else(
      selling_year == shock_year &
        selling_month == shock_month,
      1L, 0L
    )
  )


# create the control for every shock
stack_list_monthly <- list()

shock_names_monthly <- unique(flooded_oa_filtered_monthly$shock_id)

for (i in shock_names_monthly) {
  
  ttwa_treated <- treated_monthly %>%
    filter(shock_id == i) %>%
    distinct(assigned_ttwa)
  
  shock_time_i <- flooded_oa_filtered_monthly %>%
    filter(shock_id == i) %>%
    distinct(shock_time_id) %>%
    pull(shock_time_id)
  
  treated_stack <- treated_monthly %>%
    filter(shock_id == i) %>%
    mutate(
      Group = "Treat",
      rel_month = selling_time_id - shock_time_id
    ) %>%
    filter(rel_month >= -6, rel_month <= 12)
  
  controls_stack <- transactions_oa_monthly_full %>%
    filter(
      assigned_ttwa %in% ttwa_treated$assigned_ttwa,
      !oa_code %in% flooded_oa_filtered_monthly$oa_code
    ) %>%
    mutate(
      Group = "Control",
      treated_today = 0L,
      shock_id = i,
      shock_time_id = shock_time_i,
      rel_month = selling_time_id - shock_time_id
    ) %>%
    filter(rel_month >= -6, rel_month <= 12)
  
  stack_list_monthly[[as.character(i)]] <- bind_rows(treated_stack, controls_stack)
}

stacked_data_monthly <- bind_rows(stack_list_monthly)


# attach searches to the stacked monthly panel
stacked_data_monthly <- stacked_data_monthly %>%
  left_join(
    monthly_searches %>% select(oa_code, year, month, buying_searches),
    by = c("oa_code", "selling_year" = "year", "selling_month" = "month")
  )


################################################################
# Regression — ALL OUTCOMES IN ONE LOOP (MONTHLY)
################################################################

# transformed outcomes and FE ids
stacked_data_monthly <- stacked_data_monthly %>%
  mutate(
    asinh_n         = asinh(n_transactions),
    rad_n           = sqrt(n_transactions),
    asinh_price     = asinh(average_selling_price_monthly),
    rad_price       = sqrt(average_selling_price_monthly),
    log_price       = log(average_selling_price_monthly),
    asinh_searches  = asinh(buying_searches),
    rad_searches    = sqrt(buying_searches),
    log_searches    = log(buying_searches),
    treat           = as.integer(Group == "Treat"),
    ttwa_year_month = paste(assigned_ttwa, selling_year, selling_month, sep = "_"),
    oa_shockid      = paste(oa_code, shock_id, sep = "_")
  )


# save regression dataset
write_parquet(stacked_data_monthly, reg_dataset_monthly_path)

# read it in 

stacked_data_monthly <- read_parquet(reg_dataset_monthly_path)


# specs: outcome column, base var (for ybar + filtering), transform, drop zeros, labels
specs_monthly <- tribble(
  ~name,           ~outcome,          ~base,                            ~tr,    ~drop_zero, ~ylab,                        ~fileprefix,
  "trans_ihs",     "asinh_n",         "n_transactions",                 "ihs",  FALSE,      "% change in\n transactions",   "transactions_monthly_",
  #"trans_sqrt",    "rad_n",           "n_transactions",                 "sqrt", FALSE,      "% change in transactions",   "transactions_monthly_",
  #"price_ihs",     "asinh_price",     "average_selling_price_monthly",  "ihs",  TRUE,       "% change in price",          "prices_monthly_",
  #"price_sqrt",    "rad_price",       "average_selling_price_monthly",  "sqrt", TRUE,       "% change in price",          "prices_monthly_",
  "price_log",    "log_price",       "average_selling_price_monthly",   "log",  TRUE,       "% change in\n price",          "prices_monthly_",
  #"search_ihs",    "asinh_searches",  "buying_searches",                "ihs",  FALSE,      "% change in searches",       "searches_monthly_",
  #"search_sqrt",   "rad_searches",    "buying_searches",                "sqrt", FALSE,      "% change in searches",       "searches_monthly_",
  "search_log",    "log_searches",    "buying_searches",                "log",  TRUE,       "% change in\n searches",       "searches_monthly_"
)

for (r in seq_len(nrow(specs_monthly))) {
  
  # pull this spec's settings
  nm     <- specs_monthly$name[r]
  y_var  <- specs_monthly$outcome[r]
  base   <- specs_monthly$base[r]
  dz     <- specs_monthly$drop_zero[r]
  ylab   <- specs_monthly$ylab[r]
  fpref  <- specs_monthly$fileprefix[r]
  
  # regression sample: drop NAs on the base var, and zeros where required
  n_start <- nrow(stacked_data_monthly)
  dat <- stacked_data_monthly %>% filter(!is.na(.data[[base]]))
  n_after_na <- nrow(dat)
  if (dz) dat <- dat %>% filter(.data[[base]] > 0)
  n_after_zero <- nrow(dat)
  
  # report drops for this spec
  message(sprintf(
    "%-12s | start %d | NA dropped %d | zero dropped %d | final %d (%.1f%% kept)",
    nm, n_start, n_start - n_after_na, n_after_na - n_after_zero,
    n_after_zero, 100 * n_after_zero / n_start
  ))
  
  # multiplier at this sample's untransformed mean
  ybar <- mean(dat[[base]], na.rm = TRUE)
  
  # choose which transformation and switch based on the loop
  mult <- switch(specs_monthly$tr[r],
                 log  = 1,
                 ihs  = sqrt(ybar^2 + 1) / ybar,
                 sqrt = 1 / (0.5 * ybar^0.5))
  
  # build event-study formula
  fml <- as.formula(paste0(
    y_var, " ~ i(rel_month, treat, ref = -1) | oa_shockid + ttwa_year_month"
  ))
  
  # run the regression
  es <- feols(fml, data = dat, cluster = ~ oa_shockid)
  
  # tidy and rescale to percent
  event_df_clean <- tidy(es) %>%
    filter(str_detect(term, "rel_month::")) %>%
    mutate(
      rel_month = as.integer(str_extract(term, "(?<=rel_month::)-?\\d+")),
      estimate  = estimate * mult * 100,
      beta_low  = estimate - 1.96 * (std.error * mult * 100),
      beta_high = estimate + 1.96 * (std.error * mult * 100)
    ) %>%
    select(rel_month, estimate, beta_low, beta_high) %>%
    arrange(rel_month)
  
  
  # SAVE monthly results 
  write_csv(
    event_df_clean,
    file.path(results_dir, paste0(fpref, specs_monthly$tr[r], "_flood_ttwaxym_oa_fe.csv"))
  )
  
  
  # add omitted reference month
  ref_row <- tibble(rel_month = -1, estimate = 0, beta_low = 0, beta_high = 0)
  results <- bind_rows(event_df_clean, ref_row) %>% arrange(rel_month)
  
  # build the event-study plot
  p <- ggplot(results, aes(x = rel_month, y = estimate)) +
    geom_ribbon(aes(ymin = beta_low, ymax = beta_high), fill = "#6BAED6", alpha = 0.4) +
    geom_line(color = "#08306B", size = 1.2) +
    geom_vline(xintercept = 0, linetype = "dashed", color = "black", size = 1) +
    geom_hline(yintercept = 0, linetype = "dashed", color = "black", size = 1) +
    labs(x = "Months", y = ylab) +
    scale_x_continuous(breaks = seq(-6, 12, by = 2)) +
    scale_y_continuous(n.breaks = 8) +
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
  
  print(p)
  
  # save this spec's figure
  ggsave(
    filename = file.path(fig_dir, paste0(fpref, specs_monthly$tr[r], "_flood_ttwaxym_oa_fe.png")),
    plot = p, width = 18, height = 7, units = "in", dpi = 300
  )
  
  # free the fit and sample
  rm(es, dat); gc()
}




##############################################################
# Percentages of OA-date combinations that has a transaction
##############################################################

stacked_data <- read_parquet(reg_dataset_weekly_path)

# First we get the percentage of year-week-OA that have a transaction

week_summary <- stacked_data %>%
  group_by(oa_code, shock_id, selling_year, selling_week) %>%
  summarise(
    had_transaction = as.integer(any(n_transactions > 0, na.rm = TRUE)),
    .groups = "drop"
  )

# extract percentage
weekly_transaction_percentage <- week_summary %>%
  summarise(
    percentage_year_week_oa_with_transaction = 100 * mean(had_transaction, na.rm = TRUE)
  ) %>%
  pull(percentage_year_week_oa_with_transaction)



# Second we get the percentage of year-month-OA that have a transaction

month_summary <- stacked_data %>%
  mutate(
    week_start    = ISOweek2date(sprintf("%d-W%02d-4", selling_year, selling_week)),
    selling_month = month(week_start)
  ) %>%
  group_by(oa_code, shock_id, selling_year, selling_month) %>%
  summarise(
    had_transaction = as.integer(any(n_transactions > 0, na.rm = TRUE)),
    .groups = "drop"
  )

# extract percentage
monthly_transaction_percentage <- month_summary %>%
  summarise(
    percentage_year_month_oa_with_transaction = 100 * mean(had_transaction, na.rm = TRUE)
  ) %>%
  pull(percentage_year_month_oa_with_transaction)


# Third we get the percentage of year-OA that have a transaction

year_summary <- stacked_data %>%
  group_by(oa_code,shock_id, selling_year) %>%
  summarise(
    had_transaction = as.integer(any(n_transactions > 0, na.rm = TRUE)),
    .groups = "drop"
  )

# extract percentage
yearly_transaction_percentage <- year_summary %>%
  summarise(
    percentage_year_oa_with_transaction = 100 * mean(had_transaction, na.rm = TRUE)
  ) %>%
  pull(percentage_year_oa_with_transaction)


######################################################################################
# Percentages of OA-date combinations that has a transaction BOTH PRE AND POST FLOOD
#####################################################################################

# In the stacked event-study data, the same OA can appear in
# multiple shock windows. Therefore, eligibility must be defined
# separately for each OA-shock pair, not just for each OA.
#
# An OA-shock pair is eligible if it has:
#   - at least one transaction in a pre-shock week (rel_week < 0)
#   - at least one transaction in a post-shock week (rel_week > 0)

oa_shock_flags <- stacked_data %>%
  group_by(oa_code, shock_id) %>%
  summarise(
    has_pre_transaction  = any(n_transactions > 0 & rel_week < 0, na.rm = TRUE),
    has_post_transaction = any(n_transactions > 0 & rel_week > 0, na.rm = TRUE),
    eligible_oa_shock    = as.integer(has_pre_transaction & has_post_transaction),
    .groups = "drop"
  ) %>%
  select(oa_code, shock_id, eligible_oa_shock)


# Compute the percentage of OA-shock-year-week combinations that have a transaction, where the numerator includes only OA-shock pairs that are eligible
# (have at least one pre and one post transaction), and the denominator includes all OA-shock-year-week combinations in the weekly collapsed sample.

week_summary <- stacked_data %>%
  group_by(oa_code, shock_id, selling_year, selling_week) %>%
  summarise(
    had_transaction = as.integer(any(n_transactions > 0, na.rm = TRUE)),
    .groups = "drop"
  ) %>%
  left_join(oa_shock_flags, by = c("oa_code", "shock_id")) %>%
  mutate(
    eligible_oa_shock = coalesce(eligible_oa_shock, 0L),
    count_me = as.integer(eligible_oa_shock == 1 & had_transaction == 1)
  )

# extract proportion
week_transaction_stats <- week_summary %>%
  summarise(
    numerator   = sum(count_me, na.rm = TRUE),
    denominator = n(),
    percentage  = 100 * numerator / denominator
  )


# Compute the percentage of OA-shock-year-month combinations that have a transaction, using the same OA-shock eligibility rule as above

month_summary <- stacked_data %>%
  mutate(
    week_start    = ISOweek2date(sprintf("%d-W%02d-4", selling_year, selling_week)),
    selling_month = month(week_start)
  ) %>%
  group_by(oa_code, shock_id, selling_year, selling_month) %>%
  summarise(
    had_transaction = as.integer(any(n_transactions > 0, na.rm = TRUE)),
    .groups = "drop"
  ) %>%
  left_join(oa_shock_flags, by = c("oa_code", "shock_id")) %>%
  mutate(
    eligible_oa_shock = coalesce(eligible_oa_shock, 0L),
    count_me = as.integer(eligible_oa_shock == 1 & had_transaction == 1)
  )

# extract proportion
month_transaction_stats <- month_summary %>%
  summarise(
    numerator   = sum(count_me, na.rm = TRUE),
    denominator = n(),
    percentage  = 100 * numerator / denominator
  )


# Compute the percentage of OA-shock-year combinations that have a transaction, again using OA-shock eligibility based on at least
# one pre-shock and one post-shock transaction.

year_summary <- stacked_data %>%
  group_by(oa_code, shock_id, selling_year) %>%
  summarise(
    had_transaction = as.integer(any(n_transactions > 0, na.rm = TRUE)),
    .groups = "drop"
  ) %>%
  left_join(oa_shock_flags, by = c("oa_code", "shock_id")) %>%
  mutate(
    eligible_oa_shock = coalesce(eligible_oa_shock, 0L),
    count_me = as.integer(eligible_oa_shock == 1 & had_transaction == 1)
  )

# extract proportion
year_transaction_stats <- year_summary %>%
  summarise(
    numerator   = sum(count_me, na.rm = TRUE),
    denominator = n(),
    percentage  = 100 * numerator / denominator
  )

