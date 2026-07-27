##############################################################
# NONBOTS MAIN ANALYSIS
##############################################################
# The full event-study pipeline linking Rightmove property searches to construction supply shocks,
# private greenspace, floods, and new builds, all at the output area (OA) level. The sample is every
# non-bot user. Scripts are numbered in execution order, and each one's inputs are produced by the
# scripts before it plus raw data. Scripts 3 and 4 are independent branches that must both finish
# before script 5.


##############################################################
# 1_search_by_location.py
##############################################################
# --------------------------------------------------------------------------------
# Datasets Used
# --------------------------------------------------------------------------------
# - rightmove_filtered.duckdb. The non-bot filtered Rightmove database, providing search_buying and
#   search_letting (~/Desktop/Projects/housing_search/produced/nonbots).
# --------------------------------------------------------------------------------
# Script Purpose and Workflow
# --------------------------------------------------------------------------------
# Build the weekly count of searches per search location, for buying and for letting separately.
# 1. Open the filtered database read-only.
# 2. For each of search_buying and search_letting, keep only searches whose search_location_id falls
#    in the three retained ranges, which drops the postcode-level location ids.
# 3. Count searches by search location, radius filter, year, and week.
# 4. Write one Parquet file per market to the temp folder.
# --------------------------------------------------------------------------------
# Outputs
# --------------------------------------------------------------------------------
# - housing_targets/temp/nature/search_buying_searches_by_week.parquet
# - housing_targets/temp/nature/search_letting_searches_by_week.parquet


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
# 3. Read back every weekly CSV and concatenate them.
# 4. Write the combined panel as one Parquet file.
# --------------------------------------------------------------------------------
# Outputs
# --------------------------------------------------------------------------------
# - housing_targets/produced/nature/nonbots/all/oa_weekly_search.parquet


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
# - housing_targets/temp/nature/oa_weekly_search_w{week}_{year}.csv


##############################################################
# 3_ed_shock_construction.R
##############################################################
# --------------------------------------------------------------------------------
# Datasets Used
# --------------------------------------------------------------------------------
# - NHBC plot.csv, SNIN.csv, inspection.csv. The plot, construction site, and inspection records
#   (~/Desktop/Raw_Data/NHBC).
# - output_areas_2021.gpkg. The 2021 Output Area boundaries.
# --------------------------------------------------------------------------------
# Script Purpose and Workflow
# --------------------------------------------------------------------------------
# Define the construction shock as the week the first home on a site is completed, and map each site
# to the OAs it sits in.
# 1. Per plot, build a completion date as the earliest of the building-control and warranty final
#    dates, falling back to the legal completion date, then the last handover inspection, then a
#    non-failed first-PHO date.
# 2. Join plots to their site, drop plots with no start date, and drop projects with no completion
#    date at all so that data-entry errors do not create phantom sites.
# 3. Keep sites whose first completion falls on or after 1 January 2019, that have at least twenty
#    distinct plots, and whose status is active, completed, enquiry, or resurrected.
# 4. Sum planned plots across the projects on a site to get site size, and take the site's earliest
#    completion week as the shock week.
# 5. Repair the site geometries (drop one broken row, make valid, union sites with more than one
#    polygon) and intersect them with the OAs to list every intersecting OA per site.
# 6. Drop sites where the first completion precedes the first start, convert the dates to ISO year
#    and week to match the search panel, keep shocks before 2025, and write one row per site and
#    intersecting OA.
# --------------------------------------------------------------------------------
# Outputs
# --------------------------------------------------------------------------------
# - housing_targets/produced/search_on_build_shock/setup/ed_shock_oa.parquet


##############################################################
# 3_sd_shock_construction.R
##############################################################
# --------------------------------------------------------------------------------
# Datasets Used
# --------------------------------------------------------------------------------
# - NHBC plot.csv, SNIN.csv. The plot and construction site records (~/Desktop/Raw_Data/NHBC).
# - output_areas_2021.gpkg. The 2021 Output Area boundaries.
# --------------------------------------------------------------------------------
# Script Purpose and Workflow
# --------------------------------------------------------------------------------
# The same construction shock but dated from when building starts rather than when it finishes.
# 1. Join plots to their site and use the plot start date as the milestone date, dropping plots with
#    no start date.
# 2. Keep sites whose first start falls on or after 1 January 2019, that have at least twenty
#    distinct plots, and whose status is active, completed, enquiry, or resurrected.
# 3. Sum planned plots across projects to get site size, and take the site's earliest start week as
#    the shock week.
# 4. Repair and union the site geometries and intersect them with the OAs.
# 5. Convert the dates to ISO year and week, keep shocks before 2025, and write one row per site and
#    intersecting OA.
# Note this produces fewer sites than the end-date version, because sites that completed after 2019
# but started before it are excluded here. It also carries only the shock week and site size, not
# the full set of date variables.
# --------------------------------------------------------------------------------
# Outputs
# --------------------------------------------------------------------------------
# - housing_targets/produced/search_on_build_shock/setup/sd_shock_oa.parquet


