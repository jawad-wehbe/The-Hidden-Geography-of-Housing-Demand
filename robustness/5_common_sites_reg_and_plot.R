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


# paths
ed_path <- "~/Desktop/Projects/housing_targets/produced/search_on_build_shock/analysis/ed_reg_dataset.parquet"
sd_path <- "~/Desktop/Projects/housing_targets/produced/search_on_build_shock/analysis/sd_reg_dataset.parquet"
saved_or_contacted_searches_path <- "~/Desktop/Projects/housing_targets/produced/nature/nonbots/saved_or_contacted/oa_weekly_search_with_geos.parquet"
fig_dir <- "~/Desktop/Projects/housing_targets/output/figures/nature/nonbots/saved_or_contacted/"

# where to save regression output so we don't rerun feols
results_dir <- "~/Desktop/Projects/housing_targets/produced/nature/nonbots/saved_or_contacted/"
buying_tidy_path <- file.path(results_dir, "contacted_or_saved_supply_shock_eventstudy_results_tidy.csv")


# where to save the regression-ready dataset so we don't rebuild it
reg_dataset_dir<- "/home/jawad/Desktop/Projects/housing_targets/produced/nature/nonbots/regression_datasets/"
reg_dataset_path <- file.path(reg_dataset_dir, "contacted_or_saved_supply_shock_regression_dataset.parquet")


# paths for transactions (ONLY USED IN DESCRIPTIVES AT THE END)
transactions_path      <- "/home/jawad/Desktop/Raw_Data/HMLR/pp-complete.csv"
postcode_to_coord_path <- "/home/jawad/Desktop/Raw_Data/Shapefiles etc/ONSPD_FEB_2025/Data/ONSPD_FEB_2025_UK.csv"
oa_path                <- "/home/jawad/Desktop/Raw_Data/Shapefiles etc/output_areas_2021.gpkg"

##################################################################################
# VIP: Due to computation constraints given the size of each regression data set: 
# 1- We chose the sites common in both data sets
# 2- We restrict the event window to 44 weeks post treatment
##################################################################################
# read raw transactions
transaction <- read_csv(transactions_path, col_names = FALSE) %>%
  rename(id = X1, price = X2, date = X3, postcode = X4) %>%
  select(id, price, date, postcode) %>%
  mutate(postcode_key = str_to_upper(str_remove_all(postcode, "\\s+")))

# postcode -> coordinates lookup
postcode_lookup <- read_csv(postcode_to_coord_path) %>%
  select(pcds, lat, long) %>%
  filter(!is.na(lat) & !is.na(long), lat < 90) %>%   # 99.999999 = no grid ref
  mutate(postcode_key = str_to_upper(str_remove_all(pcds, "\\s+")))

# read in OAs
output_areas <- st_read(oa_path) %>%
  st_transform(27700)


# load datasets
ed_df <- read_parquet(ed_path)
sd_df <- read_parquet(sd_path)
saved_or_contacted_searches <- read_parquet(saved_or_contacted_searches_path)


# Find common construction_site_ids
common_sites <- intersect(
  unique(ed_df$construction_site_id),
  unique(sd_df$construction_site_id)
)

# remove the ed dataset just for ram purposes
rm(ed_df)
gc()

#----------------------------------------------------------------------
# Regression for buying using sd on this filtered sample
#---------------------------------------------------------------------


# filter the buying data
stacked_df <- sd_df %>% filter(construction_site_id %in% common_sites)

rm(sd_df)
gc()

#########################################################################
# Replace ordinary searches with searches only from saved or contacted
#########################################################################


# replace same week==53 by 52 convention used when the panel was built
new_searches <- saved_or_contacted_searches %>%
  mutate(week = if_else(week == 53L, 52L, week))  %>%
  group_by(oa_code, year, week) %>%
  summarise(
    buying_searches  = sum(buying_searches,  na.rm = TRUE),
    letting_searches = sum(letting_searches, na.rm = TRUE),
    .groups = "drop"
  )

n_before <- nrow(stacked_df)

