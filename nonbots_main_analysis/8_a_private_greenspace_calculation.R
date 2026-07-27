
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
library(htmlwidgets)
library(lwgeom)
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




Sys.setenv(OMP_NUM_THREADS = 2)


# CLEAR ALL 
rm(list = ls())
gc()


############
# Paths
############

# land paths
landuse1_path <- "/home/jawad/Desktop/Raw_Data/Shapefiles/NGD/landuse_1.gpkg"

landuse2_path <- "/home/jawad/Desktop/Raw_Data/Shapefiles/NGD/landuse_2.gpkg"

landuse3_path <- "/home/jawad/Desktop/Raw_Data/Shapefiles/NGD/landuse_3.gpkg"

landuse4_path <- "/home/jawad/Desktop/Raw_Data/Shapefiles/NGD/landuse_4.gpkg"

# land to uprn lookup tables

land_uprn_1_path <- "/home/jawad/Desktop/Raw_Data/Shapefiles/NGD/site-to-address-reference-01.csv"

land_uprn_2_path <- "/home/jawad/Desktop/Raw_Data/Shapefiles/NGD/site-to-address-reference-02.csv"

land_uprn_3_path <- "/home/jawad/Desktop/Raw_Data/Shapefiles/NGD/site-to-address-reference-03.csv"

land_uprn_4_path <- "/home/jawad/Desktop/Raw_Data/Shapefiles/NGD/site-to-address-reference-04.csv"

land_uprn_combined_path <- c(
  land_uprn_1_path,
  land_uprn_2_path,
  land_uprn_3_path,
  land_uprn_4_path
)

# other paths

building_addressbook_path <- "/home/jawad/Desktop/Raw_Data/Shapefiles/OS/AddressBasePremium_FULL_2025-05-09_001.gpkg"

os_zoomstack_path <- "/home/jawad/Desktop/Raw_Data/Shapefiles/OS/OS_Open_Zoomstack.gpkg"

oa_path <- "/home/jawad/Desktop/Raw_Data/Shapefiles/output_areas_2021.gpkg"


duckdb_path <- "/home/jawad/Desktop/Projects/housing_targets/temp/nature/duckcb_greenspace.duckdb"

temp_path <- "/home/jawad/Desktop/Projects/housing_targets/temp/nature/"

spill_dir <- "/home/jawad/Desktop/Projects/housing_targets/temp/nature/spill_dir/"

#####################
# Paths to STORE samples of the dataseta (Law of large numbers)
#####################

land_sample_path <- "/home/jawad/Desktop/Projects/housing_targets/temp/nature/land_sample.gpkg"

###################
# Read all data in
###################


# PLOT OUTLINE (reading them in parallel)
plan(multisession, workers = 4)

# combine paths
paths <- c(landuse1_path, landuse2_path, landuse3_path, landuse4_path)

# read them in parallel
land_use <- future_lapply(paths, function(p) {
  sf::st_read(
    p,
    layer = "Site",
    quiet = TRUE
  )
}, future.globals = FALSE)

# return to normal
plan(sequential)

# combine them
land_use_combined <- land_use %>%
  bind_rows() %>%
  st_transform(27700) 

# clean up
gc()

##############
# Store sample
##############

land_use_sample <- land_use %>%
  bind_rows() %>% 
  slice_sample(n = 1000000)

gc()

# save sample

st_write(land_use_sample, land_sample_path, delete_layer =TRUE)

######################
# Reading other data in
#######################


# land to uprn lookup
land_uprn_lookup <- lapply(land_uprn_combined_path, read_csv) %>%
  bind_rows()

# building outline (NOT PLOT OUTLINE)

buildings_gb <- st_read(os_zoomstack_path, layer = "local_buildings")

# building address book (this will  be used to classify residential vs non residential buildings)

buildings_address_book <- st_read(building_addressbook_path, layer = "blpu")

# now read in the building classification table

building_classification <- st_read(building_addressbook_path, layer = "classification")

# OA

oa <- st_read(oa_path)

#############################################
# First step: specify residential buildings
############################################

# filter classifications to only residential (the OS classification scheme can be found on Google)
residential_building_classification <- building_classification %>%
  filter(class_scheme == "AddressBase Premium Classification Scheme",
         classification_code %in% c("RD02", "RD03", "RD04", "RD06")) %>%
  distinct (uprn, classification_code)

# now keep buildings that are only residential
# AND REMOVE SCOTLAND 
# AND REMOVE RECORDS THAT WERE REMOVED BEFORE 2019

residential_building <- buildings_address_book %>%
  inner_join(residential_building_classification, by = "uprn") %>%
  filter(country != "S", 
         (year(end_date) >= 2019 | is.na(end_date))) %>%
  st_transform(27700) %>%
  select(uprn, country, classification_code)

