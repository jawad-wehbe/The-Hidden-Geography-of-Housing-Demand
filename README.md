
# Description
# Event Study Setup
1_search_by_location.py: Aggregates weekl  property search counts by location and search radius for buying and letting searches, and saves the results as Parquet files.
2_location_to_oa_batch.py: Maps weekly buying and letting searches output areas, outputs weekly CSVs, and combines them into a single Parquet file.
2_location_to_oa.py: Identifies all year–week combinations in weekly search data and sequentially runs the previous batch script to map searches to output areas.
3_sd_shock_construction.R: Constructs the site-level shock based on first plot start dates for large post-2019 sites, maps shocks to output areas, and exports the resulting OA-level shock data.
3_ed_shock_construction.R: Constructs another of the shock based on the plot end-date for large post-2019 housing sites,  maps sites to output areas, and exports OA-level shock data.
4_sd_control_dataset_construction.R: Constructs the control OA–week dataset by excluding all output areas intersecting shocked MSOAs and outputs a weekly search panel for untreated OAs data.
4_ed_control_dataset_construction.R: Constructs the control OA–week dataset using end-date shocks by excluding all output areas intersecting shocked MSOAs and exporting the untreated weekly OA data.
