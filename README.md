
# 1- Maps

1_main_report_maps.R: Produces the gap per km² maps in the main paper for the selected local authorities showing OA-level housing gaps.

2_gb_map_gap_rank.R: Creates the gap per km² GB map in the main report output areas ranked by housing gap intensity.

# 2- Descriptives

1_oa_normalized_gap_build_scatterplot.R: Constructs OA-level build counts from NHBC plot completions, assigns each site to its OA, and plots the scatter plot of the builds versus normalised gap used in the main paper.

2_rightmove_descriptives.py: Produces the Rightmove user and session descriptive statistics table used in the main paper.

# 3- PCA Analysis

1_employment_to_lsoa.R :  Computes employment access within 5 minutes by car or 15 minutes by public transport.

2_pca_regressions.R: Builds an OA-level amenity access dataset, runs the PCA (with and without LA residualisation), and run the regression describesd in the main paper


# 4- Event Study
# 4.1- Setup
1_search_by_location.py: Aggregates weekly  property search counts by location and search radius for buying and letting searches, and saves the results as Parquet files.

2_location_to_oa_batch.py: Maps weekly buying and letting searches output areas, outputs weekly CSVs, and combines them into a single Parquet file.

2_location_to_oa.py: Identifies all year–week combinations in weekly search data and sequentially runs the previous batch script to map searches to output areas.

3_sd_shock_construction.R: Constructs the site-level shock based on first plot start dates for large post-2019 sites, maps shocks to output areas, and exports the resulting OA-level shock data.

3_ed_shock_construction.R: Constructs another of the shock based on the plot end-date for large post-2019 housing sites,  maps sites to output areas, and exports OA-level shock data.

4_search_cw.R: Assigns LSOA, MSOA, LA, and TTWA to OA-level weekly search data.

4_sd_control_dataset_construction.R: Constructs the control OA–week dataset by excluding all output areas intersecting shocked MSOAs and outputs a weekly search panel for untreated OAs data.

4_ed_control_dataset_construction.R: Constructs the control OA–week dataset using end-date shocks by excluding all output areas intersecting shocked MSOAs and exporting the untreated weekly OA data.

# 4.2- Analsis

1_ed_pooled_reg_dataset_construction.R: Builds a stacked event-study regression dataset for end-date construction shocks by pairing treated OAs to the controls from 4_ed_control_dataset_construction.R within the same TTWA, and prepares the pooled event study dataset.

1_sd_pooled_reg_dataset_construction.R: Builds a stacked event-study regression dataset for start-date construction shocks by pairing treated OAs with TTWA-matched controls from 4_sd_control_dataset_construction.R, and exports the pooled event-study panel dataset.

2_common_sites_reg_and_plot.R: Runs the pooled event-study regression on buying searches for construction sites common to both start-date and end-date regression datasets and generates the event-study plot in the paper.
