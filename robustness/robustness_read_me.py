##############################################################
# ROBUSTNESS
##############################################################
# Repeats the main event studies on a restricted sample of serious searchers: users who saved a
# property or contacted an agent at least once. The pipeline mirrors nonbots_main_analysis but
# writes everything to a separate saved_or_contacted folder, so the two sets of results can be
# compared directly. The shock definitions and the OA greenspace measure are not rebuilt here, they
# are reused from nonbots_main_analysis.


##############################################################
# 1_search_by_location.py
##############################################################
# --------------------------------------------------------------------------------
# Datasets Used
# --------------------------------------------------------------------------------
# - rightmove_filtered.duckdb. The non-bot filtered Rightmove database, providing search_buying and
#   search_letting and the matching session tables used to define the sample
#   (~/Desktop/Projects/housing_search/produced/nonbots).
# --------------------------------------------------------------------------------
# Script Purpose and Workflow
# --------------------------------------------------------------------------------
# Build the weekly count of searches per search location for the saved-or-contacted sample, for
# buying and for letting separately.
# 1. Open the filtered database read-only and set the DuckDB spill directory, memory limit, and
#    thread count.
# 2. For each of search_buying and search_letting, keep only searches whose search_location_id
#    falls in the three retained ranges, which drops the postcode-level location ids.
# 3. Restrict to users who, in the matching session table, saved a property from either the search
#    results or the details page, or sent at least one email to an agent.
# 4. Count searches by search location, radius filter, year, and week.
# 5. Write one Parquet file per market to the temp folder.
# --------------------------------------------------------------------------------
# Outputs
# --------------------------------------------------------------------------------
# - housing_targets/temp/nature/search_buying_searches_by_week_saved_or_contacted.parquet
# - housing_targets/temp/nature/search_letting_searches_by_week_saved_or_contacted.parquet


##############################################################
# 2_location_to_oa.py
##############################################################
# --------------------------------------------------------------------------------
# Datasets Used
# --------------------------------------------------------------------------------
# - The two weekly search Parquet files written by 1_search_by_location.py.
# - The weekly OA CSVs written by 2_location_to_oa_batch.py.
# --------------------------------------------------------------------------------
# Script Purpose and Workflow
# --------------------------------------------------------------------------------
# Driver script. Run the OA mapping one week at a time, then stitch the weeks back together into a
# single panel. The batch script must sit in the same folder as this one.
# 1. Read the buying and letting weekly files and collect every distinct year and week pair across
#    the two.
# 2. Loop over those pairs in order, calling 2_location_to_oa_batch.py once per week and reporting
#    the runtime and whether each call succeeded.
# 3. Read back every weekly CSV for this sample and concatenate them.
# 4. Write the combined panel as one Parquet file.
# --------------------------------------------------------------------------------
# Outputs
# --------------------------------------------------------------------------------
# - housing_targets/produced/nature/nonbots/saved_or_contacted/oa_weekly_search.parquet


##############################################################
# 2_location_to_oa_batch.py
##############################################################
# --------------------------------------------------------------------------------
# Datasets Used
# --------------------------------------------------------------------------------
# - locationid_rad_to_OA.parq. The crosswalk giving, for each search location and radius, the share
#   of that search area falling in each OA (~/Desktop/Raw_Data/Rightmove).
# - The two weekly search Parquet files written by 1_search_by_location.py.
# --------------------------------------------------------------------------------
# Script Purpose and Workflow
# --------------------------------------------------------------------------------
# Convert one week of location-level searches into OA-level searches. Called once per year and week
# by the driver, taking the year and week as command line arguments.
# 1. Register the crosswalk and the two weekly search files as DuckDB views.
# 2. Filter buying and letting to the requested year and week and join each onto the crosswalk by
#    search location and radius filter.
# 3. Apportion each search to OAs by multiplying the count by the OA share, treating locations with
#    no searches that week as zero.
# 4. Sum to one row per OA for that week and write it as a CSV.
# --------------------------------------------------------------------------------
# Outputs
# --------------------------------------------------------------------------------
# - housing_targets/temp/nature/oa_weekly_search_saved_or_contacted_w{week}_{year}.csv


##############################################################
# 3_search_to_cw.R
##############################################################
# --------------------------------------------------------------------------------
# Datasets Used
# --------------------------------------------------------------------------------
# - oa_weekly_search.parquet. The saved-or-contacted OA-week panel from 2_location_to_oa.py.
# - oa_lsoa.parquet, oa_msoa.parquet, oa_la.parquet, oa_ttwa.parquet. The OA to higher-geography
#   crosswalks (~/Desktop/Raw_Data/Shapefiles etc/Crosswalks).
# --------------------------------------------------------------------------------
# Script Purpose and Workflow
# --------------------------------------------------------------------------------
# Attach the higher geographies each OA belongs to, so the later scripts can build fixed effects
# and match treated areas to controls in the same labour market.
# 1. For each crosswalk, keep for every OA the single target geography with the largest share, so
#    each OA gets exactly one LSOA, MSOA, LA, and TTWA.
# 2. Join the four assignments onto the weekly panel.
# 3. Check how many rows failed to match an LSOA, then write the augmented panel.
# --------------------------------------------------------------------------------
# Outputs
# --------------------------------------------------------------------------------
# - housing_targets/produced/nature/nonbots/saved_or_contacted/oa_weekly_search_with_geos.parquet


