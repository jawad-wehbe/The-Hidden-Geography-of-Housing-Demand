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
library(penppml)
library(ISOweek)
library(duckdb)
library(haven)





# CLEAR ALL 
rm(list = ls())
gc()


############
# Paths
############

# transaction
transactions_path <- "/home/jawad/Desktop/Raw_Data/HMLR/pp-complete.csv"

postcode_to_coord_path <- "/home/jawad/Desktop/Raw_Data/Shapefiles etc/ONSPD_FEB_2025/Data/ONSPD_FEB_2025_UK.csv"

# other paths

building_addressbook_path <- "/home/jawad/Desktop/Raw_Data/Shapefiles etc/OS/AddressBasePremium_FULL_2025-05-09_001.gpkg"

oa_path <- "/home/jawad/Desktop/Raw_Data/Shapefiles etc/output_areas_2021.gpkg"


duckdb_path <- "/home/jawad/Desktop/Projects/housing_targets/temp/nature/duckcb_greenspace.duckdb"

temp_path <- "/home/jawad/Desktop/Projects/housing_targets/temp/nature/"

#fig_dir <- "/home/jawad/Desktop/Projects/housing_targets/output/figures/nature/"

spill_dir <- "/home/jawad/Desktop/Projects/housing_targets/temp/nature/spill_dir/"

dataset_path <- "/home/jawad/Desktop/Projects/housing_targets/temp/nature/transactions_greenspace.parquet"

cw_dir <- "~/Desktop/Raw_Data/Shapefiles etc/Crosswalks/"

searches_path <- "~/Desktop/Projects/housing_targets/produced/nature/nonbots/all/oa_weekly_search_with_geos.parquet"

weekly_reg_dataset_path <- "~/Desktop/Projects/housing_targets/produced/nature/nonbots/regression_datasets/greenspace_weekly_reg_dataset_complete.parquet"

monthly_reg_dataset_path <- "~/Desktop/Projects/housing_targets/produced/nature/nonbots/regression_datasets/greenspace_monthly_reg_dataset_complete.parquet"

results_dir <- "/home/jawad/Desktop/Projects/housing_targets/produced/nature/nonbots/regression_results/"

# greenspace is in m²; multiply coefficients by 100 to express per 100 m²
scale_per_100m2 <- 100


##########################
# Read the data in
##########################

# load searches and attach on OA x ISO year-week
weekly_searches <- read_parquet(searches_path) %>%
  dplyr::select(oa_code, year, week, buying_searches)

# OA

oa <- st_read(oa_path) 

# READ THE TTWA CROSSWALK AND ASSIGN TO OA their corresponding TTWA
cw_oa_ttwa <- read_parquet(file.path(cw_dir, "oa_ttwa.parquet")) %>%
  group_by(oa_code) %>%
  slice_max(share, n = 1, with_ties = FALSE) %>%
  ungroup() %>%
  select(oa_code, assigned_ttwa = ttwa_code)  


# READ THE LSOA CROSSWALK AND ASSIGN TO OA their corresponding LSOA
cw_oa_lsoa <- read_parquet(file.path(cw_dir, "oa_lsoa.parquet")) %>%
  group_by(oa_code) %>%
  slice_max(share, n = 1, with_ties = FALSE) %>%
  ungroup() %>%
  select(oa_code, assigned_lsoa = lsoa_code)  

# READ THE MSOA CROSSWALK AND ASSIGN TO OA their corresponding MSOA
cw_oa_msoa <- read_parquet(file.path(cw_dir, "oa_msoa.parquet")) %>%
  group_by(oa_code) %>%
  slice_max(share, n = 1, with_ties = FALSE) %>%
  ungroup() %>%
  select(oa_code, assigned_msoa = msoa_code)  

# Transactions

transaction <- read_csv(transactions_path, col_names = FALSE) %>%
  rename(id =  X1, price = X2, date = X3, postcode = X4 ) %>%
  select(id, price, date, postcode) %>%
  mutate(postcode_key = str_to_upper(str_remove_all(postcode, "\\s+")))