# rm(building_classification, buildings_address_book)
# gc()

####################################################################################
# Now filter to residential buildings only 
# REMEMBER: RESIDENTIAL BUILDING HERE ARE ONLY DETACHED, SEMI DETACHED AND TERRACED
####################################################################################

# residential building has the point geometry and buildings gb has the polygon geometry

residential_building_polygons <- buildings_gb %>% 
  st_transform(27700) %>%
  st_filter(residential_building)


###########################################################################
# now filter lands to those that at least intersect a residential building
###########################################################################

# in addition to this, filter to land in the csv,so first filter look up
land_uprn_lookup_filtered <- land_uprn_lookup %>%
  inner_join(residential_building_classification, by = "uprn") %>%
  select(uprn, classification_code, osid = siteid) #RENAMING SITEID TO OSID FOR THE NEXT STEP


# now filter the land polygons to match the csv
land_use_combined_filtered <- land_use_combined %>%
  semi_join(land_uprn_lookup_filtered, by = "osid")


# now apply the spatial filter to make sure every land has at least 1 intersecting building for our purposes
land_use_residential <- land_use_combined_filtered %>%
  st_filter(residential_building_polygons) %>% 
  filter(oslandusetiera == "Residential Accommodation") # KEEP ONLY RESIDENTIAL LAND NOT MILITARY TRAINING GROUND SHIT


##################################################################
# Next, assign buildings to their PLOT outline using DUCKDB
##############################################################

# paths
land_use_file <- paste0(temp_path, "land_use.gpkg")
buildings_file <- paste0(temp_path, "buildings.gpkg")
building_point_file <- paste0(temp_path, "building_lookup.csv")


# # save the datasets before reading them back in duckdb
st_write(land_use_residential, land_use_file, delete_dsn = TRUE)
st_write(residential_building_polygons, buildings_file, delete_dsn = TRUE)
write_csv(land_uprn_lookup_filtered, building_point_file)



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

#############################
# Begin duck db operations
#############################

# register the important datasets
dbExecute(con, "DROP TABLE IF EXISTS land_use;")
dbExecute(con, "DROP TABLE IF EXISTS buildings;")
dbExecute(con, "DROP TABLE IF EXISTS property_points;")

