###########################################################
# Flood event maps — standalone
#
# Reads the saved weekly regression dataset from the floods
# script, picks one flood shock x local authority (chosen
# from pre/post search variation among treated OAs), and maps
# how OA-level buying searches move around the flood week.
#
# Searches are expressed per km² (divided by OA area). For the
# chosen shock x LA it builds, over weeks -1, 0, +1, +4, +5, +6:
#
#   LEVELS figures — change in searches per km² between two
#     weeks (e.g. week 0 minus week -1, week +1 minus week 0,
#     week +4/+5/+6 vs both week 0 and week -1), diverging
#     red/blue scale centred at 0.
#   LEVELS baseline map — raw searches per km² in week -1.
#   LOG %-CHANGE figures — 100*(log wk_a - log wk_b) for the
#     same week pairs, each on its own 1st/99th-percentile
#     winsorized diverging scale.
#
# Each map overlays: treated (flood-exposed) OA boundaries in
# purple, and one black dot per real HMLR transaction in the
# relevant week. Transactions are geocoded from postcodes via
# ONSPD, assigned to OAs spatially, and tagged to a rel_week by
# joining their selling year-week to the event window.
############################################################

library(sf)
library(dplyr)
library(tidyr)
library(ggplot2)
library(arrow)
library(readr)
library(stringr)
library(lubridate)
library(scales)

rm(list = ls())
gc()

###################
# Paths
###################

reg_dataset_weekly_path <- "~/Desktop/Projects/housing_targets/produced/nature/nonbots/regression_datasets/floods_weekly_reg_dataset_complete.parquet"

oa_path <- "/home/jawad/Desktop/Raw_Data/Shapefiles etc/output_areas_2021.gpkg"

cw_dir  <- "~/Desktop/Raw_Data/Shapefiles etc/Crosswalks/"

fig_dir <- "/home/jawad/Desktop/Projects/housing_targets/output/figures/nature/nonbots/maps/"

transactions_path <- "/home/jawad/Desktop/Raw_Data/HMLR/pp-complete.csv"

postcode_to_coord_path <- "/home/jawad/Desktop/Raw_Data/Shapefiles etc/ONSPD_FEB_2025/Data/ONSPD_FEB_2025_UK.csv"

###################
# Read the data
###################


# Read OA

oa_area <- st_read(oa_path, quiet = TRUE)

# read saved regression dataset
stacked_data <- read_parquet(reg_dataset_weekly_path)

# assign each OA one LA
oa_to_la <- read_parquet(file.path(cw_dir, "oa_la.parquet")) %>%
  group_by(oa_code) %>%
  slice_max(share, n = 1, with_ties = FALSE) %>%
  ungroup() %>%
  select(oa_code, assigned_la = la_code)

############################################
# Choose flood shock and LA
############################################

# pre/post search variation, treated OAs
shock_la_variation <- stacked_data %>%
  filter(Group == "Treat", rel_week >= -4, rel_week <= 4, rel_week != 0) %>%
  inner_join(oa_to_la, by = "oa_code") %>%
  mutate(period = if_else(rel_week > 0, "post", "pre")) %>%
  group_by(shock_id, assigned_la, period) %>%
  summarise(
    mean_searches = mean(buying_searches, na.rm = TRUE),
    n_treated_oa  = n_distinct(oa_code),
    .groups = "drop"
  ) %>%
  pivot_wider(
    names_from  = period,
    values_from = c(mean_searches, n_treated_oa),
    values_fill = 0
  ) %>%
  mutate(variation = mean_searches_post - mean_searches_pre) %>%
  arrange(desc(abs(variation)))

# manually pick shock and LA
top_shock_la <- shock_la_variation %>%
  filter(assigned_la == "E08000033", shock_id == 2)  # chosen: many OAs affected

chosen_shock <- top_shock_la %>% pull(shock_id)
chosen_la    <- top_shock_la %>% pull(assigned_la)

############################################
# Event panel: shock x LA, weeks -1..+1
############################################

# filter to event window
# filter to event window
event_panel <- stacked_data %>%
  filter(shock_id == chosen_shock, rel_week %in% c(-1, 0, 1, 4, 5, 6)) %>%
  inner_join(oa_to_la, by = "oa_code") %>%
  filter(assigned_la == chosen_la) %>%
  select(oa_code, Group, rel_week, selling_year, selling_week,
         buying_searches, n_transactions) 