########################
# Clean up transactions
########################

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
         date <= as.Date("2024-05-30"))




###########
# duck db
###########

con <- dbConnect(duckdb(), dbdir = duckdb_path)

dbExecute(con, "INSTALL spatial;")
dbExecute(con, "LOAD spatial;")

# Memory limit 
dbExecute(con, "SET memory_limit='150GB';")

# cores
dbExecute(con, "SET threads=20;")

# Spill directory 
dbExecute(con, "SET temp_directory='spill_dir';")

# Fetch the table
greenspace_df <- dbGetQuery(con, "SELECT * FROM oa_greenspace_summary")

# some stats
x <- greenspace_df$median_avg_greenspace_m2


# disconnect
dbDisconnect(con, shutdown = TRUE)

# add binary greenspace
greenspace_df <- greenspace_df %>%
  mutate(
    has_greenspace = if_else(median_avg_greenspace_m2 > 10, 1, 0 )
  )

# quantiles
x <- greenspace_df$median_avg_greenspace_m2

pctile_df <- tibble(
  label = c("p1","p5","p10","p25","p50","p75","p90","p95","p99"),
  q     = c(.01,.05,.10,.25,.50,.75,.90,.95,.99),
  value = quantile(x, c(.01,.05,.10,.25,.50,.75,.90,.95,.99), na.rm = TRUE)
)

p_pctiles <- ggplot(pctile_df, aes(x = factor(label, levels = label), y = value)) +
  geom_col(fill = "#6BAED6") +
  geom_text(aes(label = round(value, 1)), vjust = -0.5, size = 4.5, fontface = "bold") +
  labs(x = "Percentile", y = "Median private greenspace per OA (m²)") +
  theme_classic() +
  theme(
    axis.title.x = element_text(face = "bold", size = 15),
    axis.title.y = element_text(face = "bold", size = 15),
    axis.text.x  = element_text(face = "bold", size = 14),
    axis.text.y  = element_text(face = "bold", size = 14),
    axis.line    = element_line(linewidth = 1.3, colour = "black"),
    axis.ticks   = element_line(linewidth = 1.3, colour = "black"),
    panel.grid   = element_blank()
  )

ggsave(file.path(fig_dir, "greenspace_oa_percentiles.png"),
       p_pctiles, width = 10, height = 7, dpi = 300)

p_pctiles

##########################################################################
# STEP 1: The searches parquet IS the panel
#
# Assumption: the searches file is already a complete/balanced
# OA x year-week panel. Its rows define the universe directly — no
# crossing / completion needed. We only attach OA-level attributes.
##########################################################################

# time index over the searches weeks (week 53 already dropped)
week_lookup <- weekly_searches %>%
  distinct(year, week) %>%
  arrange(year, week) %>%
  mutate(time_id = row_number())

# reference week (last week of Feb 2020)
ref_time_id <- week_lookup %>%
  filter(year == 2020, week == 9) %>%
  pull(time_id)

# panel = searches rows, restricted to OAs with greenspace + crosswalk info
panel <- weekly_searches %>%
  inner_join(greenspace_df, by = "oa_code") %>%
  inner_join(cw_oa_lsoa, by = "oa_code") %>%
  inner_join(cw_oa_ttwa, by = "oa_code") %>%
  inner_join(cw_oa_msoa, by = "oa_code")

#rm(weekly_searches)
gc()


##########################################################################
# STEP 2: Aggregate transactions to OA x ISO year-week
##########################################################################

# assign transactions to OAs
transactions_oa <- st_join(oa, transactions_sf_filtered,
                           join = st_intersects, left = FALSE)

# group transactions at the OA x year-week level
transactions_oa_weekly_summary <- transactions_oa %>%
  st_drop_geometry() %>%
  group_by(oa_code, selling_year, selling_week) %>%
  summarise(
    average_selling_price_weekly = mean(price, na.rm = TRUE),
    had_transaction = as.integer(any(price > 0)),
    n_transactions = n_distinct(id[price > 0]),
    .groups = 'drop'
  )

rm (transactions_sf, transactions_sf_filtered,
   test_with_coords, transaction, postcode_lookup)
