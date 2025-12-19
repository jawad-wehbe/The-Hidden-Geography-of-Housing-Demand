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

# clear all

rm (list =ls())
gc()

####################################
# Paths:
####################################

# Latex report format

report_output_dir <- "~/Desktop/Projects/housing_targets/output/other/"

fig_dir <-"~/Desktop/Projects/housing_targets/output/figures/gap/maps_main_report/"
la_path <- "~/Desktop/Raw_Data/Shapefiles etc/LA/LAD_DEC_2023_UK_BFE.shp"

gap_path <- "~/Desktop/Projects/housing_targets/produced/gap/oa_la_combined_stats_2024.csv"

oa_path <- "~/Desktop/Raw_Data/Shapefiles etc/output_areas_2021.gpkg"

la_target_path <- "~/Desktop/Projects/housing_targets/produced/gap/la_targets_gaps_for_map_updated.csv"

plots <- "~/Desktop/Projects/housing_targets/output/figures/gap/gap_la_plots/"

oa_in_la_output_path <- "~/Desktop/Projects/housing_targets/temp/oa_to_la.gpkg"

bristol_path <- "~/Desktop/Raw_Data/Shapefiles etc/Other/Bristol_boundary.geojson"

out_dir <- "~/Desktop/Projects/housing_targets/produced/reclassification/"

########################
# reading the data in 
########################

bristol_boundary <- st_read(bristol_path) %>%
  select(geometry) %>%
  st_transform(27700)

gap <- read.csv(gap_path)

la <- st_read(la_path) %>%
  clean_names() %>%
  select(la_code = lad23cd, la_name = lad23nm, geometry)

oa <- st_read(oa_path)

la_target <- read_csv(la_target_path)



############################
# Now begin
############################

#####################
# Create ranking of gap
#####################

la_target <- la_target %>%
  arrange(desc(gap_based_target_annual)) %>%
  mutate(rank = row_number())

# remove northern Ireland LAs (it is not in the target dataset so use that to remove it)
missing_in_target <- setdiff(la$la_code, la_target$la_code)

# filter LAs to remove northern Ireland

la <- la %>%
  filter(!la_code %in% missing_in_target)

# merge gap to OA

# collapse gap so each OA code is unique
gap_unique <- gap %>%
  distinct(oa_code, .keep_all = TRUE)   # keeps the first row for each OA


oa_gap <- oa %>%
  left_join(gap_unique %>%
              select(oa_code, gap, gap_per_km2, tightness), by = "oa_code")




##############################################
# Run full intersection of LA to OA in 1 shot
###############################################

message("Getting all intersecting OAs to the LA")

# read it back in ( The code to create it just below it)

oa_in_la_complete <- st_read(oa_in_la_output_path)

# # make same crs
# oa_gap <- st_transform(oa_gap, st_crs(la))
# 
# # do intersection
# oa_in_la_complete <- st_intersection(oa_gap, la) %>%
#   st_make_valid()
# 
# # get OA area
# oa_area <- oa %>%
#   filter(oa_code %in% oa_in_la_complete$oa_code) %>%
#   mutate(
#     oa_area = as.numeric(st_area(geom))
#   ) %>%
#   st_drop_geometry()
# 
# # get intersection area and keep only those with more than 10% intersection proportion
# oa_in_la_complete <- oa_in_la_complete %>%
#   st_transform(27700) %>%
#   mutate(
#     intersection_area = as.numeric(st_area(geom))
#   ) %>%
#   inner_join(oa_area) %>%
#   mutate(
#     proportion = intersection_area/oa_area
#   ) %>%
#   filter(
#     proportion >= 0.1
#   ) %>%
#   st_transform(4326) %>%
#   st_make_valid()
# 
# # save the result so i dont have to rerun
# 
# st_write(oa_in_la_complete, oa_in_la_output_path)

#######################
# Rename Weird LAs
#######################
la <- la %>%
  mutate(
    la_name = case_when(
      la_name == "Bristol, City of" ~ "Bristol",
      la_name == "Kingston upon Hull, City of" ~ "Kingston upon Hull",
      la_name == "Herefordshire, County of" ~ "Herefordshire",
      TRUE ~ la_name  # leave other names unchanged
    )
  )

# change bristol shapefile
la$geometry[la$la_name == "Bristol"] <- bristol_boundary$geometry[1]

#############################
# LOOP
############################

