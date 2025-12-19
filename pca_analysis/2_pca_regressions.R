library(dplyr)
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
library(glmnet)
library(modelsummary)


rm(list = ls())
gc()


# PATHS 

# FROM THE 1_employment_to_lsoa.R script
lsoa_employment_level_path <- "~/Desktop/Projects/housing_targets/produced/site_classification/lsoa_private_access_summary.csv"

lsoa_path <- "~/Desktop/Raw_Data/Shapefiles etc/LSOA/uk_lsoa_2021.gpkg"

oa_path <- "~/Desktop/Raw_Data/Shapefiles etc/output_areas_2021.gpkg"

gap_path <- "~/Desktop/Projects/housing_targets/produced/gap/oa_la_combined_stats_2024.csv"

poi_path <- "~/Desktop/Raw_Data/Shapefiles etc/POI/poi_os_dec_23.gpkg"

la_path <- "~/Desktop/Raw_Data/Shapefiles etc/LA/LAD_DEC_2023_UK_BFE.shp"

output_path <- "~/Desktop/Projects/housing_targets/output/figures/nature_cities/"

results_path <- "~/Desktop/Projects/housing_targets/output/tables/nature_cities/"

la_path <- "~/Desktop/Raw_Data/Shapefiles etc/LA/LAD_DEC_2023_UK_BFE.shp"

gb_roads_path <- "~/Desktop/Raw_Data/Shapefiles etc/Other/gb_roads/oproad_gb.gpkg"

temp_path <- "~/Desktop/Projects/housing_targets/temp/nature_cities/"

# FROM THE 4_employment_to_lsoa.R script
lsoa_ids_path <- "~/Desktop/Projects/housing_targets/produced/site_classification/lsoa_ids_private_access.csv"

output_table_paths <- "~/Desktop/Projects/housing_targets/output/tables/nature_cities/"

##########################
# Read in the data
##########################

uk_roads <- st_read(gb_roads_path, layer = "road_link") %>%
  filter(road_classification %in% c("Motorway")) %>%
  select(id, road_classification, road_classification_number, form_of_way, length, geometry) %>%
  st_transform(27700)

la <- st_read(la_path)

lsoa_employment_level <- read_csv(lsoa_employment_level_path) %>%
  filter(!is.na(sum_total_employment))

gap <- read_csv(gap_path) %>%
  group_by(oa_code) %>%                    
  slice_max(area_share, n = 1, with_ties = FALSE) %>%
  ungroup()

poi <- st_read(poi_path) %>%
  filter(groupname %in% c("Accommodation, Eating and Drinking", "Attractions", "Sport and Entertainment", "Education and Health",
                          "Public Infrastructure", "Retail")) %>%
  filter(!classname %in% c("Electrical Features", "Telecommunications Features", "Gas Features")) %>%
  filter(!categoryname %in% c("Central and Local Government", "Organisations")) %>%
  filter(!is.na(groupname)) 


lsoa <- st_read(lsoa_path)

oa <- st_read(oa_path)


# NOTE: THESE  BELOW IDS ARE THE IDS FROM THE 1_employment_to_lsoa.R script

lsoa_ids_destinations <- read_parquet(lsoa_ids_path)




###################################
# OA to Roads
###################################

# Compute OA centroids (in meters CRS)
oa_centroids <- oa %>%
  st_transform(27700) %>%             
  st_centroid()

# Identify OAs with centroid within 50 m of any road
buffer_50m <- st_buffer(uk_roads, dist = 50)

# assign intersections
oa_near_road <- oa_centroids %>%
  st_join(buffer_50m, join = st_intersects, left = FALSE)

#  Extract OA codes that satisfy the condition
oa_within_50m <- oa_near_road$oa_code


#########################
# OA to LA
#########################

# COMMENTNG BELOW JUST TO TO NOT RERUN EVERYTIME FOR TIME

oa_la <- st_intersection(oa, la)

# calculate oa area
oa_area <- oa %>%
  mutate(
    oa_original_area = as.numeric(st_area(geom))
  ) %>%
  st_drop_geometry() %>%
  select(oa_code, oa_original_area)


# now assign each OA to only 1 LSOA based on highest intersection area