##############################################################
# 4_search_to_cw.R
##############################################################
# --------------------------------------------------------------------------------
# Datasets Used
# --------------------------------------------------------------------------------
# - oa_weekly_search.parquet. The OA-week search panel from 2_location_to_oa.py.
# - oa_lsoa.parquet, oa_msoa.parquet, oa_la.parquet, oa_ttwa.parquet. The OA to higher-geography
#   crosswalks (~/Desktop/Raw_Data/Shapefiles etc/Crosswalks).
# --------------------------------------------------------------------------------
# Script Purpose and Workflow
# --------------------------------------------------------------------------------
# Attach the higher geographies each OA belongs to, so the later scripts can build fixed effects and
# match treated areas to controls in the same labour market.
# 1. For each crosswalk, keep for every OA the single target geography with the largest share, so
#    each OA gets exactly one LSOA, MSOA, LA, and TTWA.
# 2. Join the four assignments onto the weekly panel.
# 3. Check how many rows failed to match an LSOA, then write the augmented panel.
# --------------------------------------------------------------------------------
# Outputs
# --------------------------------------------------------------------------------
# - housing_targets/produced/nature/nonbots/all/oa_weekly_search_with_geos.parquet
#   This is the panel every analysis script downstream reads.


##############################################################
# 5_ed_control_dataset_construction.R
# 5_sd_control_dataset_construction.R
##############################################################
# --------------------------------------------------------------------------------
# Datasets Used
# --------------------------------------------------------------------------------
# - oa_weekly_search_with_geos.parquet. The panel from 4_search_to_cw.R.
# - ed_shock_oa.parquet / sd_shock_oa.parquet. The shocks from the two scripts numbered 3.
# - oa_msoa.parquet. The OA to MSOA crosswalk, used to define the exclusion zone.
# --------------------------------------------------------------------------------
# Script Purpose and Workflow
# --------------------------------------------------------------------------------
# Build the pool of untreated OA-weeks that later serve as controls, keeping a buffer between treated
# and control areas so that spillovers do not contaminate the controls. The two scripts are identical
# except for which shock file they read: 5_ed uses the plot completion date, 5_sd the plot start date.
# 1. Recode week 53 to week 52, the convention used throughout the panel.
# 2. Find every MSOA touched by any shocked OA.
# 3. Find every OA that intersects one of those MSOAs, and drop all of them from the panel. The
#    exclusion is by physical intersection, not by assigned MSOA, so OAs straddling a boundary are
#    also removed.
# 4. Label what remains as Control, set site size and the treatment indicator to zero, and write it.
# --------------------------------------------------------------------------------
# Outputs
# --------------------------------------------------------------------------------
# - housing_targets/produced/nature/nonbots/all/ed_control_oa_weekly.parquet
# - housing_targets/produced/nature/nonbots/all/sd_control_oa_weekly.parquet


##############################################################
# 6_ed_pooled_reg_dataset_construction.R
# 6_sd_pooled_red_dataset_construction.R
##############################################################
# --------------------------------------------------------------------------------
# Datasets Used
# --------------------------------------------------------------------------------
# - oa_weekly_search_with_geos.parquet. The panel from 4_search_to_cw.R.
# - ed_shock_oa.parquet / sd_shock_oa.parquet. The shocks from the two scripts numbered 3.
# - ed_control_oa_weekly.parquet / sd_control_oa_weekly.parquet. The control pools from the two
#   scripts numbered 5.
# --------------------------------------------------------------------------------
# Script Purpose and Workflow
# --------------------------------------------------------------------------------
# Build the stacked event-study panel: one clean treated-versus-control comparison per construction
# site, stacked into a single dataset. The two scripts differ only in the shock definition used.
# 1. Keep the OA-weeks belonging to shocked OAs, join on the shock information, and mark the week the
#    shock lands. Drop sites whose shock week never appears in the panel.
# 2. For each construction site in turn:
#    a. Take that site's treated OA-weeks and note which TTWA(s) the site falls in.
#    b. Pull every control OA in those TTWA(s) and stack it under the same site id, so treated areas
#       are only ever compared with controls in the same local labour market.
#    c. Compute relative event time in weeks and cut to a window of -26 to +52.
#    d. Drop the site unless every week in that window is present, so the estimates are not driven by
#       a changing composition of sites.
#    e. Generate one treatment dummy per week in the window, switched on only for treated rows.
# 3. Stack the retained sites, drop any site that ended up with no controls, and write the panel.
# --------------------------------------------------------------------------------
# Outputs
# --------------------------------------------------------------------------------
# - housing_targets/produced/nature/nonbots/all/ed_reg_dataset.parquet
# - housing_targets/produced/nature/nonbots/all/sd_reg_dataset.parquet