# attach OA area
oa_area <- oa_area %>%
  filter(oa_code %in% event_panel$oa_code) %>%
  st_transform(27700) %>%
  mutate(
    area_km2 = as.numeric(st_area(geom)) / 1e6   
  )
# keep relevant columns
oa_area <- oa_area %>%
  st_drop_geometry() %>%
  select(oa_code, area_km2)

# keep OA group labels
oa_group <- event_panel %>% distinct(oa_code, Group)

# year-week to rel_week lookup
week_lookup <- event_panel %>%
  filter(rel_week %in% c(-1, 0, 1, 4, 5, 6)) %>%
  distinct(selling_year, selling_week, rel_week)

############################################
# Log search differences per OA
############################################

# compute weekly level changes
search_diffs <- event_panel %>%
  left_join(oa_area, by = "oa_code") %>%
  mutate(buying_searches = buying_searches / area_km2) %>%   # searches per km2
  mutate(wk = recode(rel_week, `-1` = "wk_m1", `0` = "wk_0", `1` = "wk_p1",
                     `4` = "wk_p4", `5` = "wk_p5", `6` = "wk_p6")) %>%
  select(oa_code, wk, buying_searches) %>%
  pivot_wider(names_from = wk, values_from = buying_searches) %>%
  mutate(
    diff_0_m1 = wk_0  - wk_m1,
    diff_1_0  = wk_p1 - wk_0,
    diff_4_0  = wk_p4 - wk_0,
    diff_4_m1 = wk_p4 - wk_m1,
    diff_5_0  = wk_p5 - wk_0,
    diff_5_m1 = wk_p5 - wk_m1,
    diff_6_0  = wk_p6 - wk_0,
    diff_6_m1 = wk_p6 - wk_m1
  )

############################################
# Geometry: OA polygons for LA
############################################

# read OA polygons, project
oa_sf <- st_read(oa_path) %>%
  filter(oa_code %in% search_diffs$oa_code) %>%
  st_transform(27700)

# attach diffs and groups
oa_map <- oa_sf %>%
  left_join(search_diffs, by = "oa_code") %>%
  left_join(oa_group,     by = "oa_code")

############################################
# Real transaction points, weeks 0 and +1
############################################

# read raw HMLR transactions
transactions <- read_csv(transactions_path, col_names = FALSE) %>%
  rename(id = X1, price = X2, date = X3, postcode = X4) %>%
  select(id, price, date, postcode)

# read postcode coordinate lookup
postcode_lookup <- read_csv(postcode_to_coord_path) %>%
  filter(!is.na(lat), !is.na(long)) %>%
  mutate(postcode_key = str_to_upper(str_remove_all(pcds, "\\s+"))) %>%
  select(postcode_key, lat, long)

# keep only relevant weeks
tx_window <- transactions %>%
  #filter(price > 0) %>%
  mutate(
    selling_year = isoyear(date),
    selling_week = isoweek(date)
  ) %>%
  semi_join(week_lookup, by = c("selling_year", "selling_week"))

# geocode and make spatial
tx_points <- tx_window %>%
  mutate(postcode_key = str_to_upper(str_remove_all(postcode, "\\s+"))) %>%
  inner_join(postcode_lookup, by = "postcode_key") %>%
  st_as_sf(coords = c("long", "lat"), crs = 4326) %>%
  st_transform(27700) %>%
  # assign transactions to LA OAs
  st_join(oa_sf %>% select(oa_code), join = st_intersects, left = FALSE) %>%
  # tag rel_week via year-week
  left_join(week_lookup, by = c("selling_year", "selling_week"))


############################################
# Shared plot settings
############################################

# bounding box: whole LA
la_bbox <- st_bbox(oa_map)

# label for the purple boundary legend
flood_label <- "Flooded areas \n(Storm Ciara, 2020)"