oa_la_with_area <- oa_la %>%
  clean_names() %>%
  left_join(oa_area) %>%
  mutate(
    inter_area = as.numeric(st_area(geom)),
    prop = inter_area / oa_original_area
  ) %>%
  st_drop_geometry() %>%
  group_by(oa_code) %>%
  slice_max(prop, n = 1, with_ties = FALSE) %>%
  ungroup() %>%
  select(oa_code, la_code = lad23cd)



########################
# Begin Analysis
########################

  
# now filter to the geometry of the destination LSOAs as those will be the ones that matter for amenities
lsoa_amenities_sf <- lsoa %>%
  semi_join(lsoa_ids_destinations, by = c("lsoa_code" = "destination_id")) 
  
# assign POI to LSOA
poi_lsoa <- st_join(lsoa_amenities_sf, poi, join = st_intersects, left = FALSE)
  
# now count POI per LSOA
poi_lsoa_summary <- poi_lsoa %>%
   st_drop_geometry() %>%
   group_by(lsoa_code, categoryname) %>%
   summarise(n_initial_poi = n(), .groups = "drop") %>%
  filter(!is.na(categoryname)) %>%
  complete(
    lsoa_code = lsoa_amenities_sf$lsoa_code,
    categoryname = unique(poi$categoryname),
    fill = list(n_initial_poi = 0)
  )
  
# now assign the amenities to the destination LSOAs and group by origin LSOA
lsoa_amenities_destination_origin <- lsoa_ids_destinations %>%
  left_join(poi_lsoa_summary, by = c("destination_id" = "lsoa_code")) %>% # assign amenities for destination LSOAs
  group_by(origin_id, categoryname) %>%
  summarise(n_poi = sum(n_initial_poi), .groups = "drop") %>%
  select(lsoa_code = origin_id, group = categoryname,  n_poi)
  
####################################################
# Drop infrastructure and do the classnames
####################################################

# Drop the infrasture here
access_no_infra <- lsoa_amenities_destination_origin %>%
    filter(group != "Infrastructure and Facilities")
  
# now count POI per LSOA BUT THIS TIME COUNT BY CLASSNAME NOT CATEGORYNAME
poi_lsoa_summary <- poi_lsoa %>%
  st_drop_geometry() %>%
  group_by(lsoa_code, classname) %>%
  summarise(n_initial_poi = n(), .groups = "drop") %>%
  filter(!is.na(classname)) %>%
  complete(
    lsoa_code = lsoa_amenities_sf$lsoa_code,
    classname = unique(poi$classname),
    fill = list(n_initial_poi = 0)
  )
  
# now assign the amenities to the destination LSOAs and group by origin LSOA
lsoa_amenities_origin_only <- lsoa_ids_destinations %>%
  distinct(origin_id) %>%
  left_join(poi_lsoa_summary, by = c("origin_id" = "lsoa_code")) %>% # assign amenities for destination LSOAs
  filter(classname %in% c("Libraries", "Halls and Community Centres", "Allotments", "Places Of Worship")) %>%
  select(lsoa_code = origin_id, group = classname,  n_poi = n_initial_poi)
  
# combine everything
lsoa_amenities_destination_origin <- bind_rows(lsoa_amenities_origin_only, access_no_infra)
  


##############################################################
# now bring in the OAs to the LSOA
#############################################################

# Run intersection of the OA to the LSOA 

oa_lsoa <- st_intersection(oa, lsoa)

# now assign each OA to only 1 LSOA based on highest intersection area

oa_lsoa_with_area <- oa_lsoa %>%
  left_join(oa_area) %>%
  mutate(
    inter_area = as.numeric(st_area(geom)),
    prop = inter_area / oa_original_area
  ) %>%
  st_drop_geometry() %>%
  group_by(oa_code) %>%                    
  slice_max(prop, n = 1, with_ties = FALSE) %>%
  ungroup()

# now bring in the lsoa features
oa_lsoa_ew_amenities <- oa_lsoa_with_area %>%
  inner_join(lsoa_amenities_destination_origin, by = "lsoa_code")


########################
# now bring in the gap
########################

oa_lsoa_ew_amenities_gap <- oa_lsoa_ew_amenities %>%
  left_join(gap %>% select(oa_code, gap_per_km2)) %>%
  select(oa_code, lsoa_code, gap_per_km2, group, n_poi)

########################
# Now bring in the roads
########################