##############################################################
# 7_supply_shock_reg.R
##############################################################
# --------------------------------------------------------------------------------
# Datasets Used
# --------------------------------------------------------------------------------
# - ed_reg_dataset.parquet and sd_reg_dataset.parquet. The pooled panels from the two scripts
#   numbered 6.
# - oa_weekly_search_with_geos.parquet. The panel from 4_search_to_cw.R.
# - pp-complete.csv. HMLR price paid transactions, used only for the descriptive statistics at the
#   end (~/Desktop/Raw_Data/HMLR).
# - ONSPD_FEB_2025_UK.csv. The postcode to coordinate lookup, used to place transactions.
# - output_areas_2021.gpkg. The 2021 Output Area boundaries, used to assign transactions to OAs.
# --------------------------------------------------------------------------------
# Script Purpose and Workflow
# --------------------------------------------------------------------------------
# Estimate what happens to buying searches into an area once construction starts there. Because of
# the size of the panels, the sample is restricted to the sites present in both shock definitions and
# to the 44 weeks after treatment.
# 1. Read both pooled panels and take the construction sites common to the two, then keep those sites
#    from the start-date panel.
# 2. Collapse the search panel to OA-year-week, recode week 53 to 52, and join it on in place of the
#    original search columns.
# 3. Trim the event window to 44 weeks post treatment, take logs, and build the OA-by-site and
#    site-by-week fixed effect identifiers, then save the regression-ready dataset so it does not have
#    to be rebuilt on a rerun.
# 4. Run the event study on log buying searches with OA-by-site and site-by-week fixed effects,
#    clustering on the OA-by-site identifier, and tidy the coefficients into relative weeks.
# 5. Convert the estimates to percentages, add a zero reference row at week -5, and plot the event
#    study with its confidence band.
# 6. Geocode the HMLR transactions, assign them to OAs, collapse to OA-year-week counts and average
#    prices, and report pre-period transaction activity for treated OAs.
# Several further cuts (below-median and above-median pre-treatment search areas, and new rural
# developments) are present in the script but commented out.
# --------------------------------------------------------------------------------
# Outputs
# --------------------------------------------------------------------------------
# - housing_targets/produced/nature/nonbots/regression_datasets/
#     all_nonbots_supply_shock_regression_dataset.parquet
# - housing_targets/produced/nature/nonbots/all/supply_shock_all_eventstudy_results_tidy.csv
# - housing_targets/output/figures/nature/nonbots/nonbots_all_sd_filtered_pooled_buying.png


##############################################################
# 8_a_private_greenspace_calculation.R
##############################################################
# --------------------------------------------------------------------------------
# Datasets Used
# --------------------------------------------------------------------------------
# - OS NGD landuse_1 to landuse_4.gpkg. The land-use plot outlines
#   (~/Desktop/Raw_Data/Shapefiles/NGD).
# - site-to-address-reference-01 to 04.csv. The lookup from land plot to the UPRNs on it.
# - AddressBasePremium_FULL_2025-05-09_001.gpkg. The address base, providing the address points and
#   the classification table.
# - OS_Open_Zoomstack.gpkg. The building footprint polygons.
# - output_areas_2021.gpkg. The 2021 Output Area boundaries.
# --------------------------------------------------------------------------------
# Script Purpose and Workflow
# --------------------------------------------------------------------------------
# Measure how much private greenspace, essentially garden, the typical home in each OA has. Run once,
# and the resulting table is reused by scripts 8_b and 10 and by the robustness folder.
# 1. Read the four land-use layers in parallel and combine them, saving a one million row sample for
#    checking.
# 2. Keep addresses classified as residential houses (detached, semi-detached, terraced, and flats),
#    drop Scotland, and drop records retired before 2019.
# 3. Keep building footprints that contain a residential address, and keep land plots that both
#    appear in the plot-to-address lookup and intersect one of those footprints, restricted to plots
#    whose land use is residential accommodation.
# 4. Write the plots, buildings, and lookup out and read them back into DuckDB with spatial indices.
# 5. Deduplicate plots by id, intersect buildings with plots, and union all building pieces within a
#    plot.
# 6. Count the addresses on each plot by classification, then compute greenspace as plot area minus
#    built area, divided by the number of non-flat addresses. Plots that are entirely flats get zero.
# 7. Split each plot's greenspace across the OAs it overlaps, in proportion to the share of the plot
#    in each OA, and take the median across plots to get one value per OA.
# --------------------------------------------------------------------------------
# Outputs
# --------------------------------------------------------------------------------
# - housing_targets/temp/nature/duckcb_greenspace.duckdb, table oa_greenspace_summary, holding
#   median_avg_greenspace_m2 and the number of land fragments per OA.
# - housing_targets/temp/nature/land_sample.gpkg, land_use.gpkg, buildings.gpkg, building_lookup.csv