##############################################################
# 4_ed_control_dataset_construction.R
# 4_sd_control_dataset_construction.R
##############################################################
# --------------------------------------------------------------------------------
# Datasets Used
# --------------------------------------------------------------------------------
# - oa_weekly_search_with_geos.parquet. The saved-or-contacted panel from 3_search_to_cw.R.
# - ed_shock_oa.parquet / sd_shock_oa.parquet. The end-date and start-date construction shocks,
#   built once in nonbots_main_analysis and reused here
#   (housing_targets/produced/search_on_build_shock/setup).
# - oa_msoa.parquet. The OA to MSOA crosswalk, used to define the exclusion zone.
# --------------------------------------------------------------------------------
# Script Purpose and Workflow
# --------------------------------------------------------------------------------
# Build the pool of untreated OA-weeks that later serve as controls, keeping a buffer between
# treated and control areas so that spillovers do not contaminate the controls. The two scripts are
# identical except for which shock file they read: 4_ed uses the plot completion date, 4_sd uses the
# plot start date.
# 1. Recode week 53 to week 52, the convention used throughout the panel.
# 2. Find every MSOA touched by any shocked OA.
# 3. Find every OA that intersects one of those MSOAs, and drop all of them from the panel.
# 4. Label what remains as Control, set site size and the treatment indicator to zero, and write it.
# --------------------------------------------------------------------------------
# Outputs
# --------------------------------------------------------------------------------
# - housing_targets/produced/nature/nonbots/saved_or_contacted/ed_control_oa_weekly.parquet
# - housing_targets/produced/nature/nonbots/saved_or_contacted/sd_control_oa_weekly.parquet


##############################################################
# 5_common_sites_reg_and_plot.R
##############################################################
# --------------------------------------------------------------------------------
# Datasets Used
# --------------------------------------------------------------------------------
# - ed_reg_dataset.parquet and sd_reg_dataset.parquet. The pooled event-study panels built in
#   nonbots_main_analysis, used to define the common set of sites and to supply the event structure.
# - oa_weekly_search_with_geos.parquet. The saved-or-contacted panel from 3_search_to_cw.R.
# - pp-complete.csv. HMLR price paid transactions, used only for the descriptive statistics at the
#   end (~/Desktop/Raw_Data/HMLR).
# - ONSPD_FEB_2025_UK.csv. The postcode to coordinate lookup, used to place transactions.
# - output_areas_2021.gpkg. The 2021 Output Area boundaries, used to assign transactions to OAs.
# --------------------------------------------------------------------------------
# Script Purpose and Workflow
# --------------------------------------------------------------------------------
# Re-run the supply shock event study with the serious-searcher counts in place of the full search
# counts, holding the sample of sites and the event structure fixed so the only thing that changes
# is the outcome. Because of the size of the panels, the sample is restricted to sites present in
# both shock definitions and to the 44 weeks after treatment.
# 1. Read both pooled panels, take the construction sites common to the two, and keep those sites
#    from the start-date panel.
# 2. Collapse the saved-or-contacted searches to OA-year-week, recode week 53 to 52, then drop the
#    original search columns and join the new ones on.
# 3. Trim the event window to 44 weeks post treatment, take logs, and build the OA-by-site and
#    site-by-week fixed effect identifiers, then save the regression-ready dataset so it does not
#    have to be rebuilt on a rerun.
# 4. Run the event study on log buying searches with those two fixed effects, clustering on the
#    OA-by-site identifier, and tidy the coefficients into relative weeks.
# 5. Convert the estimates to percentages, add a zero reference row at week -5, and plot the event
#    study with its confidence band.
# 6. Repeat steps 3 to 5 on the subsample of shocks whose treated OAs all sit below the median
#    pre-treatment search level, to check the result is not driven by already-busy areas.
# 7. Geocode the HMLR transactions, assign them to OAs, collapse to OA-year-week counts and average
#    prices, and report what share of OA-week, OA-month, and OA-year cells contain a transaction,
#    both overall and for treated OAs only.
# --------------------------------------------------------------------------------
# Outputs
# --------------------------------------------------------------------------------
# - housing_targets/produced/nature/nonbots/regression_datasets/
#     contacted_or_saved_supply_shock_regression_dataset.parquet
# - housing_targets/produced/nature/nonbots/saved_or_contacted/
#     contacted_or_saved_supply_shock_eventstudy_results_tidy.csv
# - housing_targets/output/figures/nature/nonbots/saved_or_contacted/
#     nonbots_saved_or_contacted_sd_filtered_pooled_buying.png
# - housing_targets/output/figures/nature/nonbots/saved_or_contacted/
#     below_median_nonbots_saved_or_contacted_sd_filtered_pooled_buying.png
# - The transaction coverage tables are printed to the console.