oa_lsoa_ew_amenities_gap <- oa_lsoa_ew_amenities_gap %>%  
  mutate(has_road = ifelse(oa_code %in% oa_within_50m, 1, 0))

# make it wide
oa_gap_reg <- oa_lsoa_ew_amenities_gap %>%
  pivot_wider(
    names_from = group,
    values_from = n_poi
  )  %>%
  clean_names() %>%
  left_join(oa_la_with_area, by = "oa_code")



############################################################
# Now assign for each OA the disementiies 
############################################################

# Run intersection of OA to to disamenities

oa_filtered <- oa %>%
  semi_join (oa_lsoa_ew_amenities_gap, by = "oa_code")

# filter to the disementies of interest only

poi_filtered <- poi %>% 
  filter(classname %in% c("Recycling Centres", "Refuse Disposal Facilities", "Waste Storage, Processing and Disposal"))

# now for those OA run a similar intersection like that for lsoa but WITHIN OA 
# assign POI to OA

poi_oa <- st_join(oa_filtered, poi_filtered, join = st_intersects, left = FALSE)

# now count POI per OA
oa_disamenities <- poi_oa %>%
  st_drop_geometry() %>%
  group_by(oa_code, classname) %>%
  summarise(n_poi = n(), .groups = "drop") %>%
  filter(!is.na(classname)) %>%
  complete(
    oa_code = oa_filtered$oa_code,
    classname = unique(poi_filtered$classname),
    fill = list(n_poi = 0)
  ) %>% 
  rename(group = classname)

# make wide to be able to join to the OA gap table

oa_disamenities_wide <- oa_disamenities %>%
  pivot_wider(
    names_from = group,
    values_from = n_poi
  )  %>%
  clean_names() 

############################################################
# Combine the amentiy access with the OA disamenity variable
############################################################

oa_lsoa_ew_amenities_gap_disamenties <- oa_gap_reg %>%  
  left_join( oa_disamenities_wide, by = "oa_code")


###############################################################
# Attach employment access at the LSOA level
################################################################

full_access_dataset <- oa_lsoa_ew_amenities_gap_disamenties %>%
  inner_join(lsoa_employment_level %>%
               select(lsoa_code = origin_id, total_employment = sum_total_employment), by = "lsoa_code")


#####################################################
# Now select all the variables that will run for PCA, we will run 4 versions:
# FIRST VERSION: 
# 1- Residualize against LA
# 2- Standardize all those variables
# 3- Sum the ammenties to create the PCA categories
# 4- Standardize again
# 5- Run PCA
#####################################################


# select the x variables
independent_vars <- full_access_dataset %>%
  select(-oa_code, -lsoa_code, -la_code, -gap_per_km2, -recycling_centres, -refuse_disposal_facilities, -waste_storage_processing_and_disposal) 


# pull their names
variables <- names(independent_vars)

# residualize the original subcategories against LA FE

resid_data <- lapply(variables, function(v) {
  
  f <- as.formula(paste0(v, " ~ 1 | la_code"))
  model <- feols(f, data = full_access_dataset)
  
  return(resid(model))
})

# make it data frame

resid_df <- as.data.frame(do.call(cbind, resid_data))
colnames(resid_df) <- variables

# Standardize: mean 0, sd 1

resid_df <- resid_df %>% 
  mutate(across(everything(), ~ as.numeric(scale(.x))))

# now we create the PCA categories

pca_categories <- data.frame(
  
  A = resid_df$eating_and_drinking,
  
  E = resid_df$recreational_and_vocational_education +
    resid_df$primary_secondary_and_tertiary_education +
    resid_df$education_support_services, 
  
  R = resid_df$household_office_leisure_and_garden +
    resid_df$clothing_and_accessories +
    resid_df$food_drink_and_multi_item_retail,
  
  C = resid_df$sports_complex +
    resid_df$venues_stage_and_screen +
    resid_df$historical_and_cultural +
    resid_df$tourism +
    resid_df$libraries +
    resid_df$halls_and_community_centres +
    resid_df$places_of_worship,
  
  H = resid_df$health_support_services +
    resid_df$health_practitioners_and_establishments,
  
  O = resid_df$outdoor_pursuits +
    resid_df$recreational +
    resid_df$landscape_features +
    resid_df$botanical_and_zoological +
    resid_df$bodies_of_water +
    resid_df$allotments,
  
  W = resid_df$total_employment
  
)