# reusable map plotting function, levels, free scale
plot_diff_map <- function(diff_var, tx_relweek, title,
                          fill_name = "Change in buying searches per km²") {
  ggplot() +
    geom_sf(
      data = oa_map,
      aes(fill = .data[[diff_var]]),
      colour = "grey70", linewidth = 0.15
    ) +
    geom_sf(
      data = oa_map %>% filter(Group == "Treat"),
      aes(colour = flood_label),
      fill = NA, linewidth = 0.6
    ) +
    geom_sf(
      data = tx_points %>% filter(rel_week == tx_relweek),
      colour = "black", alpha = 0.9, size = 2
    ) +
    scale_colour_manual(
      name = NULL,
      values = setNames("purple", flood_label),
      guide = guide_legend(order = 1)
    ) +
    scale_fill_gradient2(
      name = fill_name,
      low = "#2166AC", mid = "grey96", high = "#A50F15",
      midpoint = 0,
      na.value = "grey90",
      guide = guide_colorbar(
        order = 2,
        barheight = unit(4, "cm"),
        barwidth  = unit(0.4, "cm"),
        title.position = "top",
        title.hjust = 0.5
      )
    ) +
    coord_sf(
      xlim = c(la_bbox[["xmin"]], la_bbox[["xmax"]]),
      ylim = c(la_bbox[["ymin"]], la_bbox[["ymax"]]),
      expand = FALSE
    ) +
    theme_void(base_size = 9) +
    theme(
      plot.background = element_rect(fill = "white", colour = NA),
      panel.background = element_rect(fill = "white", colour = NA),
      legend.position = "right",
      legend.key.size = unit(0.8, "cm"),
      legend.text = element_text(size = 18),
      legend.spacing.y = unit(1, "cm"),
      legend.title = element_text(size = 18, face = "bold", margin = margin(b = 10)),
      plot.title = element_text(face = "bold", size = 16, hjust = 0.5),
      plot.caption = element_text(size = 7, hjust = 0.5, colour = "grey40")
    )
}

############################################
# Levels figures
############################################

# figure 1: week 0 vs -1
fig1 <- plot_diff_map("diff_0_m1", tx_relweek = 0, "")
print(fig1)
ggsave(file.path(fig_dir, "flood_map_searchdiff_wk0_vs_wkm1_levels.png"),
       fig1, width = 12, height = 10, units = "in", dpi = 300)

# figure 2: week +1 vs 0
fig2 <- plot_diff_map("diff_1_0", tx_relweek = 1, "")
print(fig2)
ggsave(file.path(fig_dir, "flood_map_searchdiff_wkp1_vs_wk0_levels.png"),
       fig2, width = 12, height = 10, units = "in", dpi = 300)

# figure 4: week +4 vs 0
fig4 <- plot_diff_map("diff_4_0", tx_relweek = 4, "")
print(fig4)
ggsave(file.path(fig_dir, "flood_map_searchdiff_wkp4_vs_wk0_levels.png"),
       fig4, width = 12, height = 10, units = "in", dpi = 300)

# figure 5: week +4 vs -1
fig5 <- plot_diff_map("diff_4_m1", tx_relweek = 4, "")
print(fig5)
ggsave(file.path(fig_dir, "flood_map_searchdiff_wkp4_vs_wkm1_levels.png"),
       fig5, width = 12, height = 10, units = "in", dpi = 300)

# figure 6: week +5 vs 0
fig6 <- plot_diff_map("diff_5_0", tx_relweek = 5, "")
print(fig6)
ggsave(file.path(fig_dir, "flood_map_searchdiff_wkp5_vs_wk0_levels.png"),
       fig6, width = 12, height = 10, units = "in", dpi = 300)

# figure 7: week +5 vs -1
fig7 <- plot_diff_map("diff_5_m1", tx_relweek = 5, "")
print(fig7)
ggsave(file.path(fig_dir, "flood_map_searchdiff_wkp5_vs_wkm1_levels.png"),
       fig7, width = 12, height = 10, units = "in", dpi = 300)

# figure 8: week +6 vs 0
fig8 <- plot_diff_map("diff_6_0", tx_relweek = 6, "")
print(fig8)
ggsave(file.path(fig_dir, "flood_map_searchdiff_wkp6_vs_wk0_levels.png"),
       fig8, width = 12, height = 10, units = "in", dpi = 300)

# figure 9: week +6 vs -1
fig9 <- plot_diff_map("diff_6_m1", tx_relweek = 6, "")
print(fig9)
ggsave(file.path(fig_dir, "flood_map_searchdiff_wkp6_vs_wkm1_levels.png"),
       fig9, width = 12, height = 10, units = "in", dpi = 300)

############################################
# Figure 3: week -1 search LEVELS
############################################

