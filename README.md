# The Hidden Geography of Housing Demand

Code for the paper, plus a demo dataset on which the whole pipeline runs in about 10 to 15
minutes without any licensed data. The real data cannot be shared: they are held under
a data-sharing agreement.
The processed search database alone is 1.3 TB.

- **System requirements and installation:** the two sections below.
- **Running the demo and its expected output:** see [`demo/README.md`](demo/README.md).
- **Note: Demo results will not match the paper's results.** The demo data are synthetic and
  were generated to have the same means as the real data, but the real dataset is much larger. The demo is a demonstration of the code and of what each script
  produces, not a reproduction of the estimates.
- **Licence:** CC BY-NC-SA 4.0 for the code and demo dataset (`LICENSE`); demo geography
  under the Open Government Licence.

---

## System requirements

**Software.**

| Software | Version tested |
|---|---|
| R | 4.3.3 |
| Python | 3.12.3 |
| GEOS / GDAL / PROJ (used by `sf`) | 3.12.1 / 3.8.4 / 9.4.0 |

**R packages** (versions tested): here 1.0.2, dplyr 1.2.1, tidyr 1.3.2, readr 2.2.0,
stringr 1.6.0, purrr 1.2.2, tidyverse 2.0.0, lubridate 1.9.5, ISOweek 0.6-2, janitor 2.2.1,
glue 1.8.0, zoo 1.8-15, haven 2.5.5, data.table 1.18.2, arrow 23.0.1, duckdb 1.5.1,
DBI 1.3.0, sf 1.1-0, lwgeom 0.2-15, stars 0.7-2, units 1.0-1, osmdata 0.3.0,
osmextract 0.6.0, maptiles 0.11.0, mapview 2.11.4, ncdf4 1.24, ncmeta 0.4.0, fixest 0.14.0,
broom 1.0.12, multcomp 1.4-30, survival 3.5-8, penppml 0.2.4, knitr 1.51, ggplot2 4.0.2,
ggrepel 0.9.8, ggspatial 1.1.10, ggmap 4.0.2, patchwork 1.3.2, scales 1.4.0, viridis 0.6.5,
RColorBrewer 1.1-3, tmap 4.3, leaflet 2.2.3, prettymapr 0.2.5, png 0.1-9, htmlwidgets 1.6.4,
webshot 0.5.5, future 1.70.0, future.apply 1.20.2, furrr 0.4.0, future.callr 0.10.2,
progressr 0.19.0.

**Python packages** (versions tested): duckdb 1.5.1, polars 1.39.3, pandas 3.0.2,
numpy 2.2.6, pyarrow 23.0.1, jinja2, matplotlib.

**Hardware.**

| | Demo | Real data |
|---|---|---|
| RAM | 8 GB is enough | 1.2 TB on the server we used |
| Disk | 200 MB | several TB for the raw search data |

The demo needs no non-standard hardware: any laptop with 8 GB of RAM will do. The real
run does: it was carried out on a server with 1.2 TB of RAM and several TB of disk.

---

## Installation guide

1. Install R (4.3 or later), RStudio, and Python (3.10 or later, from python.org; on Windows
   tick "Add python.exe to PATH" in the installer).
2. Download the repository (**Code > Download ZIP** on the GitHub page) and unzip it, or clone
   `https://github.com/jawad-wehbe/The-Hidden-Geography-of-Housing-Demand`.
3. Open `hidden_geography_of_housing_demand.Rproj` in the unzipped folder. RStudio sets the working directory
   to the repository root, so no paths or PATH variables need setting.
4. In the RStudio console:
   ```r
   source("demo/setup.R")
   ```
   This installs every R package the pipeline uses (skipping those already present) and the
   seven Python packages, into the Python it finds on the machine. If Python is not found, the script will stop
   and say so.
5. Nothing needs editing. The scripts find the repository root through the empty
   `.here` marker file and read every path from `config.R` / `config.py`.

Typical install time: 10 minutes.

To run the code, see [`demo/README.md`](demo/README.md).

---

The rest of this file describes the scripts, folder by folder.

## Each directory has its own detailed README file; however, below is an overview of the project

# 1- Maps

1_main_report_la_maps.R: Produces the local authority gap maps in the main paper. One image per LA is saved as {la_code}_{la_name}_la_gap_per_km2.png.

2_gb_map_gap_rank.R: Creates the GB-wide gap rank map in the main report. Saved as gap_rank_map.png.

3_transactions_searches_maps.R: Maps how OA-level buying searches move around a chosen flood event (Storm Ciara, 2020) within a single local authority, plotting changes in searches per km² across event weeks with flooded OA boundaries and transactions overlaid.

