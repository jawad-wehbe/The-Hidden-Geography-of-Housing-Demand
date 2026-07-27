
# 1- Maps

1_main_report_la_maps.R: Produces the local authority gap maps in the main paper. One PNG per LA is saved as {la_code}_{la_name}_la_gap_per_km2.png.

2_gb_map_gap_rank.R: Creates the GB-wide gap rank map in the main report. Saved as gap_rank_map.png.

3_transactions_searches_maps.R: Maps how OA-level buying searches move around a chosen flood event (Storm Ciara, 2020) within a single local authority, plotting changes in searches per km² across event weeks with flooded OA boundaries and transactions overlaid.

# 2- Descriptives

1_rightmove_descriptives.py: Produces the Rightmove summary statistics table used in the main paper. Results are assembled into a single table and exported as LaTeX (summary_table.tex).

2_rank_rank_correlations_buying_searches.R: Collapses each weekly OA search panel to total buying searches per OA, then reports the rank-rank correlation matrix across the four user samples — all non-bot users, users who saved a property, users who contacted an estate agent, and users who did both — on the set of OAs present in all four. The all panel comes from nonbots_main_analysis; the other three are produced by the subfolders below.

# 2.1 - Serious Searches Samples

Three subfolders: saved, contacted, and contacted_and_saved. Each contain the same three scripts as the main search panel construction in nonbots_main_analysis, differing only in which users are kept and where the output is written:

| Subfolder | Users retained | Output |
|---|---|---|
| `saved` | Saved at least one property | `produced/nature/nonbots/saved/oa_weekly_search.parquet` |
| `contacted` | Sent at least one email to an agent | `produced/nature/nonbots/contacted/oa_weekly_search.parquet` |
| `contacted_and_saved` | Both saved a property and contacted an agent | `produced/nature/nonbots/contacted_and_saved/oa_weekly_search.parquet` |


1_search_by_location.py: Aggregates weekly buying and letting search counts by search location and radius filter for the subfolder's user sample, and saves one Parquet file per search type.

2_location_to_oa.py: Identifies all year–week combinations in that sample's search data, sequentially runs 2_location_to_oa_batch.py for each, and combines the weekly CSVs into the sample's OA-week search panel.

2_location_to_oa_batch.py: For a single year–week, apportions the sample's location-level searches to output areas using the location-to-OA share crosswalk, and writes the weekly OA-level CSV.

# 3- Nonbots Main Analysis
This folder contains the full event-study pipeline linking Rightmove property searches (non-bot sessions) to construction supply shocks, private greenspace, floods, and new builds at the output area (OA) level. Scripts are numbered in execution order.

1_search_by_location.py: Aggregates weekly buying and letting search counts by search location and radius filter from the filtered (non-bot) Rightmove database, and saves one Parquet file per search type.

2_location_to_oa.py: Identifies all year–week combinations present in the weekly search data, sequentially runs 2_location_to_oa_batch.py for each, then combines the weekly CSVs into a single OA-week search panel (oa_weekly_search.parquet).

2_location_to_oa_batch.py: For a single year–week, apportions location-level buying and letting searches to output areas using the location-to-OA share crosswalk, and writes the weekly OA-level CSV.

3_ed_shock_construction.R: Constructs the end-date shock: for large (≥20 plot) post-2019 sites, defines the shock week as the completion of the site's first plot (building control / warranty / legal completion date, with handover and PHO fallbacks), repairs and unions site polygons, maps each site to its intersecting output areas, and exports the OA-level shock dataset (ed_shock_oa.parquet).

3_sd_shock_construction.R: Constructs the start-date shock: for large post-2019 sites, defines the shock week as the start date of the site's first plot, maps sites to intersecting output areas, and exports the OA-level shock dataset (sd_shock_oa.parquet). Produces fewer sites than the end-date version, as sites completed after 2019 but started before 2019 are excluded.

4_search_to_cw.R: Assigns each OA in the weekly search panel to its LSOA, MSOA, LA, and TTWA (using the maximum-share crosswalk match) and writes the augmented panel (oa_weekly_search_with_geos.parquet) used by all analysis scripts downstream.

5_ed_control_dataset_construction.R: Constructs the control OA-week dataset for end-date shocks by excluding every output area that intersects an MSOA touched by a shocked OA, and exports the untreated weekly search panel (ed_control_oa_weekly.parquet).

5_sd_control_dataset_construction.R: Same as above for start-date shocks, exporting sd_control_oa_weekly.parquet.

6_ed_pooled_reg_dataset_construction.R: Builds the stacked event-study regression dataset for end-date shocks: for each construction site, pairs treated OAs with control OAs in the same TTWA(s), computes relative event time, keeps only sites with a complete −26 to +52 week window and at least one control, generates the event-time dummies, and exports the pooled panel (ed_reg_dataset.parquet).

6_sd_pooled_red_dataset_construction.R: Same as above for start-date shocks, exporting sd_reg_dataset.parquet.

7_supply_shock_reg.R: Runs the pooled event-study regressions of buying searches on the supply shock, using the sites common to both the end-date and start-date datasets and an event window restricted to 44 weeks post treatment (for computational reasons). Exports the tidy event-study estimates and produces the supply shock figures in the paper.

8_a_private_greenspace_calculation.R: Computes private residential greenspace: filters OS NGD land-use plots to residential land intersecting residential buildings (detached, semi-detached, terraced), subtracts the built footprint from each plot in DuckDB, allocates per-dwelling greenspace to output areas by area overlap, and stores the OA-level summary table (oa_greenspace_summary) in the greenspace DuckDB database used by the following scripts.

8_b_greenspace_reg.R: Merges the OA greenspace measure with weekly searches and transactions, builds the weekly and monthly regression datasets, runs the greenspace event-study regressions (searches, transactions, prices), and exports the estimates as CSVs to the regression results folder.

8_c_greenspace_figure_plotting.R: Reads the saved greenspace event-study estimates and re-plots the weekly and monthly figures used in the paper.

9_floods_reg.R: Identifies flooded output areas using the England and Wales recorded flood outlines and the OS address base, merges with weekly searches and transactions, builds the weekly and monthly flood event-study datasets, runs the regressions, and exports estimates and figures.

10_newly_built_reg.R: Runs the new-build event study: combines the OA greenspace measure with newly built HMLR transactions and weekly searches, builds the weekly and monthly regression datasets, runs the event-study regressions, and exports estimates and figures.
