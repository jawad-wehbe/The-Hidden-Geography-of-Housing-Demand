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
ed_path <- "~/Desktop/Projects/housing_targets/produced/nature/nonbots/all/ed_reg_dataset.parquet"
sd_path <- "~/Desktop/Projects/housing_targets/produced/nature/nonbots/all/sd_reg_dataset.parquet"
all_searches_path <- "~/Desktop/Projects/housing_targets/produced/nature/nonbots/all/oa_weekly_search_with_geos.parquet"
fig_dir <- "~/Desktop/Projects/housing_targets/output/figures/nature/nonbots/"
#oa_class_path <- "/home/jawad/Desktop/Projects/housing_targets/produced/reclassification/oa_classified_gb.csv"


# where to save the regression-ready dataset so we don't rebuild it
reg_dataset_dir<- "/home/jawad/Desktop/Projects/housing_targets/produced/nature/nonbots/regression_datasets/"
reg_dataset_path <- file.path(reg_dataset_dir, "all_nonbots_supply_shock_regression_dataset.parquet")

# where to save regression output so we don't rerun feols
results_dir <- "~/Desktop/Projects/housing_targets/produced/nature/nonbots/all/"
buying_tidy_path <- file.path(results_dir, "supply_shock_all_eventstudy_results_tidy.csv")
buying_below_median_path <- file.path(results_dir, "below_median_all_supply_shock_eventstudy_results_tidy.csv")
buying_above_median_path <- file.path(results_dir, "above_median_all_supply_shock_eventstudy_results_tidy.csv")
buying_new_rural_path <- file.path(results_dir, "new_rural_all_supply_shock_eventstudy_results_tidy.csv")

# paths for transactions (ONLY USED IN DESCRIPTIVES AT THE END)
transactions_path      <- "/home/jawad/Desktop/Raw_Data/HMLR/pp-complete.csv"
postcode_to_coord_path <- "/home/jawad/Desktop/Raw_Data/Shapefiles etc/ONSPD_FEB_2025/Data/ONSPD_FEB_2025_UK.csv"
oa_path                <- "/home/jawad/Desktop/Raw_Data/Shapefiles etc/output_areas_2021.gpkg"

##################################################################################
# VIP: Due to computation constraints given the size of each regression data set: 
# 1- We chose the sites common in both data sets
# 2- We restrict the event window to 44 weeks post treatment
##################################################################################

# # read OA classification
# #oa_class <- read_csv(oa_class_path)
# 
# # CHECK these two before running: column name + exact label string
# names(oa_class)
# oa_class %>% count(classification)   # <- rename if your column differs
# 
# class_col   <- "classification"          # column holding the class label
# target_class <- "new rural development" # exact label to keep
# 
# oa_class <- oa_class %>%
#   select(oa_code, classification)


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
all_searches <- read_parquet(all_searches_path)


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
# Replace ordinary searches with searches only from all nonbots
#########################################################################


# replace same week==53 by 52 convention used when the panel was built
new_searches <- all_searches %>%
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
rm(new_searches, all_searches, weekly, stacked_df); gc()

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
  select(-buying_searches, -letting_searches, , -rel_yw, -ln_letting_searches)

gc()

# count the rows

cat("Buying regression rows (stacked_df_reg):", nrow(stacked_df_reg), "\n")


# save the regression-ready dataset before running feols
write_parquet(stacked_df_reg, reg_dataset_path)

# wipe everything except the regression dataset
rm(list = setdiff(ls(), "stacked_df_reg"))
gc()

# Dummy names
treat_vars <- stacked_df_reg %>% select(starts_with("Treated_")) %>% names()


# Formulas for each outcome
fml_buying  <- as.formula(paste0("ln_buying_searches ~ ", paste(treat_vars, collapse = " + "), " | oa_stack_id + shockweek_id"))

# set threads
#setFixest_nthreads(30)

rm(stacked_df_updated)
gc()

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
  filename = file.path(fig_dir, "nonbots_all_sd_filtered_pooled_buying.png"),
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


