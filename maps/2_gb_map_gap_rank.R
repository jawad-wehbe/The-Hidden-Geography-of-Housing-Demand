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
library(viridis) 
library(RColorBrewer)
library(tmap)
library(mapview)
library(webshot)
library(osmdata)
library(osmextract)
library(png)
library(grid)
library(knitr)
library(glue)
library(ggspatial)
library(maptiles)
library(ggrepel)

# clear all

rm (list =ls())
gc()

####################################
# Paths:
####################################

fig_dir <-"~/Desktop/Projects/housing_targets/output/figures/gap/"

settlements_path <- "~/Desktop/Raw_Data/Shapefiles etc/Other/scotland_settlements_centroids/Settlements2020_Centroids.shp"
gap_path <- "~/Desktop/Projects/housing_targets/produced/gap/oa_la_combined_stats_2024.csv"


oa_path <- "~/Desktop/Raw_Data/Shapefiles etc/output_areas_2021.gpkg"


uk_cities_path <- "~/Desktop/Raw_Data/Shapefiles etc/Other/uk_major_towns_cities.gpkg"

########################
# reading the data in 
########################


gap <- read.csv(gap_path) 

oa <- st_read(oa_path)

uk_cities <- st_read(uk_cities_path) %>%
  clean_names() %>%
  select(name = tcity15nm, lat, long) %>%
  st_drop_geometry()

# read in the settlements
settlements <- st_read(settlements_path)


# from google got the largest settlements in population
major_city_codes <- c(
  "S20001766", # Greater Glasgow
  "S20001714", # Edinburgh
  "S20001697", # Dundee
  "S20001725", # Falkirk
  "S20001774", # Hamilton
  "S20001699", # Dunfermline
  "S20001857", # Livingston
  "S20001768", # Greenock
  "S20001574", # Ayr
  "S20001809", # Kilmarnock
  "S20001992", # Stirling
  "S20001935",  # Perth
  "S20001539" # Aberdeen
)


# fiter to those settlements

settlements_filtered <- settlements %>%
  mutate(
    name = if_else(name == "Aberdeen, Milltimber, and Peterculter", "Aberdeen", name),
    name = if_else(name == "Inverness and Culloden", "Inverness", name),
    name = if_else(name == "Greater Glasgow", "Glasgow", name)
  ) %>%
  filter(name %in% c("Inverness", "Aberdeen", "Dundee", "Glasgow", "Edinburgh")) %>%
  st_transform(4326)

# declare cities as sf

uk_cities_sf <- st_as_sf(
  uk_cities,
  coords = c("long", "lat"),    # Note: order is (x, y) = (longitude, latitude)
  crs = 4326                    # WGS84, standard for most maps
) %>%
  mutate(
    name = if_else(name == "Kingston upon Hull", "Hull", name),
    name = if_else(name == "Brighton and Hove", "Brighton", name)
  ) %>%
  filter(name %in% c("Leeds", "Hull", "Sheffield", "Stoke-on-Trent",
                     "Liverpool", "Birmingham", "Norwich", "Swansea", "Cardiff", "Bristol", 
                     "Oxford", "Luton", "London", "Southampton", "Plymouth", "Brighton",
                     "Cambridge", "Manchester", "Exeter", "Peterborough", "Grimsby", "Lincoln", "Shrewsbury", "York",
                     "Darlington", "Hartlepool", "Carlisle", "Newcastle upon Tyne"))

# Select relavant variables and merge with OA

oa_gap <- oa %>%
  left_join(gap %>% 
              select(oa_code, gap_perkm_rank_nat,tightness_rank_nat), by = "oa_code")


# invert the ranking

oa_gap <- oa_gap %>%
  mutate(
    gap_perkm_rank_nat_inv = max(gap_perkm_rank_nat, na.rm = TRUE) + 1 - gap_perkm_rank_nat,
    tightness_rank_nat_inv = max(tightness_rank_nat, na.rm = TRUE) + 1 - tightness_rank_nat
  )

###############
# Plotting
###############

# transform it
oa_gap_4326 <- oa_gap %>%
  st_transform(4326) %>%
  st_make_valid()


uk_cities_3857 <- st_transform(uk_cities_sf, 3857)
settlements_filtered_3857 <- st_transform(settlements_filtered, 3857)


p <- ggplot() +
  annotation_map_tile(type = "osm", zoom = 10) +   # Use "osm" as the basemap
  geom_sf(
    data = oa_gap_4326, 
    aes(fill = gap_perkm_rank_nat_inv), 
    alpha = 0.8,
    color = NA
  ) +
  scale_fill_gradient(
    low = "darkred", 
    high = "#fff0f0", 
    name = "Gap per Km² Rank\n    ( / 235,243)",
    limits = c(1, max(oa_gap_4326$gap_perkm_rank_nat_inv, na.rm = TRUE)),
    breaks = c(1, pretty(c(1, max(oa_gap_4326$gap_perkm_rank_nat_inv, na.rm = TRUE)))), 
    guide = guide_colorbar(
      reverse = TRUE,
      title.position = "top",  
      title.vjust = 2          
    )
  ) +
  geom_sf(
    data = uk_cities_sf,
    shape = 21,
    fill = "black",
    size = 0.75
  ) +
  geom_sf(
    data = settlements_filtered,
    shape = 21,
    fill = "black",
    size = 0.75
  ) +
  geom_text_repel(
    data = uk_cities_3857,
    aes(x = st_coordinates(uk_cities_3857)[,1], y = st_coordinates(uk_cities_3857)[,2], label = name),
    color = "black",
    fontface = "bold",
    size = 2,
    nudge_y = 0.01,
    segment.color = NA
  ) +
  geom_text_repel(
    data = settlements_filtered_3857,
    aes(x = st_coordinates(settlements_filtered_3857)[,1], y = st_coordinates(settlements_filtered_3857)[,2], label = name),
    color = "black",
    fontface = "bold",
    size = 2,
    nudge_y = 0.01,
    segment.color = NA
  ) +
  theme_classic() +
  theme(
    axis.text = element_blank(),
    axis.ticks = element_blank(),
    axis.title = element_blank(),
    axis.line = element_blank(),
    legend.position        = "inside",
    legend.position.inside = c(0.13, 0.098),
    legend.background = element_blank()
  ) + coord_sf(
    crs = 3857,
    ylim = c(6439379, 8291320),
    expand = FALSE
  )

ggsave(
  filename = file.path(fig_dir, "gap_rank_map.png"),
  plot = p,
  width = 7, height = 9, units = "in", dpi = 300
)