gc()


##########################################################################
# STEP 3: Attach transactions onto the searches panel and zero-fill
#
# LEFT join: the panel keeps every searches row (no rows are added or
# removed). Where an OA-week has no transaction, the join produces NA in
# the transaction columns — the replace_na below turns those into
# explicit 0s. This is the only "filling in" needed: since the searches
# panel is already complete, there are no missing DATES to create, only
# missing VALUES to zero out. Transactions in OAs absent from the
# searches file, or in weeks outside its span (incl. 2020-W53), are
# discarded here.
##########################################################################

panel <- panel %>%
  left_join(
    transactions_oa_weekly_summary,
    by = c("oa_code", "year" = "selling_year", "week" = "selling_week")
  ) %>%
  mutate(
    average_selling_price_weekly = replace_na(average_selling_price_weekly, 0),
    had_transaction              = replace_na(had_transaction, 0L),
    n_transactions               = replace_na(n_transactions, 0L)
  )

# quick diagnostics: how many transaction OA-weeks were outside the frame?
# (OAs never searched, or weeks outside the searches span)
n_dropped_txn_cells <- transactions_oa_weekly_summary %>%
  anti_join(panel, by = c("oa_code",
                          "selling_year" = "year",
                          "selling_week" = "week")) %>%
  nrow()
message("Transaction OA-weeks not matched to the searches frame: ",
        n_dropped_txn_cells)



##########################################################################
# STEP 4: Regression preparation
##########################################################################

# time id + relative week (searches-based index)
panel <- panel %>%
  inner_join(week_lookup, by = c("year", "week")) %>%
  mutate(rel_week = time_id - ref_time_id)

# remove 2024+ to run faster
reg_df <- panel %>%
  filter(year < 2024)

rm(panel)
gc()

# make outcome variables in logs / transforms + FE identifiers
reg_df <- reg_df %>%
  mutate(
    # transactions outcomes
    log_selling_price                 = log(average_selling_price_weekly),
    ihs_average_selling_price_weekly  = asinh(average_selling_price_weekly),
    rad_average_selling_price_weekly  = sqrt(average_selling_price_weekly),
    ihs_n_transactions                = asinh(n_transactions),
    rad_n_transactions                = sqrt(n_transactions),
    # searches outcomes
    log_buying_searches               = log(buying_searches),
    ihs_buying_searches               = asinh(buying_searches),
    rad_buying_searches               = sqrt(buying_searches),
    # fixed effect identifiers
    ttwa_yw_id      = paste0(assigned_ttwa, "_", year, "_", week),
    lsoa_week_id    = paste0(assigned_lsoa, "_", week),
    msoa_week_id    = paste0(assigned_msoa, "_", week),
    oa_week         = paste0(oa_code, "_", week),
    yw              = paste0(year, "_", week),
    greenspace_week = paste0(week, "_", has_greenspace)
  )

# save regression dataset
write_parquet(reg_df, weekly_reg_dataset_path)


################################################################
# run regression (CONTINUOUS GREENSPACE) — 6 specs
################################################################


reg_df <- read_parquet(weekly_reg_dataset_path)


# pre-treatment stats

pre_mean <- reg_df %>% 
  filter(rel_week < 0) %>%
  summarise(
    mean_pre_transactions = mean(n_transactions, na.rm = TRUE),
    mean_searches = mean(buying_searches, na.rm = TRUE)
  )
  

# free RAM: keep only the regression frame and paths
rm(list = setdiff(ls(), c("reg_df", "fig_dir", "results_dir", "scale_per_100m2", "monthly_reg_dataset_path")))

gc()

setFixest_nthreads(40)


