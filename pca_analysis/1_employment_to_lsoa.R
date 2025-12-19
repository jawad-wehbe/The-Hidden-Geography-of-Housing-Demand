# Load the packages
library(readr)
library(dplyr)
library(stringr)
library(janitor)
library(tidyr)
library(readxl)
library(arrow)

rm(list = ls())

# Define file paths

path_lsoa <- "~/Desktop/Raw_Data/Shapefiles etc/Other/employment_2023_LSOA_2011.csv"

# Output path 5 min private or 15 mins public
private_output_paths <- "~/Desktop/Projects/housing_targets/produced/site_classification/lsoa_private_access_summary.csv"
lsoa_ids_output_path <- "~/Desktop/Projects/housing_targets/produced/site_classification/lsoa_ids_private_access.csv"

# travel time path
travel_time_path <- "~/Desktop/Raw_Data/Shapefiles etc/Other/LSOA_travel_time_matrix.csv"

# Send of the output used in reclassification of BUAs
output_lsoa_employment <- "~/Desktop/Projects/housing_targets/produced/reclassification/lsoa_employment.csv"

####################
# Load the CSV files
####################
employment_lsoa <- read_csv(path_lsoa)
lsoa_travel_time_matrix <- read_csv(travel_time_path)


#########################################
# now clean up LSOA level data
#########################################
employment_lsoa <- employment_lsoa %>%
  mutate(LSOA_code = str_extract(`2011 super output area - lower layer`, "^[A-Z0-9]+")) %>%
  filter(!is.na(`2011 super output area - lower layer`))

# get column names
old_names <- names(employment_lsoa)

# Get new names: use extracted code if present, else original name
new_names <- ifelse(
  str_detect(old_names, "^\\d{2,3}"),
  str_extract(old_names, "^\\d{2,3}"),
  old_names
)


# Set new names
names(employment_lsoa) <- new_names

# since the data skipsevery other column, drop those
employment_lsoa_clean <- employment_lsoa %>%
  select(-starts_with("..."))

# reorder and remove some weird row with text
employment_lsoa_clean <- employment_lsoa_clean %>%
  select(LSOA_code, everything(), -`201`) %>%
  slice(-34754)

# make numeric
employment_lsoa_clean <- employment_lsoa_clean %>%
  mutate(across(-LSOA_code, as.numeric))  # convert all except LSOA_code

# make long
employment_lsoa_long <- employment_lsoa_clean %>%
  pivot_longer(
    cols = -LSOA_code, # everything except the LSOA_code
    names_to = "industry_code",
    values_to = "employment"
  )%>% clean_names


###########################################
# Merge in LSOA with Country data
###########################################

# final cleaning: dropping sectors with 0 employment across great britain
employment_lsoa_long <- employment_lsoa_long %>%
  filter(!industry_code %in% c("07", "97", "98", "99"))


# final table
employment_lsoa_summary <- employment_lsoa_long %>%
  group_by(lsoa_code) %>%
  summarise(
    total_employment = sum(employment, na.rm = TRUE),
  )  %>%
  ungroup()



#####################################################
# Now work using the  5 min private or 15 min public
#####################################################


# Filter reachable by fastest_time
reachable_LSOAs_fastest <- lsoa_travel_time_matrix %>%
    filter(car_time <= 300 | pub_time <= 900)
  
# Join with employment summary


reachable_LSOAs_fastest <- reachable_LSOAs_fastest %>%
  left_join(employment_lsoa_summary, by = c("destination_id" = "lsoa_code")) %>%
  filter(!str_starts(origin_id, "S") & !str_starts(destination_id, "S"))
  
# select lsoa to their destinations only

reachable_LSOAs_ids <- reachable_LSOAs_fastest %>%
  select (origin_id, destination_id) 

# save each LSOA and its assigned ids

write_parquet(reachable_LSOAs_ids, lsoa_ids_output_path)


# Summarise
lsoa_fastest_access_summary <- reachable_LSOAs_fastest %>%
  group_by(origin_id) %>%
  summarise(
    sum_total_employment = sum(total_employment, na.rm = TRUE)
  )  %>%
  ungroup() %>%
  filter(!str_starts(origin_id, "S"))
  
# Write CSV
write_csv(lsoa_fastest_access_summary, private_output_paths)