# build week -1 levels map
fig3 <- ggplot() +
  geom_sf(
    data = oa_map,
    aes(fill = wk_m1),
    colour = "grey70", linewidth = 0.15
  ) +
  geom_sf(
    data = oa_map %>% filter(Group == "Treat"),
    aes(colour = flood_label),
    fill = NA, linewidth = 0.6
  ) +
  geom_sf(
    data = tx_points %>% filter(rel_week == -1),
    colour = "black", alpha = 0.9, size = 2
  ) +
  scale_colour_manual(
    name = NULL,
    values = setNames("purple", flood_label),
    guide = guide_legend(order = 1)
  ) +
  scale_fill_gradient(
    name = "Buying searches per km²",
    low = "#FEE5D9", high = "#A50F15",
    na.value = "grey90",
    guide = guide_colorbar(
      order = 2,
      barheight = unit(4, "cm"),
      barwidth  = unit(0.4, "cm"),
      title.position = "top",
      title.hjust = 0.5
    )
  ) +
  coord_sf(
    xlim = c(la_bbox[["xmin"]], la_bbox[["xmax"]]),
    ylim = c(la_bbox[["ymin"]], la_bbox[["ymax"]]),
    expand = FALSE
  ) +
  theme_void(base_size = 9) +
  theme(
    plot.background = element_rect(fill = "white", colour = NA),
    panel.background = element_rect(fill = "white", colour = NA),
    legend.position = "right",
    legend.key.size = unit(0.8, "cm"),
    legend.spacing.y = unit(1, "cm"),
    legend.text = element_text(size = 22),
    legend.title = element_text(size = 24, face = "bold", margin = margin(b = 10)),
    plot.title = element_text(face = "bold", size = 16, hjust = 0.5),
    plot.caption = element_text(size = 7, hjust = 0.5, colour = "grey40")
  )

print(fig3)
ggsave(file.path(fig_dir, "flood_map_searchlevels_wkm1.png"),
       fig3, width = 12, height = 10, units = "in", dpi = 300)

############################################
# LOG % CHANGE versions
############################################

# add log % change columns onto the existing oa_map
oa_map <- oa_map %>%
  mutate(
    logdiff_0_m1 = 100 * (log(wk_0)  - log(wk_m1)),
    logdiff_1_0  = 100 * (log(wk_p1) - log(wk_0)),
    logdiff_4_0  = 100 * (log(wk_p4) - log(wk_0)),
    logdiff_4_m1 = 100 * (log(wk_p4) - log(wk_m1)),
    logdiff_5_0  = 100 * (log(wk_p5) - log(wk_0)),
    logdiff_5_m1 = 100 * (log(wk_p5) - log(wk_m1)),
    logdiff_6_0  = 100 * (log(wk_p6) - log(wk_0)),
    logdiff_6_m1 = 100 * (log(wk_p6) - log(wk_m1))
  )

# pool all log diffs together
all_diffs <- c(oa_map$logdiff_0_m1, oa_map$logdiff_1_0,
               oa_map$logdiff_4_0,  oa_map$logdiff_4_m1,
               oa_map$logdiff_5_0,  oa_map$logdiff_5_m1,
               oa_map$logdiff_6_0,  oa_map$logdiff_6_m1)