# specs: outcome column, base var (for ybar), transform type, whether to drop y == 0, y-axis label
specs <- tribble(
  ~name,          ~outcome,                           ~base,                          ~transform, ~drop_zero, ~ylab,
  "log_search",   "log_buying_searches",              "buying_searches",              "log",      TRUE,       "% change in searches per 100m² greenspace",
  "ihs_trans",    "ihs_n_transactions",               "n_transactions",               "ihs",      FALSE,      "% change in transactions per 100m² greenspace",
  #"ihs_price",    "ihs_average_selling_price_weekly", "average_selling_price_weekly", "ihs",      TRUE,       "% change in price per 100m² greenspace",
  #"ihs_search",   "ihs_buying_searches",              "buying_searches",              "ihs",      FALSE,      "% change in searches per 100m² greenspace",
  #"sqrt_price",   "rad_average_selling_price_weekly", "average_selling_price_weekly", "sqrt",     TRUE,       "% change in price per 100m² greenspace",
  "log_price",    "log_selling_price",                "average_selling_price_weekly", "log",      TRUE,       "% change in price per 100m² greenspace"
  #"sqrt_trans",   "rad_n_transactions",               "n_transactions",               "sqrt",     FALSE,      "% change in transactions per 100m² greenspace",
  #"level_trans",  "n_transactions",                   "n_transactions",               "level",    FALSE,      "% change in transactions per 100m² greenspace"
)

results_list <- list()
plot_list    <- list()

for (r in seq_len(nrow(specs))) {
  
  nm     <- specs$name[r]
  y_var  <- specs$outcome[r]
  base   <- specs$base[r]
  tr     <- specs$transform[r]
  dz     <- specs$drop_zero[r]
  ylab   <- specs$ylab[r]
  
  # print what is running
  message(
    "Running spec: ", nm,
    " | outcome: ", y_var,
    " | base: ", base,
    " | transform: ", tr,
    " | drop_zero: ", dz
  )
  
  # regression sample (drop y == 0 where required)
  dat <- reg_df
  if (dz) dat <- dat %>% filter(.data[[base]] > 0)
  
  # ybar = mean of untransformed outcome on the regression sample
  ybar <- mean(dat[[base]], na.rm = TRUE)
  
  # elasticity multiplier per the table
  mult <- switch(tr,
                 log   = 1,                          # log outcome: coefficient already a semi-elasticity
                 ihs   = sqrt(ybar^2 + 1) / ybar,    # beta * sqrt(ybar^2+1)/ybar
                 sqrt  = 1 / (0.5 * ybar^0.5),       # beta / (k*ybar^k), k = 0.5
                 level = 1 / ybar                    # y^1: beta / (k*ybar^k), k = 1  to  beta/ybar
  )
  
  # formula
  fml <- as.formula(paste0(
    y_var,
    " ~ i(rel_week, median_avg_greenspace_m2, ref = -1) | ttwa_yw_id + lsoa_week_id + oa_code"
  ))
  
  # run regression
  est <- feols(fml, data = dat, cluster = ~ oa_code)
  
  # TIDY UP
  ev <- tidy(est, conf.int = TRUE) %>%
    filter(str_detect(term, "rel_week::"),
           str_detect(term, "median_avg_greenspace_m2")) %>%
    mutate(
      rel_week  = as.integer(str_extract(term, "-?\\d+")),
      estimate  = estimate  * mult * 100 * scale_per_100m2,
      lower     = conf.low  * mult * 100 * scale_per_100m2,
      upper     = conf.high * mult * 100 * scale_per_100m2,
      transform = nm
    ) %>%
    dplyr::select(rel_week, estimate, lower, upper, transform)
  
  # reference week
  ref_row <- tibble(rel_week = -1, estimate = 0, lower = 0, upper = 0, transform = nm)
  df_nm   <- bind_rows(ev, ref_row) %>% arrange(rel_week)
  results_list[[nm]] <- df_nm
  
  # --- save results ---
  write_csv(ev, file.path(results_dir, paste0("greenspace_weekly_", nm, "_eventstudy.csv")))
  
  # # plot
  # p <- ggplot(df_nm, aes(rel_week, estimate)) +
  #   geom_ribbon(aes(ymin = lower, ymax = upper), fill = "#6BAED6", alpha = 0.4) +
  #   geom_line(color = "#08306B", linewidth = 1.2) +
  #   geom_vline(xintercept = 0, linetype = "dashed", linewidth = 1) +
  #   geom_hline(yintercept = 0, linetype = "dashed", linewidth = 1) +
  #   labs(x = "Weeks", y = ylab) +
  #   scale_x_continuous(breaks = seq(-60, 201, by = 20)) +
  #   theme_classic() +
  #   theme(
  #     plot.title   = element_text(face = "bold", size = 21, hjust = 0.5),
  #     axis.title.x = element_text(face = "bold", size = 18),
  #     axis.title.y = element_text(face = "bold", size = 18),
  #     axis.text.x  = element_text(face = "bold", size = 24),
  #     axis.text.y  = element_text(face = "bold", size = 24),
  #     axis.line    = element_line(size = 1.3, color = "black"),
  #     axis.ticks   = element_line(size = 1.3, color = "black"),
  #     panel.grid   = element_blank()
  #   )
  # plot_list[[nm]] <- p
  # 
  # p 
  # 
  # # save
  # ggsave(
  #   filename = file.path(fig_dir,
  #                        paste0("greenspace_weekly_", nm, "_oafe_ttwaxywfe_lsoaxweekfe.png")),
  #   plot = p, width = 18, height = 7, units = "in", dpi = 300
  # )
  
  rm(est, dat); gc()
}

