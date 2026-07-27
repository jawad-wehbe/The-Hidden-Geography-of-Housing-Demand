
library(sf)
library(dplyr)
library(ggplot2)
library(readr)
library(janitor)  
library(ggmap)
library(arrow)
library(lubridate)
library(scales)
library(tidyr)
library(fixest)
library(broom)
library(future)
library(furrr)
library(progressr)
library(future.callr)
library(future.apply)
library(readr)
library(stringr)
library(duckdb)
library(DBI)
library(leaflet)
library(fixest)
library(future.apply)
library(ISOweek)
library(multcomp)


# CLEAR ALL 
rm(list = ls())
gc()


############
# Paths
############

oa_path <- "/home/jawad/Desktop/Raw_Data/Shapefiles etc/output_areas_2021.gpkg"

weekly_path <- "~/Desktop/Projects/housing_targets/produced/nature/nonbots/saved_or_contacted/oa_weekly_search_with_geos.parquet"

duckdb_path <- "/home/jawad/Desktop/Projects/housing_targets/temp/nature/duckcb_greenspace.duckdb"

temp_path <- "/home/jawad/Desktop/Projects/housing_targets/temp/nature/"


fig_dir <-"~/Desktop/Projects/housing_targets/output/figures/nature/nonbots/saved_or_contacted/"

spill_dir <- "/home/jawad/Desktop/Projects/housing_targets/temp/nature/spill_dir/"

dataset_path <- "/home/jawad/Desktop/Projects/housing_targets/temp/nature/searches_greenspace.parquet"

weekly_reg_dataset_path <- "~/Desktop/Projects/housing_targets/produced/nature/nonbots/saved_or_contacted/greenspace_weekly_reg_dataset.parquet"

results_path <- "~/Desktop/Projects/housing_targets/produced/nature/nonbots/saved_or_contacted/saved_or_contacted_results_greenspace_weekly.csv"

######################
# Reading other data in
#######################

# weekly searches
weekly_searches <- read_parquet(weekly_path) %>% filter(week != 53) 

# OA

oa <- st_read(oa_path)


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

summary_stats <- data.frame(
  p1  = quantile(x, 0.01, na.rm = TRUE),
  p5  = quantile(x, 0.05, na.rm = TRUE),
  p10 = quantile(x, 0.10, na.rm = TRUE),
  p25 = quantile(x, 0.25, na.rm = TRUE),
  p50 = quantile(x, 0.50, na.rm = TRUE),
  p75 = quantile(x, 0.75, na.rm = TRUE),
  p90 = quantile(x, 0.90, na.rm = TRUE),
  p95 = quantile(x, 0.95, na.rm = TRUE),
  p99 = quantile(x, 0.99, na.rm = TRUE),
  mean = mean(x, na.rm = TRUE),
  sd = sd(x, na.rm = TRUE)
)

#  Plot histogram 
ggplot(greenspace_df, aes(x = median_avg_greenspace_m2)) +
  geom_histogram(binwidth = 100, colour = "black", fill = "blue") +     
  scale_x_continuous(labels = comma_format(suffix = " m2")) +
  labs(
    x     = "Median greenspace per OA",
    y     = "Number of Output Areas"
  ) +
  theme_classic()


# disconnect
dbDisconnect(con, shutdown = TRUE)
rm()
####################################################################################
# Regression preparation (USING BINARY VARIABE, SCROLL DOWN FOR CONTINIOUS VARIABLE)
####################################################################################

# add binary greenspace
greenspace_df <- greenspace_df %>%
  mutate(
  has_greenspace = if_else(median_avg_greenspace_m2 > 10, 1, 0 )
  )

week_lookup <- weekly_searches %>%
  distinct(year, week) %>%
  arrange(year, week) %>%
  mutate(time_id = row_number())

# attach time id
weekly_searches <- weekly_searches %>%
  inner_join(week_lookup, by = c("year", "week"))


# attach greenspace
weekly_searches_greenspace <- weekly_searches %>%
  inner_join(greenspace_df, by = "oa_code")


