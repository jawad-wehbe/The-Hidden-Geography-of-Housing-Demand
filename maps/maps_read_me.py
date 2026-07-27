##############################################################
# MAPS
##############################################################
# The maps used in the main paper. Scripts 1 and 2 map the housing gap and depend on the gap
# statistics produced upstream. Script 3 maps the search response to a flood event and depends on
# the flood regression dataset built in nonbots_main_analysis, so it cannot be run on its own.


##############################################################
# 1_main_report_la_maps.R
##############################################################
# --------------------------------------------------------------------------------
# Datasets Used
# --------------------------------------------------------------------------------
# - LAD_DEC_2023_UK_BFE.shp. The December 2023 local authority district boundaries
#   (~/Desktop/Raw_Data/Shapefiles etc/LA).
# - output_areas_2021.gpkg. The 2021 Output Area boundaries.
# - oa_la_combined_stats_2024.csv. The OA-level housing gap, providing gap, gap_per_km2, and
#   tightness (housing_targets/produced/gap).
# - la_targets_gaps_for_map_updated.csv. The LA-level annual gap-based targets, used to rank LAs and
#   to identify which LAs are in scope.
# - Bristol_boundary.geojson. A corrected boundary for Bristol.
# - oa_to_la.gpkg. The cached OA-to-LA intersection layer (housing_targets/temp). The code that
#   builds it sits in the script directly below the line that reads it, commented out. It must be
#   run once before the script will work on a new machine.
# --------------------------------------------------------------------------------
# Script Purpose and Workflow
# --------------------------------------------------------------------------------
# Draw, for each selected local authority, a map of the housing gap per square kilometre at OA level
# over a street basemap, so the geography of unmet demand within a city is visible.
# 1. Rank LAs by their annual gap-based target, and drop the LAs absent from the target file, which
#    removes Northern Ireland.
# 2. Collapse the gap file to one row per OA and join it onto the OA boundaries.
# 3. Read the cached OA-to-LA intersection, which keeps OAs overlapping an LA by at least ten per
#    cent of their area, so that OAs straddling a boundary are still shown.
# 4. Tidy the awkward LA names (Bristol, Kingston upon Hull, Herefordshire) and swap in the corrected
#    Bristol boundary.
# 5. For each LA in the selected list:
#    a. Pull that LA's OAs and choose the colour scale from the sign of the gap values, sequential
#       red if all positive, sequential blue if all negative, and diverging centred on zero if mixed.
#    b. Query OpenStreetMap for the cities, towns, and suburbs inside the LA's bounding box, retrying
#       on failure and returning nothing rather than erroring if OSM stays unavailable.
#    c. Build a padded rectangular background at a three-to-two aspect ratio so every map is framed
#       consistently.
#    d. Draw the OAs shaded by gap per square kilometre over OSM tiles, then add place labels, thinned
#       for the denser cities so the labels stay readable.
#    e. Save one PNG per LA.
# --------------------------------------------------------------------------------
# Outputs
# --------------------------------------------------------------------------------
# - housing_targets/output/figures/nature/nonbots/maps/{la_code}_{la_name}_la_gap_per_km2.png


##############################################################
# 2_gb_map_gap_rank.R
##############################################################
# --------------------------------------------------------------------------------
# Datasets Used
# --------------------------------------------------------------------------------
# - output_areas_2021.gpkg. The 2021 Output Area boundaries.
# - oa_la_combined_stats_2024.csv. The OA-level housing gap, providing the national rank of gap per
#   square kilometre and of tightness (housing_targets/produced/gap).
# - uk_major_towns_cities.gpkg. The major towns and cities used as reference points.
# - Settlements2020_Centroids.shp. The Scottish settlement centroids, used because the towns and
#   cities file does not cover Scotland
#   (~/Desktop/Raw_Data/Shapefiles etc/Other/scotland_settlements_centroids).
# --------------------------------------------------------------------------------
# Script Purpose and Workflow
# --------------------------------------------------------------------------------
# Draw the single GB-wide map showing which output areas have the most intense housing gap, ranked
# nationally.
# 1. Join the national gap-per-square-kilometre rank onto the OA boundaries.
# 2. Invert the rank so the highest-gap OAs sit at the top of the colour scale and read as the
#    darkest, then reverse the colourbar so the legend runs the same way.
# 3. Select the English and Welsh towns and cities to label, and separately the largest Scottish
#    settlements, renaming a few to their short forms.
# 4. Plot every OA shaded by inverted rank over an OpenStreetMap basemap, add the labelled reference
#    points with repelled text so they do not overlap, strip the axes, and clip to the GB extent.
# --------------------------------------------------------------------------------
# Outputs
# --------------------------------------------------------------------------------
# - housing_targets/output/figures/nature/nonbots/maps/gap_rank_map.png


##############################################################
# 3_transactions_searches_maps.R
##############################################################
# --------------------------------------------------------------------------------
# Datasets Used
# --------------------------------------------------------------------------------
# - floods_weekly_reg_dataset_complete.parquet. The weekly flood event-study panel built by
#   9_floods_reg.R in nonbots_main_analysis
#   (housing_targets/produced/nature/nonbots/regression_datasets).
# - output_areas_2021.gpkg. The 2021 Output Area boundaries.
# - oa_la.parquet. The OA to LA crosswalk, used to assign each OA one local authority.
# - pp-complete.csv. HMLR price paid transactions (~/Desktop/Raw_Data/HMLR).
# - ONSPD_FEB_2025_UK.csv. The postcode to coordinate lookup.
# --------------------------------------------------------------------------------
# Script Purpose and Workflow
# --------------------------------------------------------------------------------
# Show what the flood event study looks like on the ground: for one flood in one local authority,
# map how buying searches move week by week around the flood, with real transactions overlaid.
# 1. Assign each OA its majority-share local authority.
# 2. Rank the flood shock and LA combinations by how much mean searches in treated OAs change between
#    the four weeks before and the four weeks after the shock, then take the chosen combination,
#    Storm Ciara in 2020, picked because many OAs are affected.
# 3. Keep that shock and LA over event weeks -1, 0, +1, +4, +5, and +6, and divide searches by OA area
#    so all maps are in searches per square kilometre.
# 4. Pivot to one row per OA and compute the differences between week pairs, week 0 against week -1,
#    week +1 against week 0, and weeks +4, +5, and +6 against both week 0 and week -1.
# 5. Geocode the transactions from their postcodes, assign them to the LA's OAs, and tag each one
#    with its event week.
# 6. Draw each difference map on a diverging scale centred at zero, with the flooded OA boundaries
#    outlined in purple and one black dot per transaction in that week, plus a baseline map of raw
#    search levels in week -1.
# 7. Repeat the difference maps as log percentage changes, each on its own scale winsorised at the
#    first and ninety-ninth percentiles so a few extreme OAs do not flatten the rest.
# --------------------------------------------------------------------------------
# Outputs
# --------------------------------------------------------------------------------
# All written to housing_targets/output/figures/nature/nonbots/maps/
# - flood_map_searchlevels_wkm1.png
# - flood_map_searchdiff_{week pair}_levels.png
# - flood_map_searchdiff_{week pair}_logpct_winsorized_99.png
#   where {week pair} is wk0_vs_wkm1, wkp1_vs_wk0, wkp4_vs_wk0, wkp4_vs_wkm1, wkp5_vs_wk0,
#   wkp5_vs_wkm1, wkp6_vs_wk0, or wkp6_vs_wkm1.