event_df_all <- bind_rows(results_list)




##########################################################################
# MONTHLY VERSION — searches-based panel, mirroring the weekly design
#
# Same logic as weekly:
#   frame  = searches aggregated to OA x calendar month
#   attach = greenspace + crosswalks (inner joins define the universe)
#   then   = transactions LEFT-joined on and zero-filled
##########################################################################


# aggregate searches to OA x calendar month
# (month taken from the ISO week's Thursday, so each week maps to exactly
# one month; a boundary week's searches all go to the Thursday's month)
monthly_searches <- weekly_searches %>%
  mutate(
    week_thursday = ISOweek2date(sprintf("%d-W%02d-4", year, week)),
    cal_year  = year(week_thursday),
    cal_month = month(week_thursday)
  ) %>%
  group_by(oa_code, year = cal_year, month = cal_month) %>%
  summarise(
    buying_searches = sum(buying_searches, na.rm = TRUE),
    .groups = "drop"
  )

# month index + reference month (Feb 2020, matching weekly ref 2020-W09)
month_lookup <- monthly_searches %>%
  distinct(year, month) %>%
  arrange(year, month) %>%
  mutate(time_id = row_number())

ref_time_id_monthly <- month_lookup %>%
  filter(year == 2020, month == 2) %>%
  pull(time_id)


# group transactions at the OA x calendar year-month level (from raw date)
transactions_oa_monthly_summary <- transactions_oa %>%
  st_drop_geometry() %>%
  group_by(oa_code, selling_year = year(date), selling_month = month(date)) %>%
  summarise(
    average_selling_price_monthly = mean(price, na.rm = TRUE),
    had_transaction = as.integer(any(price > 0)),
    n_transactions  = n_distinct(id[price > 0]),
    .groups = 'drop'
  )

# panel = monthly searches rows, restricted to OAs with greenspace +
# crosswalk info (same universe rule as weekly)
panel_monthly <- monthly_searches %>%
  inner_join(greenspace_df, by = "oa_code") %>%
  inner_join(cw_oa_lsoa, by = "oa_code") %>%
  inner_join(cw_oa_ttwa, by = "oa_code") %>%
  inner_join(cw_oa_msoa, by = "oa_code")

##########################################################################
# attach transactions onto the searches panel + zero-fill
##########################################################################

panel_monthly <- panel_monthly %>%
  left_join(
    transactions_oa_monthly_summary,
    by = c("oa_code", "year" = "selling_year", "month" = "selling_month")
  ) %>%
  mutate(
    average_selling_price_monthly = replace_na(average_selling_price_monthly, 0),
    had_transaction               = replace_na(had_transaction, 0L),
    n_transactions                = replace_na(n_transactions, 0L)
  )


##########################################################################
# MONTHLY STEP 3: regression preparation
##########################################################################