# Standardize again: mean 0, sd 1

pca_categories_standerdized <- pca_categories %>% 
  mutate(across(everything(), ~ as.numeric(scale(.x))))

# Run PCA

pca_v1 <- prcomp(pca_categories_standerdized, center = FALSE, scale. = FALSE)

summary(pca_v1)       # variance explained

# Select only the first 2 components
rot12 <- pca_v1$rotation[, 1:2]


# create the loading of each variable in a nice dataframe
rot_table <- data.frame(
  compoent = rownames(rot12),
  PC1 = round(rot12[, 1], 3),
  PC2 = round(rot12[, 2], 3),
  row.names = NULL
)

# Extract the actual PCAs now to prepare for regression
pc_scores <- as.data.frame(pca_v1$x[, 1:2])
colnames(pc_scores) <- c("PC1", "PC2")

# Attach back the relevant columns
final_pca_data <- cbind(
  oa_code = full_access_dataset$oa_code,
  pc_scores, 
  recycling_centres = full_access_dataset$recycling_centres, 
  refuse_disposal_facilities = full_access_dataset$refuse_disposal_facilities,
  waste_storage_processing_and_disposal = full_access_dataset$waste_storage_processing_and_disposal,
  gap_per_km2 = full_access_dataset$gap_per_km2,
  has_road = full_access_dataset$has_road
)

# create indicators for the disamenities
final_pca_data <- final_pca_data %>%
  mutate(
    ind_recycling = as.integer(recycling_centres > 0),
    ind_refuse = as.integer(refuse_disposal_facilities > 0),
    ind_waste_storage = as.integer(waste_storage_processing_and_disposal > 0)
  )

# Run regression
model <- lm(
  gap_per_km2 ~ PC1 + PC2 +
    ind_recycling + ind_refuse + ind_waste_storage +has_road,
  data = final_pca_data
)

tidy_model_v1 <- tidy(model)

##################################################################
# NOW WE RUN VERSION 2 OF THE PCA (Basically no LA residualizing): 
# 1- Standardize all those variables
# 2- Sum the amenities to create the PCA categories
# 3- Standardize again
# 4- Run PCA
##################################################################


# select the x variables
independent_vars <- full_access_dataset %>%
  select(-oa_code, -lsoa_code, -la_code, -gap_per_km2, -recycling_centres, -refuse_disposal_facilities, -waste_storage_processing_and_disposal) 


# Standardize: mean 0, sd 1
independent_vars <- independent_vars %>% 
  mutate(across(everything(), ~ as.numeric(scale(.x))))

# now we create the PCA categories

pca_categories_v2 <- data.frame(
  
  A = independent_vars$eating_and_drinking,
  
  E = independent_vars$recreational_and_vocational_education +
    independent_vars$primary_secondary_and_tertiary_education +
    independent_vars$education_support_services, 
  
  R = independent_vars$household_office_leisure_and_garden +
    independent_vars$clothing_and_accessories +
    independent_vars$food_drink_and_multi_item_retail,
  
  C = independent_vars$sports_complex +
    independent_vars$venues_stage_and_screen +
    independent_vars$historical_and_cultural +
    independent_vars$tourism +
    independent_vars$libraries +
    independent_vars$halls_and_community_centres +
    independent_vars$places_of_worship,
  
  H = independent_vars$health_support_services +
    independent_vars$health_practitioners_and_establishments,
  
  O = independent_vars$outdoor_pursuits +
    independent_vars$recreational +
    independent_vars$landscape_features +
    independent_vars$botanical_and_zoological +
    independent_vars$bodies_of_water +
    independent_vars$allotments,
  
  W = independent_vars$total_employment
  
)


# Standardize again: mean 0, sd 1

pca_categories_standerdized_v2 <- pca_categories_v2 %>% 
  mutate(across(everything(), ~ as.numeric(scale(.x))))

# Run PCA

pca_v2 <- prcomp(pca_categories_standerdized_v2, center = FALSE, scale. = FALSE)

# summarise PCA
summary(pca_v2)       

# Select only the first 2 components
# Flip signs of loadings of the first PCA (does not affect the analysis just reports the output cleaner)
rot12_v2 <- pca_v2$rotation[, 1:2]
rot12_v2[, 1] <- rot12_v2[, 1] * -1