##############################################################
# 6_searches_flood_event_study.R
##############################################################
# --------------------------------------------------------------------------------
# Datasets Used
# --------------------------------------------------------------------------------
# - NRW_HISTORIC_FLOODMAP.gpkg and Recorded_Flood_Outlines.gpkg. The recorded flood outlines for
#   England and for Wales (~/Desktop/Raw_Data/Shapefiles etc/Other/Floods).
# - AddressBasePremium_FULL_2025-05-09_001.gpkg. The address base, providing the building points
#   and the classification table used to identify residential addresses.
# - OS_Open_Zoomstack.gpkg. Used for the public greenspace layer.
# - output_areas_2021.gpkg. The 2021 Output Area boundaries, restricted to England and Wales.
# - oa_ttwa.parquet. The OA to TTWA crosswalk.
# - oa_weekly_search_with_geos.parquet. The saved-or-contacted panel from 3_search_to_cw.R.
# --------------------------------------------------------------------------------
# Script Purpose and Workflow
# --------------------------------------------------------------------------------
# Re-run the flood event study on serious searchers, asking whether searches into an area fall after
# it floods.
# 1. Combine the England and Wales flood outlines and keep floods starting between 2019 and May 2024.
# 2. Keep residential addresses only, drop Scotland and records retired before 2019, and assign each
#    address to its OA.
# 3. Intersect those addresses with the flood outlines to count flooded and total buildings per OA,
#    and plot the distribution of the flooded share.
# 4. Take the twenty largest floods by area covered, treat the OAs they hit as treated, and date
#    each shock by the ISO year and week the flood started.
# 5. For each shock, build a stack of the treated OAs plus every never-treated OA in the same
#    TTWA(s), and compute relative weeks over a window of -24 to +52.
# 6. Generate the event-time dummies, take logs, and build the TTWA-by-week and OA-by-shock fixed
#    effect identifiers, then save the regression panel.
# 7. Run the event study on log buying searches with those fixed effects, clustering on the
#    OA-by-shock identifier, convert the estimates to percentages with confidence intervals, save
#    them, and plot the event study against a zero reference at week -1.
# --------------------------------------------------------------------------------
# Outputs
# --------------------------------------------------------------------------------
# - housing_targets/produced/nature/nonbots/saved_or_contacted/floods_weekly_reg_dataset.parquet
# - housing_targets/produced/nature/nonbots/saved_or_contacted/
#     saved_or_contacted_results_floods_event_weekly.csv
# - housing_targets/output/figures/nature/nonbots/saved_or_contacted/
#     nonbots_saved_or_contacted_event_study_buying_searches.png


##############################################################
# 7_searches_private_greenspace_event_study.R
##############################################################
# --------------------------------------------------------------------------------
# Datasets Used
# --------------------------------------------------------------------------------
# - duckcb_greenspace.duckdb, table oa_greenspace_summary. The OA-level median private greenspace
#   per dwelling, computed once in nonbots_main_analysis and reused here
#   (housing_targets/temp/nature).
# - oa_weekly_search_with_geos.parquet. The saved-or-contacted panel from 3_search_to_cw.R.
# - output_areas_2021.gpkg. The 2021 Output Area boundaries.
# --------------------------------------------------------------------------------
# Script Purpose and Workflow
# --------------------------------------------------------------------------------
# Re-run the private greenspace event study on serious searchers, asking whether demand shifted
# towards OAs with more private greenspace after the start of the pandemic.
# 1. Read the OA greenspace table, report its distribution, and flag OAs with more than 10 square
#    metres per dwelling.
# 2. Build a continuous week index over the search panel and set the reference week to the last week
#    of February 2020, then express every week relative to it.
# 3. Join greenspace onto the weekly searches, drop 2024 to keep the regression tractable, take logs
#    and build the TTWA-by-week, LSOA-by-week, and other fixed effect identifiers, then save the
#    regression panel.
# 4. Run the event study interacting relative week with the continuous greenspace measure, with OA,
#    TTWA-by-week, and LSOA-by-week fixed effects, clustering on OA.
# 5. Keep the interaction terms, rescale the estimates to a percentage change per 100 square metres,
#    save them, and plot the event study against a zero reference at week -1.
# --------------------------------------------------------------------------------
# Outputs
# --------------------------------------------------------------------------------
# - housing_targets/produced/nature/nonbots/saved_or_contacted/greenspace_weekly_reg_dataset.parquet
# - housing_targets/produced/nature/nonbots/saved_or_contacted/
#     saved_or_contacted_results_greenspace_weekly.csv
# - housing_targets/output/figures/nature/nonbots/saved_or_contacted/
#     nonbots_saved_or_contacted_searches_greenspace_event_study_plot_cont_treat_oafe_ttwaxywfe_lsoaxweekfe.png