# time id + relative month (searches-based index)
panel_monthly <- panel_monthly %>%
  inner_join(month_lookup, by = c("year", "month")) %>%
  mutate(rel_month = time_id - ref_time_id_monthly)

# same speed-up cut as weekly
reg_df_monthly <- panel_monthly %>%
  filter(year < 2024)


# outcome transforms + FE identifiers
reg_df_monthly <- reg_df_monthly %>%
  mutate(
    # transactions outcomes
    log_selling_price_monthly = log(average_selling_price_monthly),
    ihs_price_monthly   = asinh(average_selling_price_monthly),
    rad_price_monthly   = sqrt(average_selling_price_monthly),
    ihs_n_transactions  = asinh(n_transactions),
    rad_n_transactions  = sqrt(n_transactions),
    # searches outcomes
    log_buying_searches = log(buying_searches),
    ihs_buying_searches = asinh(buying_searches),
    rad_buying_searches = sqrt(buying_searches),
    # fixed effect identifiers
    ttwa_ym_id    = paste0(assigned_ttwa, "_", year, "_", month),
    lsoa_month_id = paste0(assigned_lsoa, "_", month),
    msoa_month_id = paste0(assigned_msoa, "_", month),
    oa_month      = paste0(oa_code, "_", month),
    ym            = paste0(year, "_", month)
  )

#  save it alongside the weekly one
write_parquet(reg_df_monthly, monthly_reg_dataset_path)

rm(panel_monthly, monthly_searches, transactions_oa_monthly_summary)
gc()

# clear memory
rm (weekly_searches,
    test_with_coords, transaction, postcode_lookup)
gc()


################################################################
# run regression (CONTINUOUS GREENSPACE) — MONTHLY
################################################################

# read it back in
reg_df_monthly <- read_parquet(monthly_reg_dataset_path)

setFixest_nthreads(15)

# specs: outcome column, base var (for ybar), transform type, whether to drop y == 0, y-axis label
specs_monthly <- tribble(
  ~name,          ~outcome,               ~base,                            ~transform, ~drop_zero, ~ylab,
  "log_search",   "log_buying_searches",  "buying_searches",                "log",      TRUE,      "% change in searches per 100m² greenspace",
  "ihs_trans",    "ihs_n_transactions",   "n_transactions",                 "ihs",      FALSE,      "% change in transactions per 100m² greenspace",
  #"ihs_price",    "ihs_price_monthly",    "average_selling_price_monthly",  "ihs",      TRUE,       "% change in price per 100m² greenspace",
  #"ihs_search",   "ihs_buying_searches",  "buying_searches",                "ihs",      FALSE,      "% change in searches per 100m² greenspace",
  #"sqrt_price",   "rad_price_monthly",    "average_selling_price_monthly",  "sqrt",     TRUE,       "% change in price per 100m² greenspace",
  "log_price",    "log_selling_price_monthly", "average_selling_price_monthly", "log",  TRUE,       "% change in price per 100m² greenspace"
  #"sqrt_trans",   "rad_n_transactions",   "n_transactions",                 "sqrt",     FALSE,      "% change in transactions per 100m² greenspace",
  #"level_trans",  "n_transactions",       "n_transactions",                 "level",    FALSE,      "% change in transactions per 100m² greenspace"
)

results_list_monthly <- list()
plot_list_monthly    <- list()