# create the loading of each variable in a nice dataframe
rot_table_v2 <- data.frame(
  compoent = rownames(rot12_v2),
  PC1 = round(rot12_v2[, 1], 3),
  PC2 = round(rot12_v2[, 2], 3),
  row.names = NULL
)



# Flip the PC scores as well
pc_scores_v2 <- as.data.frame(pca_v2$x[, 1:2])
pc_scores_v2[, 1] <- pc_scores_v2[, 1] * -1
colnames(pc_scores_v2) <- c("PC1", "PC2")

# Attach back the relevant columns
final_pca_data_v2 <- cbind(
  oa_code = full_access_dataset$oa_code,
  pc_scores_v2, 
  recycling_centres = full_access_dataset$recycling_centres, 
  refuse_disposal_facilities = full_access_dataset$refuse_disposal_facilities,
  waste_storage_processing_and_disposal = full_access_dataset$waste_storage_processing_and_disposal,
  gap_per_km2 = full_access_dataset$gap_per_km2,
  has_road = full_access_dataset$has_road
)

# create indicators for the disamenities
final_pca_data_v2 <- final_pca_data_v2 %>%
  mutate(
    ind_recycling = as.integer(recycling_centres > 0),
    ind_refuse = as.integer(refuse_disposal_facilities > 0),
    ind_waste_storage = as.integer(waste_storage_processing_and_disposal > 0)
  )

# Run regression
model_v2 <- lm(
  gap_per_km2 ~ PC1 + PC2 +
    ind_recycling + ind_refuse + ind_waste_storage +has_road,
  data = final_pca_data_v2
)

# tidy up
tidy_model_v2 <- tidy(model_v2)

##########################################
# Extract results
##########################################

# PCA 1 loadings already stored as rot12
loadings_v1 <- as.data.frame(rot12)

# Round to 3 decimals
loadings_v1 <- loadings_v1 %>%
  mutate(across(everything(), ~ round(.x, 3))) %>%
  tibble::rownames_to_column("Category")

#specification 2
loadings_v2 <- as.data.frame(rot12_v2)

# Round to 3 decimals
loadings_v2 <- loadings_v2 %>%
  mutate(across(everything(), ~ round(.x, 3))) %>%
  tibble::rownames_to_column("Category")

# COMBINE BOTH MODE WEIGHTS

pca_weights <- loadings_v1 %>%
  rename(
    `PC 1 (Residualized)` = PC1,
    `PC 2 (Residualized)` = PC2
  ) %>%
  left_join(
    loadings_v2 %>%
      rename(
        `PC 1 (Non-Residualized)` = PC1,
        `PC 2 (Non-Residualized)` = PC2
      ),
    by = "Category"
  ) %>%
  # reorder
  select(Category, `PC 1 (Non-Residualized)`, `PC 2 (Non-Residualized)`, `PC 1 (Residualized)`, `PC 2 (Residualized)` )

# Rename categories
pca_weights <- pca_weights |>
  mutate(
    Category = recode(Category,
                      "A" = "Eating & Drinking",
                      "E" = "Education",
                      "R" = "Retail",
                      "C" = "Culture & Leisure",
                      "H" = "Health",
                      "O" = "Outdoor",
                      "W" = "Employment"
    )
  )

# export THE WEIGHTS as latex
datasummary_df(
  pca_weights,
  output = paste0(output_table_paths, "pca_weights_table.tex")
)


# export THE REGRESSION RESULTS as latex
modelsummary(
  list("Non–Residualized PCA" = model_v2, "LA–Residualized PCA" = model),
  fmt = 3,
  coef_map = c(
    "PC1" = "PC 1",
    "PC2" = "PC 2",
    "ind_recycling" = "Recycling centre",
    "ind_refuse" = "Refuse Disposal Facilities",
    "ind_waste_storage" = "Waste Storage, Processing and Disposal",
    "has_road" = "Motorway Road (50 meters)"
  ),
  gof_omit = "AIC|BIC|Log.Lik|F|RMSE",
  stars = c('*' = 0.1, '**' = 0.05, '***' = 0.01),   
  output = paste0(output_table_paths, "pca_regression_table.tex")
)