##############################################################
# 8_b_greenspace_reg.R
##############################################################
# --------------------------------------------------------------------------------
# Datasets Used
# --------------------------------------------------------------------------------
# - duckcb_greenspace.duckdb, table oa_greenspace_summary, from 8_a.
# - oa_weekly_search_with_geos.parquet. The panel from 4_search_to_cw.R.
# - pp-complete.csv. HMLR price paid transactions (~/Desktop/Raw_Data/HMLR).
# - ONSPD_FEB_2025_UK.csv. The postcode to coordinate lookup.
# - output_areas_2021.gpkg and the OA to LSOA, MSOA, and TTWA crosswalks.
# --------------------------------------------------------------------------------
# Script Purpose and Workflow
# --------------------------------------------------------------------------------
# Test whether demand shifted towards OAs with more private greenspace after the pandemic began, in
# searches, in transactions, and in prices.
# 1. Read the OA greenspace table, describe its distribution, plot the percentile curve, and flag OAs
#    with more than ten square metres per dwelling.
# 2. Geocode the transactions, assign them to OAs, and collapse to OA-year-week counts and average
#    prices, then join onto the weekly search panel and zero-fill weeks with no sale.
# 3. Build a continuous week index, set the reference period to the last week of February 2020, and
#    express every period relative to it. Build the fixed effect identifiers and save the panel.
# 4. For each outcome in turn, log searches, inverse hyperbolic sine transactions, and log price, run
#    an event study interacting relative week with the continuous greenspace measure, with OA,
#    TTWA-by-week, and LSOA-by-week fixed effects, clustered on OA.
# 5. Rescale the estimates to a percentage change per hundred square metres and write one results
#    file per outcome.
# 6. Repeat the whole exercise at monthly frequency, with the reference set to February 2020 and the
#    monthly equivalents of the fixed effects.
# --------------------------------------------------------------------------------
# Outputs
# --------------------------------------------------------------------------------
# - housing_targets/produced/nature/nonbots/regression_datasets/
#     greenspace_weekly_reg_dataset_complete.parquet
#     greenspace_monthly_reg_dataset_complete.parquet
# - housing_targets/produced/nature/nonbots/regression_results/
#     greenspace_weekly_{spec}_eventstudy.csv
#     greenspace_monthly_{spec}_eventstudy.csv
#   where {spec} is log_search, ihs_trans, or log_price.
# - housing_targets/output/figures/nature/nonbots/greenspace_oa_percentiles.png


##############################################################
# 8_c_greenspace_figure_plotting.R
##############################################################
# --------------------------------------------------------------------------------
# Datasets Used
# --------------------------------------------------------------------------------
# - The weekly and monthly greenspace event-study results written by 8_b.
# --------------------------------------------------------------------------------
# Script Purpose and Workflow
# --------------------------------------------------------------------------------
# Redraw the greenspace event-study figures from the saved estimates, so the plots can be restyled
# without rerunning the regressions.
# 1. For each frequency and each outcome, read the results file, skipping any that is missing.
# 2. Add back the zero reference row at the omitted period.
# 3. Plot the estimates and confidence band on the shared theme and save the figure.
# --------------------------------------------------------------------------------
# Outputs
# --------------------------------------------------------------------------------
# - housing_targets/output/figures/nature/nonbots/
#     greenspace_weekly_{spec}_oafe_ttwaxywfe_lsoaxweekfe.png
#     greenspace_monthly_{spec}_oafe_ttwaxymfe_lsoaxmonthfe.png