# plots
dbExecute(con, sprintf("
CREATE TABLE land_use AS
SELECT 
  ST_MakeValid(geom) AS valid_geom,
  *
EXCLUDE (geom)
FROM ST_Read('%s');
", land_use_file))

# buildings
dbExecute(con, sprintf("
CREATE OR REPLACE TABLE buildings AS
SELECT 
  ST_MakeValid(geom) AS valid_geom,
  *
EXCLUDE (geom)
FROM ST_Read('%s');
", buildings_file))

# property points
dbExecute(con, sprintf("
CREATE OR REPLACE TABLE property_points AS
SELECT *
FROM read_csv_auto('%s');
", building_point_file))


# OA
dbExecute(con, sprintf("
CREATE OR REPLACE TABLE oa AS
SELECT
  ST_MakeValid(geom) AS valid_geom,
  *
EXCLUDE (geom)
FROM ST_Read('%s');
", oa_path))

# create indices

dbExecute(con, "
CREATE INDEX land_use_spatial_idx 
ON land_use USING RTREE (valid_geom);
")

dbExecute(con, "
CREATE INDEX buildings_spatial_idx 
ON buildings USING RTREE (valid_geom);
")

dbExecute(con, "
CREATE INDEX oa_spatial_idx 
ON oa USING RTREE (valid_geom);
")

##################################################
# Begin analysis
##################################################

# drop duplicate land
dbExecute(con, "
CREATE OR REPLACE TABLE land_use_dedup AS
SELECT *
FROM (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY osid ORDER BY osid) AS rn
    FROM land_use
)
WHERE rn = 1;
")

# Check which buildings intersect our lands

dbExecute(con, "
CREATE OR REPLACE TABLE building_land_overlap AS
SELECT
  b.uuid, 
  l.osid,
  ST_Intersection(b.valid_geom, l.valid_geom) AS intersection_geom,
  b.valid_geom AS building_valid_geom,
  l.valid_geom AS land_valid_geom
FROM buildings b
JOIN land_use_dedup l
ON ST_Intersects(b.valid_geom, l.valid_geom);
")


# Count classifications / UPRNs per land

dbExecute(con, "
CREATE OR REPLACE TABLE land_classification_summary AS
SELECT
    osid,

    COUNT(DISTINCT uprn) AS uprn_total,
    COUNT(DISTINCT CASE WHEN classification_code = 'RD02' THEN uprn END) AS n_rd02,
    COUNT(DISTINCT CASE WHEN classification_code = 'RD03' THEN uprn END) AS n_rd03,
    COUNT(DISTINCT CASE WHEN classification_code = 'RD04' THEN uprn END) AS n_rd04,
    COUNT(DISTINCT CASE WHEN classification_code = 'RD06' THEN uprn END) AS n_rd06,

    COUNT(DISTINCT CASE WHEN classification_code <> 'RD06' THEN uprn END) AS uprn_non_rd06,

    COUNT(DISTINCT classification_code) AS n_class_types,

    CASE
        WHEN COUNT(DISTINCT CASE WHEN classification_code <> 'RD06' THEN uprn END) = 0 THEN 1
        ELSE 0
    END AS all_rd06
FROM property_points
GROUP BY osid;
")


# Union all intersecting building pieces within each land

dbExecute(con, "
CREATE OR REPLACE TABLE land_building_union AS
SELECT
    osid,
    ST_Union_Agg(intersection_geom) AS buildings_union_geom
FROM building_land_overlap
GROUP BY osid;
")


##################################################
# 3) Compute green area = land - intersecting building geometry
#    Then divide by number of non-RD06 UPRNs
#    If all UPRNs are RD06(flats) => average greenspace = 0
##################################################

dbExecute(con, "
CREATE OR REPLACE TABLE land_greenspace_base AS
SELECT
    l.osid,
    l.valid_geom AS land_geom,
    c.uprn_total,
    c.n_rd02,
    c.n_rd03,
    c.n_rd04,
    c.n_rd06,
    c.uprn_non_rd06,
    c.n_class_types,
    c.all_rd06,
    u.buildings_union_geom
FROM land_use_dedup l
INNER JOIN land_classification_summary c
    ON l.osid = c.osid
INNER JOIN land_building_union u
    ON l.osid = u.osid
WHERE u.buildings_union_geom IS NOT NULL;
")


# calculate the areas
dbExecute(con, "
CREATE OR REPLACE TABLE land_greenspace AS
WITH greenspace_calc AS (
    SELECT
        osid,
        uprn_total,
        n_rd02,
        n_rd03,
        n_rd04,
        n_rd06,
        uprn_non_rd06,
        n_class_types,
        all_rd06,
        land_geom,
        ST_Area(land_geom) AS land_area_m2,
        ST_Area(buildings_union_geom) AS built_area_m2,
        GREATEST(
            0,
            ST_Area(ST_Difference(land_geom, buildings_union_geom))
        ) AS greenspace_area_m2
    FROM land_greenspace_base
)
SELECT
    *,
    CASE
        WHEN all_rd06 = 1 OR uprn_non_rd06 = 0 THEN 0
        ELSE greenspace_area_m2 / uprn_non_rd06
    END AS avg_greenspace_m2
FROM greenspace_calc;
")

# fetch the numbers to R of greenspace 

land_greenspace <- dbGetQuery(con, "
SELECT
    osid,
    uprn_total,
    uprn_non_rd06,
    land_area_m2,
    built_area_m2,
    greenspace_area_m2,
    avg_greenspace_m2
FROM land_greenspace
")




###########################################################################################
## Now for OAs
###########################################################################################


# calculate proportion of land intersecting the OA
dbExecute(con, "
CREATE OR REPLACE TABLE land_oa_overlap AS
SELECT
    g.osid,
    o.oa_code,
    ST_Area(ST_Intersection(g.land_geom, o.valid_geom)) / g.land_area_m2 AS land_overlap_share
FROM land_greenspace g
INNER JOIN oa o
ON ST_Intersects(g.land_geom, o.valid_geom);
")

# allocate the average green space based on the proportion of the land covering that OA (NOT PROPORTION OF GREENSPACE COVERING THE LAND)
dbExecute(con, "
CREATE OR REPLACE TABLE land_oa_weighted AS
SELECT
    lo.osid,
    lo.oa_code,
    g.avg_greenspace_m2,
    lo.land_overlap_share,
    g.avg_greenspace_m2 * lo.land_overlap_share AS weighted_greenspace
FROM land_oa_overlap lo
INNER JOIN land_greenspace g
ON lo.osid = g.osid;
")


# compute median greenspace per OA
dbExecute(con, "
CREATE OR REPLACE TABLE oa_greenspace_summary AS
SELECT
    oa_code,
    MEDIAN(weighted_greenspace) AS median_avg_greenspace_m2,
    COUNT(*) AS n_land_fragments
FROM land_oa_weighted
GROUP BY oa_code;
")

# Fetch the table
greenspace_df <- dbGetQuery(con, "SELECT * FROM oa_greenspace_summary")


# disconnect
dbDisconnect(con, shutdown = TRUE)