# 
# ######################################################################################################
# # Running a version only on treated areas that fall below the median of searches pre-treatment
# ######################################################################################################
# 
# ###############################################################
# # Keep shocks that mostly hit low-search (below-median) areas
# # Baseline = mean buying searches pre-treatment, treated areas only
# ###############################################################
# 
# # pre-treatment search level for each treated area
# baseline <- stacked_df_updated %>%
#   filter(rel_yw < 0, Group == "Treat") %>%
#   group_by(construction_site_id, oa_code) %>%
#   summarise(baseline_searches = mean(buying_searches), .groups = "drop")
# 
# 
# # median across treated areas
# med <- median(baseline$baseline_searches)
# 
# # for each shock, what share of its treated areas are below that median
# site_share <- baseline %>%
#   mutate(below = baseline_searches < med) %>%
#   group_by(construction_site_id) %>%
#   summarise(
#     n_treated_oas = n(),
#     share_below   = mean(below),
#     .groups = "drop"
#   )
# 
# # How much variation: sites all-below, all-above, or mixed
# site_share %>%
#   mutate(category = case_when(
#     share_below == 1 ~ "all OAs below median",
#     share_below == 0 ~ "all OAs above median",
#     TRUE             ~ "mixed"
#   )) %>%
#   count(category)
# 
# 
# # keep shocks where all treated areas are low-search
# keep_sites <- site_share %>%
#   filter(share_below == 1) %>%
#   pull(construction_site_id)
# 
# cat("Sites kept:", length(keep_sites), "of", nrow(site_share), "\n")
# 
# # get the AVERSGE PRE-TREATMENT SEARCHES FOR TREATED AREAS IF WE FILTER TO SHOCKS THAT HAVE ALL TREATED OAs ONLY BELOW THE MEDIAN
# summary <- stacked_df_updated %>%
#   filter(Group == "Treat", rel_yw <0, construction_site_id %in% keep_sites) %>%
#   summarise(
#     avg_pre_searches = mean(buying_searches)
#   )
# 
# 
# # keep the whole stack (treated + control) for those shocks
# stacked_df_reg_filtered <- stacked_df_updated %>%
#   filter(construction_site_id %in% keep_sites)
# 
# 
# ##############################################
# # From here on, we continue the original code
# ##############################################
# 
# 
# # remove things for ram
# stacked_df_reg_filtered <- stacked_df_reg_filtered %>%
#   mutate(across(starts_with("Treated_"), as.logical)) %>%
#   select(-construction_site_id, -oa_code, -year,-week,-assigned_lsoa,-assigned_msoa,-assigned_la,-assigned_ttwa, -Group)
# 
# gc()
# 
# # drop more columns not needed
# 
# stacked_df_reg_filtered <-stacked_df_reg_filtered %>%
#   select(-buying_searches, -letting_searches, -site_size, -rel_yw, -ln_letting_searches)
# 
# gc()
# 
# # count the rows
# 
# cat("Buying regression rows (stacked_df_reg_filtered):", nrow(stacked_df_reg_filtered), "\n")
# 
# # Dummy names
# treat_vars <- stacked_df_reg_filtered %>% select(starts_with("Treated_")) %>% names()
# 
# # Formulas for each outcome
# fml_buying  <- as.formula(paste0("ln_buying_searches ~ ", paste(treat_vars, collapse = " + "), " | oa_stack_id + shockweek_id"))
# 
# # set threads
# setFixest_nthreads(20)
# 
# # Run Regressions 
# buying_res  <- feols(fml_buying,  data = stacked_df_reg_filtered, cluster = ~oa_stack_id)
# 
# # tidy results
# buying_tidy <- tidy(buying_res) %>%
#   filter(str_detect(term, "^Treated_")) %>%
#   select(term, estimate, std.error)
# 
# # release ram
# 
# rm(buying_res)
# gc()
# 
# # cleaning names and creating relative week
# buying_tidy <- buying_tidy %>%
#   mutate(
#     # Remove 'Treated_' and any trailing TRUE/FALSE
#     term_clean = str_remove_all(term, "Treated_|TRUE|FALSE"),
#     # If it starts with 'm', make it negative
#     rel_week = case_when(
#       str_detect(term_clean, "^m") ~ -as.integer(str_remove(term_clean, "^m")),
#       TRUE ~ as.integer(term_clean)
#     ),
#     se = std.error,
#     search_type = "buying"
#   ) %>%
#   select(rel_week, estimate, se, search_type) %>%
#   arrange(rel_week)
# 
# 
# # Calculate CI columns 
# results <- buying_tidy %>%
#   mutate(
#     estimate = estimate * 100,
#     se = se * 100,
#     lower = estimate - 1.96 * se,
#     upper = estimate + 1.96 * se
#   )
# 
# # Create a reference row for week -5
# ref_row <- tibble(
#   rel_week = -5,
#   estimate = 0,
#   se = 0,
#   lower = 0,
#   upper = 0,
#   search_type = "buying"
# )
# 
# 
# 
# # Bind the new row to your existing results
# results <- bind_rows(results, ref_row)
# 
# # save the tidy table so we can skip feols next time
# write_csv(results, buying_below_median_path)
# 
# max_y <- max(results$estimate, na.rm = TRUE)
# 
# # Plot Buying
# buying_plot <- ggplot(
#   results %>% filter(search_type == "buying"),
#   aes(x = rel_week, y = estimate)
# ) +
#   geom_ribbon(aes(ymin = lower, ymax = upper), fill = "#6BAED6", alpha = 0.4) +
#   geom_line(color = "#08306B", linewidth = 1.2) +
#   geom_vline(xintercept = 0, linetype = "dashed", color = "black", linewidth = 1) +
#   geom_hline(yintercept = 0, linetype = "dashed", linewidth = 1) +
#   annotate(
#     "text",
#     x = 6,
#     y = max_y + 0.05,
#     label = "First Plot Construction start\n Week ",
#     vjust = 0,
#     size = 4,
#     fontface = "bold"
#   ) +
#   labs(
#     x = "Weeks",
#     y = "% change in searches "
#   ) +
#   scale_x_continuous(
#     breaks = sort(unique(c(-26, -5, 0, seq(-20, 40, by = 5), 44)))
#   ) +
#   scale_y_continuous(
#     breaks = seq(-1, 5, by = 0.5)
#   ) +
#   theme_classic() +
#   theme(
#     plot.title   = element_text(face = "bold", size = 21, hjust = 0.5),
#     axis.title.x = element_text(face = "bold", size = 15),
#     axis.title.y = element_text(face = "bold", size = 15),
#     axis.text.x  = element_text(face = "bold", size = 16),
#     axis.text.y  = element_text(face = "bold", size = 16),
#     axis.line    = element_line(size = 1.3, color = "black"),
#     axis.ticks   = element_line(size = 1.3, color = "black"),
#     panel.grid   = element_blank()
#   )
# print(buying_plot)
# 
# # #  Buying plot
# ggsave(
#   filename = file.path(fig_dir, "below_median_nonbots_all_sd_filtered_pooled_buying.png"),
#   plot = buying_plot,
#   width = 18, height = 7, dpi = 300
# )
# 
# 
# ######################################################################################################
# # Running a version only on treated areas that fall ABOVE the median of searches pre-treatment
# ######################################################################################################
# 
# ###############################################################
# # Keep shocks whose treated areas are all high-search (above-median)
# # Baseline = mean buying searches pre-treatment, treated areas only
# ###############################################################
# 
# # keep shocks where ALL treated areas are high-search (above median)
# keep_sites_above <- site_share %>%
#   filter(share_below == 0) %>%
#   pull(construction_site_id)
# 
# cat("Sites kept (above median):", length(keep_sites_above), "of", nrow(site_share), "\n")
# 
# # average pre-treatment searches for treated areas in those shocks
# summary_above <- stacked_df_updated %>%
#   filter(Group == "Treat", rel_yw < 0, construction_site_id %in% keep_sites_above) %>%
#   summarise(avg_pre_searches = mean(buying_searches))
# 
# # keep the whole stack (treated + control) for those shocks
# stacked_df_reg_above <- stacked_df_updated %>%
#   filter(construction_site_id %in% keep_sites_above)
# 
# ##############################################
# # From here on, identical to the original code
# ##############################################
# 
# stacked_df_reg_above <- stacked_df_reg_above %>%
#   mutate(across(starts_with("Treated_"), as.logical)) %>%
#   select(-construction_site_id, -oa_code, -year, -week,
#          -assigned_lsoa, -assigned_msoa, -assigned_la, -assigned_ttwa, -Group)
# gc()
# 
# stacked_df_reg_above <- stacked_df_reg_above %>%
#   select(-buying_searches, -letting_searches, -site_size, -rel_yw, -ln_letting_searches)
# gc()
# 
# cat("Buying regression rows (stacked_df_reg_above):", nrow(stacked_df_reg_above), "\n")
# 
# # Dummy names
# treat_vars <- stacked_df_reg_above %>% select(starts_with("Treated_")) %>% names()
# 
# # Formula
# fml_buying <- as.formula(paste0(
#   "ln_buying_searches ~ ", paste(treat_vars, collapse = " + "),
#   " | oa_stack_id + shockweek_id"
# ))
# 
# setFixest_nthreads(20)
# 
# buying_res <- feols(fml_buying, data = stacked_df_reg_above, cluster = ~oa_stack_id)
# 
# buying_tidy <- tidy(buying_res) %>%
#   filter(str_detect(term, "^Treated_")) %>%
#   select(term, estimate, std.error)
# 
# rm(buying_res); gc()
# 
# buying_tidy <- buying_tidy %>%
#   mutate(
#     term_clean = str_remove_all(term, "Treated_|TRUE|FALSE"),
#     rel_week = case_when(
#       str_detect(term_clean, "^m") ~ -as.integer(str_remove(term_clean, "^m")),
#       TRUE ~ as.integer(term_clean)
#     ),
#     se = std.error,
#     search_type = "buying"
#   ) %>%
#   select(rel_week, estimate, se, search_type) %>%
#   arrange(rel_week)
# 
# results <- buying_tidy %>%
#   mutate(
#     estimate = estimate * 100,
#     se       = se * 100,
#     lower    = estimate - 1.96 * se,
#     upper    = estimate + 1.96 * se
#   )
# 
# ref_row <- tibble(rel_week = -5, estimate = 0, se = 0,
#                   lower = 0, upper = 0, search_type = "buying")
# results <- bind_rows(results, ref_row)
# 
# # save the tidy table (separate path so it doesn't overwrite below-median)
# write_csv(results, buying_above_median_path)
# 
# max_y <- max(results$estimate, na.rm = TRUE)
# 
# # Plot Buying
# buying_plot <- ggplot(
#   results %>% filter(search_type == "buying"),
#   aes(x = rel_week, y = estimate)
# ) +
#   geom_ribbon(aes(ymin = lower, ymax = upper), fill = "#6BAED6", alpha = 0.4) +
#   geom_line(color = "#08306B", linewidth = 1.2) +
#   geom_vline(xintercept = 0, linetype = "dashed", color = "black", linewidth = 1) +
#   geom_hline(yintercept = 0, linetype = "dashed", linewidth = 1) +
#   annotate(
#     "text",
#     x = 6,
#     y = max_y + 0.05,
#     label = "First Plot Construction start\n Week ",
#     vjust = 0,
#     size = 4,
#     fontface = "bold"
#   ) +
#   labs(
#     x = "Weeks",
#     y = "% change in searches "
#   ) +
#   scale_x_continuous(
#     breaks = sort(unique(c(-26, -5, 0, seq(-20, 40, by = 5), 44)))
#   ) +
#   scale_y_continuous(
#     breaks = seq(-1, 5, by = 0.5)
#   ) +
#   theme_classic() +
#   theme(
#     plot.title   = element_text(face = "bold", size = 21, hjust = 0.5),
#     axis.title.x = element_text(face = "bold", size = 15),
#     axis.title.y = element_text(face = "bold", size = 15),
#     axis.text.x  = element_text(face = "bold", size = 16),
#     axis.text.y  = element_text(face = "bold", size = 16),
#     axis.line    = element_line(size = 1.3, color = "black"),
#     axis.ticks   = element_line(size = 1.3, color = "black"),
#     panel.grid   = element_blank()
#   )
# print(buying_plot)
# 
# ggsave(
#   filename = file.path(fig_dir, "above_median_nonbots_all_sd_filtered_pooled_buying.png"),
#   plot = buying_plot,
#   width = 18, height = 7, dpi = 300
# )
# 
# 
# 
# 
# 
# 
# 
# ###############################################################
# ###############################################################
# # Running a version only on shocks that hit New, Rural Developments
# ###############################################################
# ###############################################################
# 
# # ###############################################################
# # # Identify shocks whose treated OAs are ALL new rural developments
# # ###############################################################
# # 
# # # treated OAs per shock (reuses `baseline` from the median blocks)
# # site_class <- baseline %>%
# #   select(construction_site_id, oa_code) %>%
# #   left_join(oa_class, by = "oa_code") %>%
# #   group_by(construction_site_id) %>%
# #   summarise(
# #     n_treated_oas   = n(),
# #     n_unmatched     = sum(is.na(classification)),
# #     share_new_rural = mean(classification == "new rural development", na.rm = TRUE),
# #     .groups = "drop"
# #   )
# # 
# # # how many sites are all / none / mixed
# # site_class %>%
# #   mutate(category = case_when(
# #     share_new_rural == 1 ~ "all OAs new rural",
# #     share_new_rural == 0 ~ "no OAs new rural",
# #     TRUE                 ~ "mixed"
# #   )) %>%
# #   count(category)
# # 
# # # keep shocks where all treated OAs are new rural developments
# # keep_sites_new_rural <- site_class %>%
# #   filter(share_new_rural == 1, n_unmatched == 0) %>%
# #   pull(construction_site_id)
# # cat("Sites kept (new rural):", length(keep_sites_new_rural),
# #     "of", nrow(site_class), "\n")
# 
# ###############################################################
# # Identify shocks where ALL OAs (treated AND control) are
# # new rural developments
# ###############################################################
# 
# # every OA in each stack, regardless of Group
# site_oas <- stacked_df_updated %>%
#   distinct(construction_site_id, oa_code, Group)
# 
# site_class <- site_oas %>%
#   left_join(oa_class, by = "oa_code") %>%
#   group_by(construction_site_id) %>%
#   summarise(
#     n_oas           = n(),
#     n_treated_oas   = sum(Group == "Treat"),
#     n_control_oas   = sum(Group != "Treat"),
#     share_new_rural = mean(classification == "new rural development", na.rm = TRUE),
#     # useful to see the two sides separately
#     share_new_rural_treat   = mean(classification[Group == "Treat"] == "new rural development", na.rm = TRUE),
#     share_new_rural_control = mean(classification[Group != "Treat"] == "new rural development", na.rm = TRUE),
#     .groups = "drop"
#   )
# 
# # how many sites are all / none / mixed (now across the whole stack)
# site_class %>%
#   mutate(category = case_when(
#     share_new_rural == 1 ~ "all OAs new rural",
#     share_new_rural == 0 ~ "no OAs new rural",
#     TRUE                 ~ "mixed"
#   )) %>%
#   count(category)
# 
# # keep shocks where EVERY OA in the stack is a new rural development
# keep_sites_new_rural <- site_class %>%
#   filter(share_new_rural == 1) %>%
#   pull(construction_site_id)
# 
# cat("Sites kept (both control and treate are new rural):", length(keep_sites_new_rural),
#     "of", nrow(site_class), "\n")
# 
# 
# 
# # average pre-treatment searches for treated areas in those shocks
# summary_new_rural <- stacked_df_updated %>%
#   filter(Group == "Treat", rel_yw < 0,
#          construction_site_id %in% keep_sites_new_rural) %>%
#   summarise(avg_pre_searches = mean(buying_searches))
# 
# # average pre treatmenr searches per km2
# baseline_new_rural <- stacked_df_updated %>%
#   filter(Group == "Treat", rel_yw < 0,
#          construction_site_id %in% keep_sites_new_rural) %>%
#   left_join(oa_area, by = "oa_code") %>%
#   mutate(searches_per_km2 = buying_searches / area_km2) %>%
#   summarise(mean_searches_per_km2 = mean(searches_per_km2, na.rm = TRUE))
# 
# 
# 
# # keep the whole stack (treated + control) for those shocks
# stacked_df_reg_new_rural <- stacked_df_updated %>%
#   filter(construction_site_id %in% keep_sites_new_rural)
# 
# # get the average number of controls per stack
# control_counts_new_rural <- stacked_df_reg_new_rural %>%
#   filter(Group != "Treat") %>%
#   distinct(construction_site_id, oa_code) %>%
#   count(construction_site_id, name = "n_control_oas")
# 
# mean(control_counts_new_rural$n_control_oas)
# 
# ##############################################
# # From here on, identical to the original code
# ##############################################
# 
# stacked_df_reg_new_rural <- stacked_df_reg_new_rural %>%
#   mutate(across(starts_with("Treated_"), as.logical))
# gc()
# 
# # stack-level site size from the treated rows (guard against 0 / NA there too)
# site_size_lookup <- stacked_df_reg_new_rural %>%
#   filter(Group == "Treat", !is.na(site_size), site_size > 0) %>%
#   distinct(construction_site_id, site_size)
# 
# 
# # overwrite for ALL rows in the stack, treated and control alike
# stacked_df_reg_new_rural <- stacked_df_reg_new_rural %>%
#   select(-site_size) %>%
#   left_join(site_size_lookup, by = "construction_site_id") %>%
#   filter(!is.na(site_size)) %>%
#   mutate(searches_per_unit = buying_searches / site_size)
# 
# 
# cat("Buying regression rows (stacked_df_reg_new_rural):",
#     nrow(stacked_df_reg_new_rural), "\n")
# 
# # Dummy names
# treat_vars <- stacked_df_reg_new_rural %>% select(starts_with("Treated_")) %>% names()
# 
# # Formula
# fml_buying <- as.formula(paste0(
#   "buying_searches ~ ", paste(treat_vars, collapse = " + "),
#   " | oa_stack_id + shockweek_id"
# ))
# 
# setFixest_nthreads(20)
# 
# 
# # run regression
# buying_res <- feols(fml_buying, data = stacked_df_reg_new_rural, cluster = ~oa_stack_id)
# 
# 
# #########################
# # Tidy up
# #########################
# 
# buying_tidy <- tidy(buying_res) %>%
#   filter(str_detect(term, "^Treated_")) %>%
#   select(term, estimate, std.error)
# 
# buying_tidy <- buying_tidy %>%
#   mutate(
#     term_clean = str_remove_all(term, "Treated_|TRUE|FALSE"),
#     rel_week = case_when(
#       str_detect(term_clean, "^m") ~ -as.integer(str_remove(term_clean, "^m")),
#       TRUE ~ as.integer(term_clean)
#     ),
#     se = std.error,
#     search_type = "buying"
#   ) %>%
#   select(rel_week, estimate, se, search_type) %>%
#   arrange(rel_week)
# 
# results <- buying_tidy %>%
#   mutate(
#     estimate = estimate ,
#     se       = se,
#     lower    = estimate - 1.96 * se,
#     upper    = estimate + 1.96 * se
#   )
# 
# ref_row <- tibble(rel_week = -5, estimate = 0, se = 0,
#                   lower = 0, upper = 0, search_type = "buying")
# results <- bind_rows(results, ref_row)
# 
# # # save results to csv
# # write_csv(results, buying_new_rural_path)
# 
# max_y <- max(results$estimate, na.rm = TRUE)
# 
# # Plot Buying
# buying_plot <- ggplot(
#   results %>% filter(search_type == "buying"),
#   aes(x = rel_week, y = estimate)
# ) +
#   geom_ribbon(aes(ymin = lower, ymax = upper), fill = "#6BAED6", alpha = 0.4) +
#   geom_line(color = "#08306B", linewidth = 1.2) +
#   geom_vline(xintercept = 0, linetype = "dashed", color = "black", linewidth = 1) +
#   geom_hline(yintercept = 0, linetype = "dashed", linewidth = 1) +
#   annotate(
#     "text",
#     x = 6,
#     y = max_y + 0.05,
#     label = "First Plot Construction start\n Week ",
#     vjust = 0,
#     size = 4,
#     fontface = "bold"
#   ) +
#   labs(
#     x = "Weeks",
#     y = "Searches "
#   ) +
#   scale_x_continuous(
#     breaks = sort(unique(c(-26, -5, 0, seq(-20, 40, by = 5), 44)))
#   ) +
#   theme_classic() +
#   theme(
#     plot.title   = element_text(face = "bold", size = 21, hjust = 0.5),
#     axis.title.x = element_text(face = "bold", size = 15),
#     axis.title.y = element_text(face = "bold", size = 15),
#     axis.text.x  = element_text(face = "bold", size = 16),
#     axis.text.y  = element_text(face = "bold", size = 16),
#     axis.line    = element_line(size = 1.3, color = "black"),
#     axis.ticks   = element_line(size = 1.3, color = "black"),
#     panel.grid   = element_blank()
#   )
# print(buying_plot)
# 
# ggsave(
#   filename = file.path(fig_dir, "new_rural_per_unit_nonbots_all_sd_filtered_pooled_buying.png"),
#   plot = buying_plot,
#   width = 18, height = 7, dpi = 300
# )
# 
# 
# # ############################################################
# # # Rebuild new-rural stacks with a COMMON rural control pool (Rural OAs that are never hit by any supply shock ever)
# # ############################################################
# # 
# # # --- 1. treated rows from the qualifying stacks (keep as-is) -------------
# # treated_rows <- stacked_df_updated %>%
# #   filter(construction_site_id %in% keep_sites_new_rural, Group == "Treat")
# # 
# # treat_vars <- treated_rows %>% select(starts_with("Treated_")) %>% names()
# # 
# # # --- 2. each stack's calendar-week -> rel_yw mapping ---------------------
# # stack_grid <- treated_rows %>%
# #   distinct(construction_site_id, year, week, rel_yw)
# # 
# # # --- 3. rural control pool: rural OAs never treated in any stack ---------
# # ever_treated <- stacked_df_updated %>%
# #   filter(Group == "Treat") %>%
# #   distinct(oa_code) %>%
# #   pull(oa_code)
# # 
# # rural_control_oas <- oa_class %>%
# #   filter(classification == "new rural development",
# #          !oa_code %in% ever_treated) %>%
# #   distinct(oa_code)
# # 
# # cat("Rural control OAs:", nrow(rural_control_oas),
# #     "| stacks:", length(keep_sites_new_rural),
# #     "| weeks/stack:", n_distinct(stack_grid$year, stack_grid$week), "\n")
# # 
# # # --- 4. searches for those OAs (re-read; all_searches was rm'd) ----------
# # ctrl_searches <- read_parquet(all_searches_path) %>%
# #   mutate(week = if_else(week == 53L, 52L, week)) %>%
# #   semi_join(rural_control_oas, by = "oa_code") %>%
# #   group_by(oa_code, year, week) %>%
# #   summarise(buying_searches = sum(buying_searches, na.rm = TRUE), .groups = "drop")
# # 
# # # --- 5. cross control OAs with every stack's week grid -------------------
# # control_rows <- stack_grid %>%
# #   cross_join(rural_control_oas) %>%
# #   inner_join(ctrl_searches, by = c("oa_code", "year", "week")) %>%
# #   mutate(
# #     Group             = "Control",
# #     ln_buying_searches = log(buying_searches),
# #     oa_stack_id       = paste0(oa_code, "_", construction_site_id),
# #     shockweek_id      = paste0(construction_site_id, "_", year, "_", week)
# #   )
# # 
# # # all treatment dummies are FALSE for controls
# # control_rows[treat_vars] <- FALSE
# # 
# # # --- 6. bind into one regression frame ----------------------------------
# # keep_cols <- c("oa_code", "construction_site_id", "rel_yw", "Group",
# #                "ln_buying_searches", "oa_stack_id", "shockweek_id", treat_vars)
# # 
# # reg_new_rural_pool <- bind_rows(
# #   treated_rows %>% mutate(across(all_of(treat_vars), as.logical)) %>% select(all_of(keep_cols)),
# #   control_rows %>% select(all_of(keep_cols))
# # ) %>%
# #   filter(is.finite(ln_buying_searches))
# # 
# # cat("Rows:", nrow(reg_new_rural_pool),
# #     "| treated OA-stacks:", n_distinct(reg_new_rural_pool$oa_stack_id[reg_new_rural_pool$Group == "Treat"]),
# #     "\n")
# # 
# # # --- 7. estimate --------------------------------------------------------
# # fml_buying <- as.formula(paste0(
# #   "ln_buying_searches ~ ", paste(treat_vars, collapse = " + "),
# #   " | oa_stack_id + shockweek_id"
# # ))
# # 
# # setFixest_nthreads(20)
# # buying_res <- feols(fml_buying, data = reg_new_rural_pool, cluster = ~oa_code)
# # 
# # #########################
# # # Tidy up
# # #########################
# # 
# # buying_tidy <- tidy(buying_res) %>%
# #   filter(str_detect(term, "^Treated_")) %>%
# #   select(term, estimate, std.error)
# # 
# # buying_tidy <- buying_tidy %>%
# #   mutate(
# #     term_clean = str_remove_all(term, "Treated_|TRUE|FALSE"),
# #     rel_week = case_when(
# #       str_detect(term_clean, "^m") ~ -as.integer(str_remove(term_clean, "^m")),
# #       TRUE ~ as.integer(term_clean)
# #     ),
# #     se = std.error,
# #     search_type = "buying"
# #   ) %>%
# #   select(rel_week, estimate, se, search_type) %>%
# #   arrange(rel_week)
# # 
# # results <- buying_tidy %>%
# #   mutate(
# #     estimate = estimate * 100,
# #     se       = se * 100,
# #     lower    = estimate - 1.96 * se,
# #     upper    = estimate + 1.96 * se
# #   )
# # 
# # ref_row <- tibble(rel_week = -5, estimate = 0, se = 0,
# #                   lower = 0, upper = 0, search_type = "buying")
# # results <- bind_rows(results, ref_row)
# # 
# # # save results to csv
# # write_csv(results, buying_new_rural_path)
# # 
# # max_y <- max(results$estimate, na.rm = TRUE)
# # 
# # # Plot Buying
# # buying_plot <- ggplot(
# #   results %>% filter(search_type == "buying"),
# #   aes(x = rel_week, y = estimate)
# # ) +
# #   geom_ribbon(aes(ymin = lower, ymax = upper), fill = "#6BAED6", alpha = 0.4) +
# #   geom_line(color = "#08306B", linewidth = 1.2) +
# #   geom_vline(xintercept = 0, linetype = "dashed", color = "black", linewidth = 1) +
# #   geom_hline(yintercept = 0, linetype = "dashed", linewidth = 1) +
# #   annotate(
# #     "text",
# #     x = 6,
# #     y = max_y + 0.05,
# #     label = "First Plot Construction start\n Week ",
# #     vjust = 0,
# #     size = 4,
# #     fontface = "bold"
# #   ) +
# #   labs(
# #     x = "Weeks",
# #     y = "% change in searches "
# #   ) +
# #   scale_x_continuous(
# #     breaks = sort(unique(c(-26, -5, 0, seq(-20, 40, by = 5), 44)))
# #   ) +
# #   theme_classic() +
# #   theme(
# #     plot.title   = element_text(face = "bold", size = 21, hjust = 0.5),
# #     axis.title.x = element_text(face = "bold", size = 15),
# #     axis.title.y = element_text(face = "bold", size = 15),
# #     axis.text.x  = element_text(face = "bold", size = 16),
# #     axis.text.y  = element_text(face = "bold", size = 16),
# #     axis.line    = element_line(size = 1.3, color = "black"),
# #     axis.ticks   = element_line(size = 1.3, color = "black"),
# #     panel.grid   = element_blank()
# #   )
# # print(buying_plot)
# 
# ###########################################################
# # Pre-treatment searches per km2 ??? new rural sample
# ############################################################
# 
# # OA areas in km2
# oa_area <- output_areas %>%
#   st_transform(27700) %>%
#   mutate(area_km2 = as.numeric(st_area(.)) / 1e6) %>%
#   st_drop_geometry() %>%
#   select(oa_code, area_km2)
# 
# 
# baseline_new_rural <- stacked_df_updated %>%
#   filter(Group == "Treat", rel_yw < 0,
#          construction_site_id %in% keep_sites_new_rural) %>%
#   left_join(oa_area, by = "oa_code") %>%
#   mutate(searches_per_km2 = buying_searches / area_km2) %>%
#   summarise(mean_searches_per_km2 = mean(searches_per_km2, na.rm = TRUE))
# 
# # get average Rurual treated OA size
# avg_treated_oa_size <- stacked_df_updated %>%
#   filter(Group == "Treat", rel_yw < 0,
#          construction_site_id %in% keep_sites_new_rural) %>%
#   left_join(oa_area, by = "oa_code") %>% 
#   distinct(oa_code, area_km2) %>%
#   summarise(
#     n_oas       = n(),
#     avg_oa_area = mean(area_km2)
#   )
# oa_area_treated <- stacked_df_updated %>%
#   filter(Group == "Treat", rel_yw < 0,
#          construction_site_id %in% keep_sites_new_rural) %>%
#   distinct(oa_code) %>%
#   left_join(oa_area, by = "oa_code")










#############################################################
#############################################################
# Introducing transactions
##############################################################
##############################################################

##################################################
# Transactions: clean and assign to OA-year-week
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

# pre-period transactions per treated OA: weekly average AND overall total
baseline_tx_overall <- reg_df %>%
  filter(rel_yw < 0, Group == "Treat") %>%
  group_by(construction_site_id, oa_code) %>%
  summarise(
    baseline_tx    = mean(n_transactions),   # weekly average (as before)
    total_pre_tx   = sum(n_transactions),    # overall count across the pre-period
    .groups = "drop"
  )

# averages across treated OAs
mean(baseline_tx_overall$baseline_tx)    # avg weekly transactions
mean(baseline_tx_overall$total_pre_tx)   # avg total transactions over the pre-period