# 2. Drop the old searches, join the new ones, zero-fill weeks with no serious search
stacked_df_updated <- stacked_df %>%
  select(-buying_searches, -letting_searches) %>%
  left_join(new_searches, by = c("oa_code", "year", "week"))

# check if anyhing did not get searches 
test <- stacked_df_updated %>%
  filter(is.na(buying_searches), is.na(letting_searches))

# clear for ram
rm(new_searches, saved_or_contacted_searches, weekly, stacked_df); gc()

###############################
# Prepare and run regression
###############################

# drop unnecessary weeks
stacked_df_updated <- stacked_df_updated %>% 
  filter(rel_yw <= 44) %>% 
  select(-Treated_52, -Treated_51, -Treated_50, -Treated_49, -Treated_48, -Treated_47, -Treated_45, -Treated_46)


# create log searches and FE identifiers

stacked_df_updated <- stacked_df_updated %>%
  mutate(
    ln_buying_searches  = log(buying_searches),
    ln_letting_searches = log(letting_searches),
    shockweek_id = paste0(construction_site_id, "_", year, "_", week),
    oa_stack_id = paste0(oa_code, "_", construction_site_id)
  ) %>%
  select(-Treated_m5, -treated_today)

# remove things for ram
stacked_df_reg <- stacked_df_updated %>%
  mutate(across(starts_with("Treated_"), as.logical)) %>%
  select(-construction_site_id, -oa_code, -year,-week,-assigned_lsoa,-assigned_msoa,-assigned_la,-assigned_ttwa, -Group)

gc()

# drop more columns not needed

stacked_df_reg <-stacked_df_reg %>%
  select(-buying_searches, -letting_searches, -site_size, -rel_yw, -ln_letting_searches)

gc()

# count the rows

cat("Buying regression rows (stacked_df_reg):", nrow(stacked_df_reg), "\n")


# # save the regression-ready dataset before running feols
# write_parquet(stacked_df_reg, reg_dataset_path)

# read it back in

stacked_df_reg <- read_parquet(reg_dataset_path)

# wipe everything except the regression dataset
rm(list = setdiff(ls(), c("stacked_df_reg", "fig_dir", "buying_tidy_path")))
gc()

# Dummy names
treat_vars <- stacked_df_reg %>% select(starts_with("Treated_")) %>% names()

# Formulas for each outcome
fml_buying  <- as.formula(paste0("ln_buying_searches ~ ", paste(treat_vars, collapse = " + "), " | oa_stack_id + shockweek_id"))

# set threads
#setFixest_nthreads(30)

# Run Regressions 
buying_res  <- feols(fml_buying,  data = stacked_df_reg, cluster = ~oa_stack_id)

# tidy results
buying_tidy <- tidy(buying_res) %>%
  filter(str_detect(term, "^Treated_")) %>%
  select(term, estimate, std.error)

# release ram

rm(buying_res)
gc()

# cleaning names and creating relative week

buying_tidy <- buying_tidy %>%
  mutate(
    # Remove 'Treated_' and any trailing TRUE/FALSE
    term_clean = str_remove_all(term, "Treated_|TRUE|FALSE"),
    # If it starts with 'm', make it negative
    rel_week = case_when(
      str_detect(term_clean, "^m") ~ -as.integer(str_remove(term_clean, "^m")),
      TRUE ~ as.integer(term_clean)
    ),
    se = std.error,
    search_type = "buying"
  ) %>%
  select(rel_week, estimate, se, search_type) %>%
  arrange(rel_week)

# save the tidy table so we can skip feols next time
write_csv(buying_tidy, buying_tidy_path)

buying_tidy <- read_csv(buying_tidy_path)
# Calculate CI columns 
results <- buying_tidy %>%
  mutate(
    estimate = estimate * 100,
    se = se * 100,
    lower = estimate - 1.96 * se,
    upper = estimate + 1.96 * se
  )

# Create a reference row for week -5
ref_row <- tibble(
  rel_week = -5,
  estimate = 0,
  se = 0,
  lower = 0,
  upper = 0,
  search_type = "buying"
)

# Bind the new row to your existing results
results <- bind_rows(results, ref_row)