# 2- Descriptives

1_search_descriptives.py: Produces the search data summary statistics table used in the main paper. Results are assembled into a single table and exported as LaTeX (summary_table.tex).

2_rank_rank_correlations_buying_searches.R: Collapses each weekly OA search panel to total buying searches per OA, then reports the rank-rank correlation matrix across the four user samples — all non-bot users, users who saved a property, users who contacted an estate agent, and users who did both — on the set of OAs present in all four. The all panel comes from nonbots_main_analysis; the other three are produced by the subfolders below.

3_price_vs_gap.R: Merges the combined demand gap per km² with the average 2024 rental and sales asking prices per OA and plots price against gap as scatters.

# 2.1 - Serious Searches Samples

Three subfolders: saved, contacted, and contacted_and_saved. Each contain the same three scripts as the main search panel construction in nonbots_main_analysis, differing only in which users are kept and where the output is written:

| Subfolder | Users retained | Output |
|---|---|---|
| `saved` | Saved at least one property | `produced/hidden_geography_of_housing_demand/nonbots/saved/oa_weekly_search.parquet` |
| `contacted` | Sent at least one email to an agent | `produced/hidden_geography_of_housing_demand/nonbots/contacted/oa_weekly_search.parquet` |
| `contacted_and_saved` | Both saved a property and contacted an agent | `produced/hidden_geography_of_housing_demand/nonbots/contacted_and_saved/oa_weekly_search.parquet` |


1_search_by_location.py: Aggregates weekly buying and letting search counts by search location and radius filter for the subfolder's user sample, and saves one Parquet file per search type.

2_location_to_oa.py: Identifies all year–week combinations in that sample's search data, sequentially runs 2_location_to_oa_batch.py for each, and combines the weekly CSVs into the sample's OA-week search panel.

2_location_to_oa_batch.py: For a single year–week, apportions the sample's location-level searches to output areas using the location-to-OA share crosswalk, and writes the weekly OA-level CSV.

# 3- Nonbots Main Analysis
This folder contains the full event-study pipeline linking property searches (non-bot sessions) to construction supply shocks, private greenspace, floods, and new builds at the output area (OA) level. Scripts are numbered in execution order.

1_search_by_location.py: Aggregates weekly buying and letting search counts by search location and radius filter from the filtered (non-bot) search database, and saves one Parquet file per search type.

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


# 4- Robustness

Replication of the main event studies on a restricted "serious user" sample: only search-data users who saved a property or contacted an agent at least once. The pipeline mirrors nonbots_main_analysis but writes to a separate saved_or_contacted output folder throughout, so the two sets of results can be compared directly.

1_search_by_location.py: Aggregates weekly buying and letting search counts by search location and radius, restricted to users who saved a property or sent at least one email in the matching session table, and saves one Parquet file per search type.

2_location_to_oa.py: Identifies all year–week combinations in the restricted search data, sequentially runs 2_location_to_oa_batch.py for each, and combines the weekly CSVs into the saved-or-contacted OA-week search panel.

2_location_to_oa_batch.py: For a single year–week, apportions the restricted location-level searches to output areas using the location-to-OA share crosswalk, and writes the weekly OA-level CSV.

3_search_to_cw.R: Assigns each OA in the restricted weekly panel to its LSOA, MSOA, LA, and TTWA, producing the geography-augmented panel used by the remaining robustness scripts.

4_ed_control_dataset_construction.R / 4_sd_control_dataset_construction.R: Construct the control OA-week datasets for the end-date and start-date construction shocks respectively, excluding every output area intersecting an MSOA touched by a shocked OA. Both reuse the shock files built in nonbots_main_analysis (3_ed_shock_construction.R and 3_sd_shock_construction.R).

5_common_sites_reg_and_plot.R: Runs the supply shock event study on the restricted sample, using the construction sites common to both the end-date and start-date pooled datasets and an event window capped at 44 weeks post treatment. Exports the tidy event-study estimates and the corresponding figures, and repeats the regression on a subsample of sites selected on pre-period search activity.

6_searches_flood_event_study.R: Repeats the flood event study on the restricted sample — identifying flooded output areas from the England and Wales recorded flood outlines, building the weekly regression panel, estimating the event study on buying searches, and exporting the estimates and figure.

7_searches_private_greenspace_event_study.R: Repeats the private greenspace event study on the restricted sample, using the OA greenspace measure computed in nonbots_main_analysis (8_a_private_greenspace_calculation.R), and exports the weekly estimates and figure.