##############################################################
# 9_floods_reg.R
##############################################################
# --------------------------------------------------------------------------------
# Datasets Used
# --------------------------------------------------------------------------------
# - NRW_HISTORIC_FLOODMAP.gpkg and Recorded_Flood_Outlines.gpkg. The recorded flood outlines for
#   England and for Wales (~/Desktop/Raw_Data/Shapefiles etc/Other/Floods).
# - AddressBasePremium_FULL_2025-05-09_001.gpkg. The address base, used to identify residential
#   addresses.
# - output_areas_2021.gpkg, restricted to England and Wales, and the OA to TTWA crosswalk.
# - oa_weekly_search_with_geos.parquet. The panel from 4_search_to_cw.R.
# - pp-complete.csv and ONSPD_FEB_2025_UK.csv. Transactions and the postcode lookup.
# --------------------------------------------------------------------------------
# Script Purpose and Workflow
# --------------------------------------------------------------------------------
# Test whether searches and transactions into an area fall after it floods.
# 1. Combine the England and Wales flood outlines and keep floods starting between 2019 and May 2024.
# 2. Keep residential addresses, drop Scotland and records retired before 2019, and assign each
#    address to its OA.
# 3. Intersect those addresses with the flood outlines to count flooded and total buildings per OA,
#    and plot the distribution of the flooded share.
# 4. Take the twenty largest floods by area covered, treat the OAs they hit as treated, and date each
#    shock by the ISO year and week the flood started.
# 5. For each shock, stack the treated OAs together with every never-treated OA in the same TTWA(s),
#    and compute relative weeks over a window of -24 to +52.
# 6. Attach transactions, generate the event-time dummies, build the TTWA-by-week and OA-by-shock
#    fixed effect identifiers, and save the weekly panel.
# 7. Run the event study for each outcome, transactions and searches, with those fixed effects
#    clustered on the OA-by-shock identifier, convert to percentages, and save the estimates and the
#    figures.
# 8. Repeat the whole exercise at monthly frequency.
# --------------------------------------------------------------------------------
# Outputs
# --------------------------------------------------------------------------------
# - housing_targets/produced/nature/nonbots/regression_datasets/
#     floods_weekly_reg_dataset_complete.parquet
#     floods_monthly_reg_dataset_complete.parquet
# - housing_targets/produced/nature/nonbots/regression_results/
#     {transactions|searches}_weekly_{tr}_flood_ttwaxyw_oa_fe.csv
#     {transactions|searches}_monthly_{tr}_flood_ttwaxym_oa_fe.csv
# - housing_targets/output/figures/nature/nonbots/ the matching PNGs
# The weekly regression dataset here is also the input to 3_transactions_searches_maps.R in the maps
# folder.


##############################################################
# 10_newly_built_reg.R
##############################################################
# --------------------------------------------------------------------------------
# Datasets Used
# --------------------------------------------------------------------------------
# - duckcb_greenspace.duckdb, table oa_greenspace_summary, from 8_a.
# - oa_weekly_search_with_geos.parquet. The panel from 4_search_to_cw.R.
# - pp-complete.csv, restricted to new build sales (~/Desktop/Raw_Data/HMLR).
# - ONSPD_FEB_2025_UK.csv. The postcode to coordinate lookup.
# - output_areas_2021.gpkg and the OA to LSOA, MSOA, and TTWA crosswalks.
# --------------------------------------------------------------------------------
# Script Purpose and Workflow
# --------------------------------------------------------------------------------
# Repeat the greenspace event study on new build transactions only, to ask whether the shift towards
# greener areas shows up in what actually gets built and sold rather than only in what people search
# for.
# 1. Read the OA greenspace table and flag OAs with more than ten square metres per dwelling.
# 2. Keep only transactions flagged as new builds, geocode them, assign them to OAs, and collapse to
#    OA-year-week counts and average prices.
# 3. Join onto the weekly search panel, zero-fill weeks with no new build sale, set the reference
#    period to the last week of February 2020, build the fixed effect identifiers, and save the panel.
# 4. Run the event study interacting relative week with the continuous greenspace measure, with OA,
#    TTWA-by-week, and LSOA-by-week fixed effects, clustered on OA, and save the estimates and figure.
# 5. Repeat at monthly frequency, with the omitted period set six months before the reference rather
#    than one, and the monthly equivalents of the fixed effects.
# --------------------------------------------------------------------------------
# Outputs
# --------------------------------------------------------------------------------
# - housing_targets/produced/nature/nonbots/regression_datasets/
#     greenspace_newbuilds_weekly_reg_dataset_complete.parquet
#     greenspace_newbuilds_monthly_reg_dataset_complete.parquet
# - housing_targets/produced/nature/nonbots/regression_results/
#     greenspace_new_builds_weekly_{spec}_oafe_ttwaxywfe_lsoaxweekfe.csv
#     greenspace_new_builds_monthly_normalised_m6_{spec}_oafe_ttwaxymfe_lsoaxmonthfe.csv
# - housing_targets/output/figures/nature/nonbots/ the matching PNGs