max_y <- max(results$estimate, na.rm = TRUE)

# Plot Buying
buying_plot <- ggplot(
  results %>% filter(search_type == "buying"),
  aes(x = rel_week, y = estimate)
) +
  geom_ribbon(aes(ymin = lower, ymax = upper), fill = "#6BAED6", alpha = 0.4) +
  geom_line(color = "#08306B", linewidth = 1.2) +
  geom_vline(xintercept = 0, linetype = "dashed", color = "black", linewidth = 1) +
  geom_hline(yintercept = 0, linetype = "dashed", linewidth = 1) +
  annotate(
    "text",
    x = 11,
    y = max_y - 0.05,
    label = "First Plot Construction\n Start Week ",
    vjust = 0,
    size = 10,
    fontface = "bold"
  ) +
  labs(
    x = "Weeks",
    y = "% change in searches"
  ) +
  scale_x_continuous(
    breaks = sort(unique(c(-26, -5, 0, seq(-20, 40, by = 5), 44)))
  ) +
  scale_y_continuous(
    breaks = seq(-1, 2.2, by = 0.4)
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

# Buying plot
ggsave(
  filename = file.path(fig_dir, "nonbots_saved_or_contacted_sd_filtered_pooled_buying.png"),
  plot = buying_plot,
  width = 18, height = 7, dpi = 300
)


####################
# Get some stats on the searches
####################

unique(stacked_df$Group)


test <- stacked_df %>%
  filter(Group == "Treat", rel_yw < 0) %>%
  summarise(
    avg_searches = mean(buying_searches),
    .groups = 'drop'
  )
  


######################################################################################################
# Running a version only on treated areas that fall below the median of searches pre-treatment
######################################################################################################

###############################################################
# Keep shocks that mostly hit low-search (below-median) areas
# Baseline = mean buying searches pre-treatment, treated areas only
###############################################################

# pre-treatment search level for each treated area
baseline <- stacked_df_updated %>%
  filter(rel_yw < 0, Group == "Treat") %>%
  group_by(construction_site_id, oa_code) %>%
  summarise(baseline_searches = mean(buying_searches), .groups = "drop")


# median across treated areas
med <- median(baseline$baseline_searches)

# for each shock, what share of its treated areas are below that median
site_share <- baseline %>%
  mutate(below = baseline_searches < med) %>%
  group_by(construction_site_id) %>%
  summarise(
    n_treated_oas = n(),
    share_below   = mean(below),
    .groups = "drop"
  )

# How much variation: sites all-below, all-above, or mixed
site_share %>%
  mutate(category = case_when(
    share_below == 1 ~ "all OAs below median",
    share_below == 0 ~ "all OAs above median",
    TRUE             ~ "mixed"
  )) %>%
  count(category)


# keep shocks where all treated areas are low-search
keep_sites <- site_share %>%
  filter(share_below == 1) %>%
  pull(construction_site_id)

cat("Sites kept:", length(keep_sites), "of", nrow(site_share), "\n")

# get the AVERSGE PRE-TREATMENT SEARCHES FOR TREATED AREAS IF WE FILTER TO SHOCKS THAT HAVE ALL TREATED OAs ONLY BELOW THE MEDIAN
summary <- stacked_df_updated %>%
  filter(Group == "Treat", rel_yw <0, construction_site_id %in% keep_sites) %>%
  summarise(
    avg_pre_searches = mean(buying_searches)
  )


# keep the whole stack (treated + control) for those shocks
stacked_df_reg_filtered <- stacked_df_updated %>%
  filter(construction_site_id %in% keep_sites)


##############################################
# From here on, we continue the original code
##############################################


# remove things for ram
stacked_df_reg_filtered <- stacked_df_reg_filtered %>%
  mutate(across(starts_with("Treated_"), as.logical)) %>%
  select(-construction_site_id, -oa_code, -year,-week,-assigned_lsoa,-assigned_msoa,-assigned_la,-assigned_ttwa, -Group)

gc()

# drop more columns not needed

stacked_df_reg_filtered <-stacked_df_reg_filtered %>%
  select(-buying_searches, -letting_searches, -site_size, -rel_yw, -ln_letting_searches)

gc()

# count the rows

cat("Buying regression rows (stacked_df_reg_filtered):", nrow(stacked_df_reg_filtered), "\n")

# Dummy names
treat_vars <- stacked_df_reg_filtered %>% select(starts_with("Treated_")) %>% names()

# Formulas for each outcome
fml_buying  <- as.formula(paste0("ln_buying_searches ~ ", paste(treat_vars, collapse = " + "), " | oa_stack_id + shockweek_id"))

# set threads
setFixest_nthreads(15)

# Run Regressions 
buying_res  <- feols(fml_buying,  data = stacked_df_reg_filtered, cluster = ~oa_stack_id)

# tidy results
buying_tidy <- tidy(buying_res) %>%
  filter(str_detect(term, "^Treated_")) %>%
  select(term, estimate, std.error)

# release ram

rm(buying_res)
gc()

# cleaning names and creating relative week

buying_tidy <- buying_tidy %>%
  mutate(
    # Remove 'Treated_' and any trailing TRUE/FALSE
    term_clean = str_remove_all(term, "Treated_|TRUE|FALSE"),
    # If it starts with 'm', make it negative
    rel_week = case_when(
      str_detect(term_clean, "^m") ~ -as.integer(str_remove(term_clean, "^m")),
      TRUE ~ as.integer(term_clean)
    ),
    se = std.error,
    search_type = "buying"
  ) %>%
  select(rel_week, estimate, se, search_type) %>%
  arrange(rel_week)


# Calculate CI columns 
results <- buying_tidy %>%
  mutate(
    estimate = estimate * 100,
    se = se * 100,
    lower = estimate - 1.96 * se,
    upper = estimate + 1.96 * se
  )

# Create a reference row for week -5
ref_row <- tibble(
  rel_week = -5,
  estimate = 0,
  se = 0,
  lower = 0,
  upper = 0,
  search_type = "buying"
)

# Bind the new row to your existing results
results <- bind_rows(results, ref_row)

max_y <- max(results$estimate, na.rm = TRUE)

# Plot Buying
buying_plot <- ggplot(
  results %>% filter(search_type == "buying"),
  aes(x = rel_week, y = estimate)
) +
  geom_ribbon(aes(ymin = lower, ymax = upper), fill = "#6BAED6", alpha = 0.4) +
  geom_line(color = "#08306B", size = 1.2) +
  geom_vline(xintercept = 0, linetype = "dashed", color = "black", size = 1) +
  annotate(
    "text", 
    x = 13, 
    y = max_y + 0.05,      # Small buffer above the plot line
    label = "First Plot Construction start\n Week ",
    vjust = 0,             # Align bottom of text to y
    size = 4,              # Adjust text size as you wish
    fontface = "bold"
  ) +
  labs(
    x = "Weeks",
    y = "Percent change in searches (%)"
  ) +
  scale_x_continuous(
    breaks = sort(unique(c(-26, -5, 0, seq(-20, 40, by = 5), 44)))
  ) +
  scale_y_continuous(
    breaks = seq(-1, 5, by = 1)  
  ) +
  theme_bw(base_size = 17) +
  theme(
    plot.title = element_text(face = "bold", size = 21, hjust = 0.5),
    axis.title.x = element_text(face = "bold", size = 15),
    axis.title.y = element_text(face = "bold", size = 15),
    axis.text.x = element_text(face = "bold", size = 16),
    axis.text.y = element_text(face = "bold", size = 16),
    axis.line = element_line(size = 1.3, color = "black"),
    axis.ticks = element_line(size = 1.3, color = "black"),
    panel.grid = element_blank()
  )

print(buying_plot)

# #  Buying plot
ggsave(
  filename = file.path(fig_dir, "below_median_nonbots_saved_or_contacted_sd_filtered_pooled_buying.png"),
  plot = buying_plot,
  width = 8, height = 6, dpi = 320
)

##################################################
# Transactions: read, clean, assign to OA-year-week
##################################################

# join, keep matched, restrict to sample window early (keeps the sf small)
transactions_sf <- transaction %>%
  left_join(postcode_lookup, by = "postcode_key") %>%
  filter(!is.na(pcds),
         date >= as.Date("2019-01-01"),
         date <= as.Date("2024-05-30")) %>%
  distinct(id, .keep_all = TRUE) %>%                 # guard against duplicate ids
  st_as_sf(coords = c("long", "lat"), crs = 4326) %>%
  st_transform(27700)

rm(transaction, postcode_lookup); gc()

# assign each transaction to an OA
output_areas <- st_read(oa_path) %>%
  st_transform(27700) %>%
  select(oa_code)

transactions_oa <- st_join(transactions_sf, output_areas,
                           join = st_intersects, left = FALSE) %>%
  st_drop_geometry()

#rm(transactions_sf, output_areas); gc()

# collapse to OA-year-week counts (same week conventions as the panel)
tx_oa_weekly <- transactions_oa %>%
  mutate(
    year = isoyear(date),
    week = pmin(isoweek(date), 52L)
  ) %>%
  group_by(oa_code, year, week) %>%
  summarise(
    n_transactions               = n(),
    average_selling_price_weekly = mean(price, na.rm = TRUE),
    .groups = "drop"
  )

#rm(transactions_oa); gc()

##################################################
# Attach to the panel, zero-fill -> reg_df
##################################################

reg_df <- stacked_df_updated %>%
  left_join(tx_oa_weekly, by = c("oa_code", "year", "week")) %>%
  mutate(
    n_transactions  = replace_na(n_transactions, 0L),
    had_transaction = as.integer(n_transactions > 0),
    rel_week        = rel_yw
  )

# rm(tx_oa_weekly); gc()


######################################################################################
# Percentages of OA-date combinations with a transaction:
# overall, and restricted to OAs with both pre- and post-shock transactions
#####################################################################################

# eligibility: OA has at least one pre AND one post transaction
oa_shock_flags <- reg_df %>%
  group_by(oa_code) %>%
  summarise(
    has_pre_transaction  = any(n_transactions > 0 & rel_week < 0, na.rm = TRUE),
    has_post_transaction = any(n_transactions > 0 & rel_week > 0, na.rm = TRUE),
    eligible_oa_shock    = as.integer(has_pre_transaction & has_post_transaction),
    .groups = "drop"
  ) %>%
  select(oa_code, eligible_oa_shock)

# --- Weekly ---
week_summary <- reg_df %>%
  group_by(oa_code, year, week) %>%
  summarise(
    had_transaction = as.integer(any(n_transactions > 0, na.rm = TRUE)),
    .groups = "drop"
  ) %>%
  left_join(oa_shock_flags, by = "oa_code") %>%
  mutate(
    eligible_oa_shock = coalesce(eligible_oa_shock, 0L),
    count_me = as.integer(eligible_oa_shock == 1 & had_transaction == 1)
  )

# --- Monthly (Thursday of ISO week -> month) ---
month_summary <- reg_df %>%
  mutate(
    week_start = ISOweek2date(sprintf("%d-W%02d-4", year, week)),
    month      = month(week_start)
  ) %>%
  group_by(oa_code, year, month) %>%
  summarise(
    had_transaction = as.integer(any(n_transactions > 0, na.rm = TRUE)),
    .groups = "drop"
  ) %>%
  left_join(oa_shock_flags, by = "oa_code") %>%
  mutate(
    eligible_oa_shock = coalesce(eligible_oa_shock, 0L),
    count_me = as.integer(eligible_oa_shock == 1 & had_transaction == 1)
  )

# --- Yearly ---
year_summary <- reg_df %>%
  group_by(oa_code, year) %>%
  summarise(
    had_transaction = as.integer(any(n_transactions > 0, na.rm = TRUE)),
    .groups = "drop"
  ) %>%
  left_join(oa_shock_flags, by = "oa_code") %>%
  mutate(
    eligible_oa_shock = coalesce(eligible_oa_shock, 0L),
    count_me = as.integer(eligible_oa_shock == 1 & had_transaction == 1)
  )

# helper: both stats from one summary
get_stats <- function(df, freq_label) {
  df %>%
    summarise(
      denominator       = n(),
      n_with_tx         = sum(had_transaction, na.rm = TRUE),
      n_with_tx_prepost = sum(count_me, na.rm = TRUE)
    ) %>%
    transmute(
      frequency           = freq_label,
      pct_with_tx         = 100 * n_with_tx / denominator,
      pct_with_tx_prepost = 100 * n_with_tx_prepost / denominator,
      denominator
    )
}

transaction_stats_table <- bind_rows(
  get_stats(week_summary,  "Week-Year-OA"),
  get_stats(month_summary, "Month-Year-OA"),
  get_stats(year_summary,  "Year-OA")
)

print(transaction_stats_table)






######################################################################################
# TREATED ONLY: Percentages of OA-date combinations with a transaction:
# overall, and restricted to OAs with both pre- and post-shock transactions
#####################################################################################

# restrict to treated OAs only
reg_df_treated <- reg_df %>% filter(Group == "Treat")

# eligibility: treated OA has at least one pre AND one post transaction
oa_shock_flags <- reg_df_treated %>%
  group_by(oa_code) %>%
  summarise(
    has_pre_transaction  = any(n_transactions > 0 & rel_week < 0, na.rm = TRUE),
    has_post_transaction = any(n_transactions > 0 & rel_week > 0, na.rm = TRUE),
    eligible_oa_shock    = as.integer(has_pre_transaction & has_post_transaction),
    .groups = "drop"
  ) %>%
  select(oa_code, eligible_oa_shock)

# --- Weekly ---
week_summary <- reg_df_treated %>%
  group_by(oa_code, year, week) %>%
  summarise(
    had_transaction = as.integer(any(n_transactions > 0, na.rm = TRUE)),
    .groups = "drop"
  ) %>%
  left_join(oa_shock_flags, by = "oa_code") %>%
  mutate(
    eligible_oa_shock = coalesce(eligible_oa_shock, 0L),
    count_me = as.integer(eligible_oa_shock == 1 & had_transaction == 1)
  )

# --- Monthly (Thursday of ISO week -> month) ---
month_summary <- reg_df_treated %>%
  mutate(
    week_start = ISOweek2date(sprintf("%d-W%02d-4", year, week)),
    month      = month(week_start)
  ) %>%
  group_by(oa_code, year, month) %>%
  summarise(
    had_transaction = as.integer(any(n_transactions > 0, na.rm = TRUE)),
    .groups = "drop"
  ) %>%
  left_join(oa_shock_flags, by = "oa_code") %>%
  mutate(
    eligible_oa_shock = coalesce(eligible_oa_shock, 0L),
    count_me = as.integer(eligible_oa_shock == 1 & had_transaction == 1)
  )

# --- Yearly ---
year_summary <- reg_df_treated %>%
  group_by(oa_code, year) %>%
  summarise(
    had_transaction = as.integer(any(n_transactions > 0, na.rm = TRUE)),
    .groups = "drop"
  ) %>%
  left_join(oa_shock_flags, by = "oa_code") %>%
  mutate(
    eligible_oa_shock = coalesce(eligible_oa_shock, 0L),
    count_me = as.integer(eligible_oa_shock == 1 & had_transaction == 1)
  )

# helper: both stats from one summary
get_stats <- function(df, freq_label) {
  df %>%
    summarise(
      denominator       = n(),
      n_with_tx         = sum(had_transaction, na.rm = TRUE),
      n_with_tx_prepost = sum(count_me, na.rm = TRUE)
    ) %>%
    transmute(
      frequency           = freq_label,
      pct_with_tx         = 100 * n_with_tx / denominator,
      pct_with_tx_prepost = 100 * n_with_tx_prepost / denominator,
      denominator
    )
}

transaction_stats_table_treated <- bind_rows(
  get_stats(week_summary,  "Week-Year-OA"),
  get_stats(month_summary, "Month-Year-OA"),
  get_stats(year_summary,  "Year-OA")
)

print(transaction_stats_table_treated)