# reference week (Last week of february)
ref_time_id <- week_lookup %>%
  filter(year == 2020, week == 9) %>%
  pull(time_id)

weekly_searches_greenspace <- weekly_searches_greenspace %>%
  mutate(rel_week = time_id - ref_time_id)


# filter to 4 months pre and 2 years post
weekly_searches_greenspace_filtered <- weekly_searches_greenspace # %>%
 # filter(rel_week >= -54 & rel_week <= 104)


weekly_searches_greenspace_filtered <- weekly_searches_greenspace_filtered %>%
  filter(year < 2024) # remove the last 5 months window just to run faster

# make outcome variables in logs
weekly_searches_greenspace_filtered <- weekly_searches_greenspace_filtered %>%
  mutate(
    log_buying_searches = log(buying_searches),
    ttwa_yw_id = paste0(assigned_ttwa, "_", year, "_", week), # for FE
    msoa_yw_id = paste0(assigned_msoa, "_", year, "_", week),
    msoa_week_id = paste0(assigned_msoa, "_", week),
    lsoa_week_id = paste0(assigned_lsoa, "_", week),
    la_yw_id = paste0(assigned_la, "_", year, "_", week),
    oa_week = paste0(oa_code, "_", week),
    yw = paste(year, "_", week),
    greenspace_week = paste0(week, "_", has_greenspace)
  )


# save dataset

write_parquet(weekly_searches_greenspace_filtered, weekly_reg_dataset_path)

# run regression (USING CONTINIOUS GREENSPACE)

setFixest_nthreads(20)

est <- feols(
  log_buying_searches ~ i(rel_week, median_avg_greenspace_m2, ref = -1) | ttwa_yw_id + lsoa_week_id + oa_code, 
  data = weekly_searches_greenspace_filtered,
  cluster = ~oa_code
)

gc()

#######################
# Tidy up
#######################

tidy_est <- tidy(est, conf.int = TRUE)

# keep only interaction terms
event_df <- tidy_est %>%
  filter(str_detect(term, "rel_week::") &
           str_detect(term, "median_avg_greenspace_m2")) %>%
  mutate(
    rel_week = as.integer(str_extract(term, "-?\\d+"))
  )



# rename confidence interval
event_df <- event_df %>%
  mutate(
    estimate = estimate * 100 *100, # we use twice multiplication to make it percentage and then per 100 m2
    lower = conf.low * 100 *100,
    upper = conf.high * 100 *100
  ) %>%
  dplyr::select(estimate, rel_week, lower, upper)


# save results 

 write_csv(event_df,results_path)

 # add reference week
ref_row <- tibble(
  rel_week = -1,
  estimate = 0,
  lower = 0,
  upper = 0
)

# bind the reference week
event_df <- bind_rows(event_df, ref_row)

# arrange
event_df <- event_df %>%
  arrange(rel_week)


# plot results
lol <- ggplot(event_df, aes(x = rel_week, y = estimate)) +
  
  geom_ribbon(
    aes(ymin = lower, ymax = upper),
    fill = "#6BAED6",
    alpha = 0.4
  ) +
  
  geom_line(color = "#08306B", linewidth = 1.2) +
  
  geom_vline(xintercept = 0, linetype = "dashed", linewidth = 1) +
  
  geom_hline(yintercept = 0, linetype = "dashed", linewidth = 1) +
  
  labs(
    x = "Weeks",
    y = "% change in searches\n per 100m² greenspace"
  ) +
  
  scale_x_continuous(
    breaks = seq(-60, 201, by = 20)
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

# print
lol

# save
ggsave(
  filename = file.path(fig_dir, "nonbots_saved_or_contacted_searches_greenspace_event_study_plot_cont_treat_oafe_ttwaxywfe_lsoaxweekfe.png"),
  plot = lol, width = 18, height = 7, units = "in", dpi = 300
)
gc()

#############################
# Some pre treatment stats
############################
summary <- weekly_searches_greenspace_filtered %>%
  filter(rel_week < 0) %>%
  summarise(
    avg_searches = mean(buying_searches),
    .groups = 'drop'
  )