for (r in seq_len(nrow(specs_monthly))) {
  
  nm     <- specs_monthly$name[r]
  y_var  <- specs_monthly$outcome[r]
  base   <- specs_monthly$base[r]
  tr     <- specs_monthly$transform[r]
  dz     <- specs_monthly$drop_zero[r]
  ylab   <- specs_monthly$ylab[r]
  
  # print what is running
  message(
    "Running spec: ", nm,
    " | outcome: ", y_var,
    " | base: ", base,
    " | transform: ", tr,
    " | drop_zero: ", dz
  )
  
  # regression sample (drop y == 0 where required, keyed to the base var)
  dat <- reg_df_monthly
  if (dz) dat <- dat %>% filter(.data[[base]] > 0)
  
  # ybar = mean of UNtransformed outcome on the regression sample
  ybar <- mean(dat[[base]], na.rm = TRUE)
  
  # elasticity multiplier per the table
  mult <- switch(tr,
                 log   = 1,                          # log outcome: coefficient already a semi-elasticity
                 ihs   = sqrt(ybar^2 + 1) / ybar,    # beta * sqrt(ybar^2+1)/ybar
                 sqrt  = 1 / (0.5 * ybar^0.5),       # beta / (k*ybar^k), k = 0.5
                 level = 1 / ybar                    # y^1: beta / (k*ybar^k), k = 1  to  beta/ybar
  )
  
  # formula
  fml <- as.formula(paste0(
    y_var,
    " ~ i(rel_month, median_avg_greenspace_m2, ref = -1) | ttwa_ym_id + lsoa_month_id + oa_code"
  ))
  
  # run regression
  est <- feols(fml, data = dat, cluster = ~ oa_code)
  
  ev <- tidy(est, conf.int = TRUE) %>%
    filter(str_detect(term, "rel_month::"),
           str_detect(term, "median_avg_greenspace_m2")) %>%
    mutate(
      rel_month = as.integer(str_extract(term, "-?\\d+")),
      estimate  = estimate  * mult * 100 * scale_per_100m2,
      lower     = conf.low  * mult * 100 * scale_per_100m2,
      upper     = conf.high * mult * 100 * scale_per_100m2,
      transform = nm
    ) %>%
    dplyr::select(rel_month, estimate, lower, upper, transform)
  
  # reference month
  ref_row <- tibble(rel_month = -1, estimate = 0, lower = 0, upper = 0, transform = nm)
  df_nm   <- bind_rows(ev, ref_row) %>% arrange(rel_month)
  results_list_monthly[[nm]] <- df_nm
  
  # --- save results ---
  write_csv(ev, file.path(results_dir, paste0("greenspace_monthly_", nm, "_eventstudy.csv")))
  
  # # plot
  # p <- ggplot(df_nm, aes(rel_month, estimate)) +
  #   geom_ribbon(aes(ymin = lower, ymax = upper), fill = "#6BAED6", alpha = 0.4) +
  #   geom_line(color = "#08306B", linewidth = 1.2) +
  #   geom_vline(xintercept = 0, linetype = "dashed", linewidth = 1) +
  #   geom_hline(yintercept = 0, linetype = "dashed", linewidth = 1) +
  #   labs(x = "Months", y = ylab) +
  #   scale_x_continuous(breaks = seq(-15, 48, by = 3)) +
  #   theme_classic() +
  #   theme(
  #     plot.title   = element_text(face = "bold", size = 21, hjust = 0.5),
  #     axis.title.x = element_text(face = "bold", size = 18),
  #     axis.title.y = element_text(face = "bold", size = 18),
  #     axis.text.x  = element_text(face = "bold", size = 24),
  #     axis.text.y  = element_text(face = "bold", size = 24),
  #     axis.line    = element_line(size = 1.3, color = "black"),
  #     axis.ticks   = element_line(size = 1.3, color = "black"),
  #     panel.grid   = element_blank()
  #   )
  # plot_list_monthly[[nm]] <- p
  # 
  # # save
  # ggsave(
  #   filename = file.path(fig_dir,
  #                        paste0("greenspace_monthly_", nm, "_oafe_ttwaxymfe_lsoaxmonthfe.png")),
  #   plot = p, width = 18, height = 7, units = "in", dpi = 300
  # )
  
  rm(est, dat); gc()
}

event_df_all_monthly <- bind_rows(results_list_monthly)




##########################################################################################################
# Getting stats from the regression dataset (USING THE ONE FILLED WITH THE 0s AT THE WEEKLY LEVEL)
##########################################################################################################

######################################################################################
# Percentages of OA-date combinations that has a transaction BOTH PRE AND POST COVID
#####################################################################################

