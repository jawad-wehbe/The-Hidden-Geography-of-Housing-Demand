library(here)
library(dplyr)
library(readr)
library(ggplot2)
library(scales)

rm(list = ls())
source(file.path(here(), "config.R"))   # all data roots come from config.R (real or demo mode)
gc()

# --- Load data -----------------------------------------------------------
oa_gap <- read_csv(file.path(project_root, "produced/gap/oa_la_combined_stats_2024.csv"), show_col_types = FALSE)

oa_prices <- read_csv(file.path(project_root, "produced/gap/oa_map_variables.csv"), show_col_types = FALSE) %>%
  select(oa_code, avg_rental_price, avg_buying_price) %>%
  distinct()   # 13 OAs straddle two LAs and appear twice with the same values

fig_dir <- file.path(project_root, "output/figures/hidden_geography_of_housing_demand/descriptives/")
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)

# --- Merge gap and prices ------------------------------------------------
merged <- oa_gap %>%
  select(oa_code, gap_per_km2) %>%
  distinct() %>%   # same 13 OAs, one row each
  left_join(oa_prices, by = "oa_code")

# --- Plots ---------------------------------------------------------------

# Rental price vs GAP
p1_rental <- ggplot(merged, aes(x = gap_per_km2, y = avg_rental_price)) +
  geom_point(alpha = 0.4, size = 1) +
  scale_y_continuous(labels = comma) +
  scale_x_continuous(labels = comma) +
  labs(
    title = "Rental Price vs Gap per km²",
    x = "Gap per km²",
    y = "Average Rental Price (£)"
  ) +
  theme_bw()

ggsave(
  filename = "rental_price_vs_gap.png",
  plot = p1_rental,
  path = fig_dir,
  width = 8, height = 6, dpi = 300
)

# Sales price vs GAP
p2_sales <- ggplot(merged, aes(x = gap_per_km2, y = avg_buying_price)) +
  geom_point(alpha = 0.4, size = 1) +
  scale_y_continuous(labels = comma) +
  scale_x_continuous(labels = comma) +
  labs(
    title = "Sales Price vs Gap per km²",
    x = "Gap per km²",
    y = "Average Sales Price (£)"
  ) +
  theme_bw()

ggsave(
  filename = "sales_price_vs_gap.png",
  plot = p2_sales,
  path = fig_dir,
  width = 8, height = 6, dpi = 300
)

# --- Binned means: buying price vs GAP, 50 quantile bins (commented out) ----
# binned <- merged %>%
#   mutate(x_bin = ntile(gap_per_km2, 50)) %>%
#   group_by(x_bin) %>%
#   summarise(
#     gap_bin_mid = mean(gap_per_km2, na.rm = TRUE),
#     avg_price   = mean(avg_buying_price, na.rm = TRUE),
#     .groups = "drop"
#   )
# 
# p_binscatter <- ggplot(binned, aes(x = gap_bin_mid, y = avg_price)) +
#   geom_point(color = "blue") +
#   geom_line(color = "blue") +
#   scale_y_continuous(labels = comma) +
#   scale_x_continuous(labels = comma) +
#   labs(
#     title = "Buying Price (2024) vs Gap per km² (Binned Means)",
#     x = "Gap per km²",
#     y = "Average Buying Price (£)"
#   ) +
#   theme_minimal()
# 
# ggsave(
#   filename = "sales_price_vs_gap_binned.png",
#   plot = p_binscatter,
#   path = fig_dir,
#   width = 8, height = 6, dpi = 300
# )