# reusable map plotting function, log %, per-variable winsorized scale
plot_logdiff_map <- function(diff_var, tx_relweek, title,
                             fill_name = "% change in searches per km²") {
  

  # 99th percentile of this variable's own tails
  v <- oa_map[[diff_var]]
  v <- v[is.finite(v)]
  lo_lim <- quantile(v, 0.01, na.rm = TRUE)
  hi_lim <- quantile(v, 0.99, na.rm = TRUE)
  
  
  ggplot() +
    geom_sf(
      data = oa_map,
      aes(fill = .data[[diff_var]]),
      colour = "grey70", linewidth = 0.15
    ) +
    geom_sf(
      data = oa_map %>% filter(Group == "Treat"),
      aes(colour = flood_label),
      fill = NA, linewidth = 0.6
    ) +
    geom_sf(
      data = tx_points %>% filter(rel_week == tx_relweek),
      colour = "black", alpha = 0.9, size = 2
    ) +
    scale_colour_manual(
      name = NULL,
      values = setNames("purple", flood_label),
      guide = guide_legend(order = 1)
    ) +
    scale_fill_gradient2(
      name = fill_name,
      low = "#2166AC", mid = "grey96", high = "#A50F15",
      midpoint = 0,
      limits = c(lo_lim, hi_lim),
      oob = scales::squish,
      na.value = "grey90",
      guide = guide_colorbar(
        order = 2,
        barheight = unit(4, "cm"),
        barwidth  = unit(0.4, "cm"),
        title.position = "top",
        title.hjust = 0.5
      )
    ) +
    coord_sf(
      xlim = c(la_bbox[["xmin"]], la_bbox[["xmax"]]),
      ylim = c(la_bbox[["ymin"]], la_bbox[["ymax"]]),
      expand = FALSE
    ) +
    theme_void(base_size = 9) +
    theme(
      plot.background = element_rect(fill = "white", colour = NA),
      panel.background = element_rect(fill = "white", colour = NA),
      legend.position = "right",
      legend.key.size = unit(0.8, "cm"),
      legend.text = element_text(size = 22),
      legend.spacing.y = unit(1, "cm"),
      legend.title = element_text(size = 24, face = "bold", margin = margin(b = 10)),
      plot.title = element_text(face = "bold", size = 24, hjust = 0.5),
      plot.caption = element_text(size = 7, hjust = 0.5, colour = "grey40")
    )
}
# figure 1L: week 0 vs -1
fig1_log <- plot_logdiff_map("logdiff_0_m1", tx_relweek = 0, "")
print(fig1_log)
ggsave(file.path(fig_dir, "flood_map_searchdiff_wk0_vs_wkm1_logpct_winsorized_99.png"),
       fig1_log, width = 12, height = 10, units = "in", dpi = 300)

# figure 2L: week +1 vs 0
fig2_log <- plot_logdiff_map("logdiff_1_0", tx_relweek = 1, "")
print(fig2_log)
ggsave(file.path(fig_dir, "flood_map_searchdiff_wkp1_vs_wk0_logpct_winsorized_99.png"),
       fig2_log, width = 12, height = 10, units = "in", dpi = 300)

# figure 4L: week +4 vs 0
fig4_log <- plot_logdiff_map("logdiff_4_0", tx_relweek = 4, "")
print(fig4_log)
ggsave(file.path(fig_dir, "flood_map_searchdiff_wkp4_vs_wk0_logpct_winsorized_99.png"),
       fig4_log, width = 12, height = 10, units = "in", dpi = 300)

# figure 5L: week +4 vs -1
fig5_log <- plot_logdiff_map("logdiff_4_m1", tx_relweek = 4, "")
print(fig5_log)
ggsave(file.path(fig_dir, "flood_map_searchdiff_wkp4_vs_wkm1_logpct_winsorized_99.png"),
       fig5_log, width = 12, height = 10, units = "in", dpi = 300)

# figure 6L: week +5 vs 0
fig6_log <- plot_logdiff_map("logdiff_5_0", tx_relweek = 5, "")
print(fig6_log)
ggsave(file.path(fig_dir, "flood_map_searchdiff_wkp5_vs_wk0_logpct_winsorized_99.png"),
       fig6_log, width = 12, height = 10, units = "in", dpi = 300)

# figure 7L: week +5 vs -1
fig7_log <- plot_logdiff_map("logdiff_5_m1", tx_relweek = 5, "")
print(fig7_log)
ggsave(file.path(fig_dir, "flood_map_searchdiff_wkp5_vs_wkm1_logpct_winsorized_99.png"),
       fig7_log, width = 12, height = 10, units = "in", dpi = 300)

# figure 8L: week +6 vs 0
fig8_log <- plot_logdiff_map("logdiff_6_0", tx_relweek = 6, "")
print(fig8_log)
ggsave(file.path(fig_dir, "flood_map_searchdiff_wkp6_vs_wk0_logpct_winsorized_99.png"),
       fig8_log, width = 12, height = 10, units = "in", dpi = 300)

# figure 9L: week +6 vs -1
fig9_log <- plot_logdiff_map("logdiff_6_m1", tx_relweek = 6, "")
print(fig9_log)
ggsave(file.path(fig_dir, "flood_map_searchdiff_wkp6_vs_wkm1_logpct_winsorized_99.png"),
       fig9_log, width = 12, height = 10, units = "in", dpi = 300)