# Weekly
oa_shock_flags <- reg_df %>%
  group_by(oa_code) %>%
  summarise(
    has_pre_transaction  = any(n_transactions > 0 & rel_week < 0, na.rm = TRUE),
    has_post_transaction = any(n_transactions > 0 & rel_week > 0, na.rm = TRUE),
    eligible_oa_shock    = as.integer(has_pre_transaction & has_post_transaction),
    .groups = "drop"
  ) %>%
  select(oa_code, eligible_oa_shock)


# Compute the percentage of OA-year-week combinations that have a transaction, where the numerator includes only OAs that are eligible
# (have at least one pre and one post transaction), and the denominator includes all OA-year-week combinations in the weekly collapsed sample.

week_summary <- reg_df %>%
  group_by(oa_code, year, week) %>%
  summarise(
    had_transaction = as.integer(any(n_transactions > 0, na.rm = TRUE)),
    .groups = "drop"
  ) %>%
  left_join(oa_shock_flags, by = c("oa_code")) %>%
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


# Compute the percentage of OA-year-month combinations that have a transaction, using the same OA eligibility rule as above

month_summary <- reg_df %>%
  mutate(
    week_start    = ISOweek2date(sprintf("%d-W%02d-4", year, week)),
    month = month(week_start)
  ) %>%
  group_by(oa_code, year, month) %>%
  summarise(
    had_transaction = as.integer(any(n_transactions > 0, na.rm = TRUE)),
    .groups = "drop"
  ) %>%
  left_join(oa_shock_flags, by = c("oa_code")) %>%
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


# Compute the percentage of OA-year combinations that have a transaction, again using OA eligibility based on at least
# one pre-shock and one post-shock transaction.

year_summary <- reg_df %>%
  group_by(oa_code, year) %>%
  summarise(
    had_transaction = as.integer(any(n_transactions > 0, na.rm = TRUE)),
    .groups = "drop"
  ) %>%
  left_join(oa_shock_flags, by = c("oa_code")) %>%
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

# helper: both stats from one summary
get_stats <- function(df, freq_label) {
  df %>%
    summarise(
      denominator     = n(),
      n_with_tx       = sum(had_transaction, na.rm = TRUE)
    ) %>%
    transmute(
      frequency          = freq_label,
      pct_with_tx        = 100 * n_with_tx / denominator
    )
}

transaction_stats_table <- bind_rows(
  get_stats(week_summary,  "Week-Year-OA"),
  get_stats(month_summary, "Month-Year-OA"),
  get_stats(year_summary,  "Year-OA")
)

print(transaction_stats_table)





reg_df <- read_parquet(weekly_reg_dataset_path)

# --- per OA-week (the panel's native unit) ---
weekly_rate <- reg_df %>%
  summarise(
    n_oa_weeks      = n(),
    n_oas           = n_distinct(oa_code),
    mean_tx         = mean(n_transactions),          # incl. zeros
    pct_weeks_any   = 100 * mean(n_transactions > 0),
    p50             = median(n_transactions),
    p90             = quantile(n_transactions, 0.90),
    max             = max(n_transactions)
  )

# --- per OA-month ---
monthly_rate <- reg_df %>%
  mutate(month = month(ISOweek2date(sprintf("%d-W%02d-4", year, week)))) %>%
  group_by(oa_code, year, month) %>%
  summarise(n_transactions = sum(n_transactions), .groups = "drop") %>%
  summarise(
    mean_tx       = mean(n_transactions),
    pct_any       = 100 * mean(n_transactions > 0),
    p50           = median(n_transactions)
  )

# --- per OA-year ---
yearly_rate <- reg_df %>%
  group_by(oa_code, year) %>%
  summarise(n_transactions = sum(n_transactions), .groups = "drop") %>%
  summarise(
    mean_tx       = mean(n_transactions),
    pct_any       = 100 * mean(n_transactions > 0),
    p50           = median(n_transactions)
  )

bind_rows(
  weekly_rate  %>% transmute(unit = "OA-week",  mean_tx, pct_any = pct_weeks_any),
  monthly_rate %>% transmute(unit = "OA-month", mean_tx, pct_any),
  yearly_rate  %>% transmute(unit = "OA-year",  mean_tx, pct_any)
)