# List of LAs we want to process
la_list <- c(
  "Cornwall",
  "Dorset",
  "Bristol", 
  "City of Edinburgh",
  "Nottingham",
  "Manchester",
  "Liverpool",
  "Salford",
  "Redbridge",
  "Coventry",
  "South Hams",
  "Redcar and Cleveland",
  "Tendring",
  "Cambridge",
  "Slough",
  "Newham",
  "Hillingdon",
  "Islington",
  "Wandsworth",
  "City of London",
  "Sheffield"

)   


for (la_test in la_list) {
  
  message("Running ", la_test, " ...")
  
  # --- Filter LA polygon ---
  la_trial <- la %>% filter(la_name == la_test)
  
  # pull LA code
  la_loop_code <- la %>%
    filter(la_name == la_test) %>%
    pull(la_code)
  
  
  # get LA area to use to check if we plot suburbs or no
  
  la_area_km2 <- la_trial %>%
    st_transform(27700) %>%
    st_area() %>%
    as.numeric() / 1e6
  
  ##########################################
  #  OA intersections with this Specific LA
  ###########################################
  
  oa_in_la <- oa_in_la_complete %>%
    filter(la_code == la_loop_code)
  
 
  #####################################
  ## Maps
  #####################################
  # --- Set up color palette ---
  
  vals <- oa_in_la$gap_per_km2
  min_val <- min(vals, na.rm = TRUE)
  max_val <- max(vals, na.rm = TRUE)
  
  if (min_val > 0) {
    palette <- "Reds"; style <- "cont"; midpoint <- NULL
  } else if (max_val <= 0) {
    palette <- "Blues"; style <- "cont"; midpoint <- NULL
  } else {
    palette <- "-RdBu"; style <- "cont"; midpoint <- 0
  }
  
  
  
  # --- Bounding box for OSM ---
  
  message("Getting BB from OSM and relevant geographies")
  
  bb <- st_bbox(la_trial) %>% st_transform(4326)
  
  # Querying safely because OSM sometimes errors out
  
  safe_osm_query <- function(q, tries = 3, wait = 2) {
    for (i in 1:tries) {
      out <- try(q, silent = TRUE)
      if (!inherits(out, "try-error")) return(out) # if it is not an error, give output
      Sys.sleep(wait) # otherwise wait for a few seconds and then retry
    }
    return(NULL)  # give up after all retries
  }
  
  # --- OSM queries ---
  
  cities <- safe_osm_query(
    opq(bb) %>%
      add_osm_feature(key = "place", value = "city") %>%
      osmdata_sf()
  )
  
  towns <- safe_osm_query(
    opq(bb) %>%
      add_osm_feature(key = "place", value = "town") %>%
      osmdata_sf()
  )
  
  suburbs <- safe_osm_query(
    opq(bb) %>%
      add_osm_feature(key = "place", value = "suburb") %>%
      osmdata_sf()
  )
  
  # --- Deduplicate helper ---
  dedup_osm <- function(sf_obj) {
    if (!is.null(sf_obj) && "name" %in% names(sf_obj)) {
      sf_obj %>%
        filter(!is.na(name)) %>%
        group_by(name) %>%
        slice(1) %>%
        ungroup()
    } else {
      NULL
    }
  }
  
  city_points   <- dedup_osm(cities$osm_points)
  town_points   <- dedup_osm(towns$osm_points)
  suburb_points <- dedup_osm(suburbs$osm_points)
  
  ###########################
  # Plotting
  ##########################
  
  message("Now plotting gap map")
  
  # If any of the following LA is the loop, change its name
  if (la_test == "Bristol, City of") {
    la_test <- "Bristol"
  } else if (la_test == "Kingston upon Hull, City of") {
    la_test <- "Kingston upon Hull"
  } else if (la_test == "Herefordshire, County of") {
    la_test <- "Herefordshire"
  }
  
  ###############################
  # Create a square bbox around LA 
  # #################################

  
  make_rectangle_background <- function(sf_obj, aspect_ratio = 3/2, pad_factor = 0.05) {
    bb <- st_bbox(sf_obj)
    if (any(is.na(bb))) stop("Bounding box contains NA — check geometries or CRS.")
    
    xrange <- bb["xmax"] - bb["xmin"]
    yrange <- bb["ymax"] - bb["ymin"]
    
    # Determine center
    cx <- (bb["xmax"] + bb["xmin"]) / 2
    cy <- (bb["ymax"] + bb["ymin"]) / 2
    
    # Calculate width and height based on desired aspect ratio
    height <- yrange + yrange * pad_factor * 2
    width <- max(xrange + xrange * pad_factor * 2, height * aspect_ratio)
    
    if (width / height < aspect_ratio) {
      width <- height * aspect_ratio
    }
    
    bb_rect <- c(
      xmin = as.numeric(cx - width / 2),
      ymin = as.numeric(cy - height / 2),
      xmax = as.numeric(cx + width / 2),
      ymax = as.numeric(cy + height / 2)
    )
    
    st_as_sfc(st_bbox(bb_rect, crs = st_crs(sf_obj)))
  }
  
  # Example: 2:1 width:height rectangle
  bg_square <- make_rectangle_background(la_trial, aspect_ratio = 3/2, pad_factor = 0.10)
  
  tm <- tm_shape(bg_square) +
    tm_borders(alpha = 0) +                                        
    tm_shape(oa_in_la) +
    tm_tiles("https://tile.openstreetmap.bzh/br/{z}/{x}/{y}.png") +   # ← must come first
    tm_polygons(
      fill = "gap_per_km2",
      fill_alpha = 0.85,
      col = "black",
      lwd = 0.12,
      fill.scale = tm_scale_continuous(values = palette),
      tm_legend(title = "Gap per Km² (Homes per Km²)", orientation = "landscape", position = tm_pos_out("center", "bottom", pos.h = "center") , na.show = FALSE)
    )  +  
    tm_layout(
      bbox = st_bbox(bg_square),
      main.title = paste(la_test),
      main.title.position = "center",
      legend.outside = FALSE,
      asp = 1
    )
  
  #################################
  # For suburbs, towns and cities
  #################################
  
  # define the function to handle empty lists of any of them
  empty_sf <- function(type_name) {
    st_sf(
      name = character(0),
      geometry = st_sfc(crs = 4326), 
      type = character(0)
    )
  }
  
  # Ensure each object is an sf with columns name, geometry, type
  # if null make it an empty sf object using the function above
  
  if (is.null(town_points) || nrow(town_points) == 0) {
    town_points <- empty_sf("Town")
  } else {
    town_points <- town_points %>% select(name, geometry)
    town_points$type <- "Town"
  }
  
  if (is.null(suburb_points) || nrow(suburb_points) == 0) {
    suburb_points <- empty_sf("Suburb")
  } else {
    suburb_points <- suburb_points %>% select(name, geometry)
    suburb_points$type <- "Suburb"
  }
  
  if (is.null(city_points) || nrow(city_points) == 0) {
    city_points <- empty_sf("City")
  } else {
    city_points <- city_points %>% select(name, geometry)
    city_points$type <- "City"
  }
  
  # bind them WITHOUT CITIES FOR NOW
 all_points <- bind_rows(town_points, suburb_points %>% slice_sample(n= 10))
  
  # cities where we decrease the labels
  special_cities <- c("Bristol",
                      "City of Edinburgh",
                      "Nottingham",
                      "Manchester",
                      "Liverpool",
                      "Salford")

  # if any of those cities, select only up to 15 labels

   if (la_test %in% special_cities) {
     all_points <- all_points %>%
       slice_sample(n = 15)
   }

  # more special cities

  # cities where we decrease the labels
  special_cities <- c("Dorset",
                      "Cornwall")

  # if any of those cities, select only up to 15 labels

  if (la_test %in% special_cities) {
    all_points <- all_points %>%
      slice_sample(n = 10)
  }
  
  if (!is.null(all_points) && nrow(all_points) > 0) {
    all_points$label_size <- case_when(
      all_points$type == "Town"   ~ 0.75,
      all_points$type == "City"   ~ 0.9,
      all_points$type == "Suburb" ~ 0.6,
      TRUE                        ~ 0.1   # fallback default
    )
  }

  # add the labeling points
  uniq_sizes <- unique(all_points$label_size)
  if (length(uniq_sizes) == 1) {
    tm <- tm +
      tm_shape(all_points) +
      tm_text(
        "name",
        size = uniq_sizes,  # dynamically use the only value present
        col = "black",
        fontface = "italic",
        options = opt_tm_text(remove_overlap = TRUE)
      )
  } else {
    tm <- tm +
      tm_shape(all_points) +
      tm_text(
        "name",
        size = "label_size",  # let tmap use the mapping when >1 unique value
        col = "black",
        fontface = "italic",
        options = opt_tm_text(remove_overlap = TRUE),
        size.legend = tm_legend(show = FALSE)
      )
  }
  

  print(tm)
  

  #  Save map 
  final_file <- file.path(fig_dir, paste0(la_loop_code, "_", la_test, "_la_gap_per_km2.png"))

  tmap_save(
    tm,
    asp = 3/2,
    dpi = 300,
    filename = final_file
  )
  

  # remove town, cities, suburbs and all points for next iteration
  
  rm(suburb_points, town_points, city_points, all_points)
  
} 

