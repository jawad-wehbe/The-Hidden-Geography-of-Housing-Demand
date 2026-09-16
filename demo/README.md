# Demo: running the full pipeline on a small synthetic dataset

This folder lets anyone run every script of *The Hidden Geography of Housing Demand*
end to end without access to the licensed raw data. The instructions below are written
for RStudio. **For ease of running, we recommend opening the project file (hidden_geography_of_housing_demand.Rproj) and source two scripts from the console, with
no terminal or PATH setup.** It contains

| Path | What it is |
|---|---|
| `setup.R` | installs the R and Python packages, run from the RStudio console |
| `run_demo.R` | runs the full pipeline from the RStudio console (calls `setup.R` first) |
| `run_demo_main.R` | the same for the main analysis and maps only (no descriptives, no robustness), a third of the time |
| `data/` | the demo dataset, pre-built (about 30 MB), plus the folders the pipeline writes into |
| `install_packages.R`, `requirements.txt` | R and Python package installers |

The analysis code that runs is the pipeline in the parent folders
(`nonbots_main_analysis`, `descriptives`, `robustness`, `maps`) is unchanged. The only
difference between a real run and a demo run is which data folders `config.R` and
`config.py` point at (the names of the authors' real search data sit in a local config
file that is not distributed).

System requirements and the installation guide are in the repository's main
[`README.md`](../README.md). Install first, then run the demo as described below.

---

## 1. Demo

### Run it

From the RStudio console, with `hidden_geography_of_housing_demand.Rproj` open:

```r
source("demo/run_demo.R")          # full pipeline (35 scripts)
source("demo/run_demo_main.R")     # main analysis and maps only (18 scripts), a third of the time
```

`run_demo_main.R` leaves out the descriptives and robustness groups, which each rebuild
the search panel for a user subset and account for most of the run time.

Each runner first sources `demo/setup.R` (so packages are installed if they are not
already), then sets `HOUSING_DEMO=1`, creates the output folders, and runs the scripts in
order, which should print one line per script with its run time, like this:

```
Demo run started ...
nonbots_main_analysis/1_search_by_location.py                               ok  3s
nonbots_main_analysis/2_location_to_oa.py                                   ok  209s
...
Demo run finished ...  total 13 min
```

A script's own output is not shown unless it fails. To see each scripts own output, see below "Running individual scripts".

**Every figure, table and intermediate dataset is saved within `demo/` too**, under
`demo/data/housing_targets/output/` and `demo/data/housing_targets/produced/` (see
"Expected output" below).

In case you would like to run the scripts without needing the RStudio: from any
R or RStudio console, `setwd("path to the unzipped folder")` (the folder that holds
`config.R`) and then `source("demo/run_demo.R")`. The run should work the same way.

### Running individual scripts

To run individual scripts or to start from a specific script, type in console the following:

- `from <- "9_floods"; source("demo/run_demo.R")` resumes at the first script whose
  name contains the text and continues to the end.
- `only <- "9_floods"; source("demo/run_demo.R")` runs just that one script.

Both work the same way with `run_demo_main.R`, for example
`only <- "9_floods"; source("demo/run_demo_main.R")`.

Both are cleared after the run, so the next plain `source()` starts from the top again.

When running an individual script, make sure the data it needs from earlier scripts is
already there under `demo/data`.

**To see a script's console output (for example the rank-rank correlations), source it
directly in the console.** The working directory must be the repository folder (the one
that holds `config.R`): open `hidden_geography_of_housing_demand.Rproj` first, or set it
by hand with `setwd()`. Then set the demo switch and source the script:

```r
setwd("path to the unzipped folder")   # not needed if the .Rproj is open
Sys.setenv(HOUSING_DEMO = "1")
source("descriptives/2_rank_rank_correlations_buying_searches.R")
```

The script reads files written by earlier steps, so run the pipeline first (the
rank-rank script needs the four search panels from the descriptives group, which
`run_demo.R` produces and `run_demo_main.R` does not).

### Expected run time

About 10 to 15 minutes on a laptop with 16 GB of RAM, most of it in the five
`2_location_to_oa.py` scripts, which loop over 283 weeks one at a time exactly as they
do on the real data. 

### Expected output

**All outputs are saved inside the demo folder as well**, under `demo/data/housing_targets/` (figures and tables in `output/`, intermediate datasets and estimates in `produced/`). Nothing is written outside the repository:

| Output | Path (under `output/` or `produced/`) | Produced by |
|---|---|---|
| Supply-shock event study, figure and tidy estimates | `output/figures/hidden_geography_of_housing_demand/nonbots/nonbots_all_sd_filtered_pooled_buying.png`, `produced/hidden_geography_of_housing_demand/nonbots/all/supply_shock_all_eventstudy_results_tidy.csv` | `nonbots_main_analysis/7` |
| Greenspace event studies: weekly log searches, monthly IHS transactions, monthly log prices | `output/figures/hidden_geography_of_housing_demand/nonbots/greenspace_weekly_log_search_*.png`, `greenspace_monthly_ihs_trans_*.png`, `greenspace_monthly_log_price_*.png`; estimates in `produced/hidden_geography_of_housing_demand/nonbots/regression_results/greenspace_*.csv` | `nonbots_main_analysis/8_b`, re-plotted by `8_c` |
| Flood event studies: weekly log searches, monthly IHS transactions, monthly log prices | `output/figures/hidden_geography_of_housing_demand/nonbots/searches_weekly_log_flood_*.png`, `transactions_monthly_ihs_flood_*.png`, `prices_monthly_log_flood_*.png`; estimates in `produced/hidden_geography_of_housing_demand/nonbots/regression_results/*flood*.csv` | `9` |
| New-build monthly event study | `output/figures/hidden_geography_of_housing_demand/nonbots/greenspace_new_builds_monthly_*.png` and its CSV | `10` |
| Search data summary statistics table | `output/tables/hidden_geography_of_housing_demand/summary_table.tex` | `descriptives/1` |
| Rank-rank correlations across user samples | printed to the console, so source the script in RStudio to see them (see "Run it" above; after `run_demo.R` has produced the four search panels) | `descriptives/2` |
| Asking price against demand gap: two scatters | `output/figures/hidden_geography_of_housing_demand/descriptives/rental_price_vs_gap.png`, `sales_price_vs_gap.png` | `descriptives/3` |
| Robustness (saved-or-contacted users): supply shock, floods, greenspace | `output/figures/hidden_geography_of_housing_demand/nonbots/saved_or_contacted/*.png`, estimates in `produced/hidden_geography_of_housing_demand/nonbots/saved_or_contacted/*.csv` | `robustness/saved_or_contacted/5, 6, 7` |
| Local authority gap map (Calderdale) | `output/figures/hidden_geography_of_housing_demand/nonbots/maps/E08000033_Calderdale_la_gap_per_km2.png` | `maps/1` |
| Gap rank map (in the demo, zoomed to the 126 demo OAs rather than the whole of Great Britain) | `output/figures/hidden_geography_of_housing_demand/nonbots/maps/gap_rank_map.png` | `maps/2` |
| Flood maps (Storm Ciara, 2020): baseline searches per km² in week -1, and % log change in searches per km² between weeks +4 and -1 | `output/figures/hidden_geography_of_housing_demand/nonbots/maps/flood_map_searchlevels_wkm1.png`, `flood_map_searchdiff_wkp4_vs_wkm1_logpct_winsorized_99.png` | `maps/3` |

In total 17 figures, one LaTeX table and 13 estimate CSVs. Every file has the same
name and location (relative to the project root) as in the real run.

### What the demo data are, and what the results mean

The demo covers six MSOAs of Calderdale (126 output areas), Jan 2019 to May 2024. Two
kinds of input are mixed:

- **Real, open-licence geography**, clipped to the area: ONS output-area polygons and
  crosswalks, local-authority and travel-to-work-area boundaries, Environment Agency
  recorded flood outlines. These are the only real records in the demo.
- **Synthetic everything else**: property searches, sessions and views (with invented
  user, session and property ids), the location-to-OA share table, NHBC sites and plots,
  OS land-use plots, buildings and address points, ONSPD postcodes, HMLR transactions,
  and the OA gap statistics used by the maps. All were drawn from a fixed seed
  (20250910) by a set of generator scripts that are not part of this repository.
  Each file carries only the columns the pipeline reads, with the real column
  names and types.

**No effects are planted. Searches, transactions and prices are drawn from the same
distribution in every output area and week. The event studies therefore estimate
nothing but noise, and their figures show flat, wide-banded paths around zero. That is
the expected output: the demo shows that every script runs and produces every file,
not that the paper's estimates are recovered. The paper's estimates need the licensed
data.**

---

## 2. Demo of the paper's results

| Element of the paper | Script | Output |
|---|---|---|
| Supply-shock event study (buying searches around construction start) | `nonbots_main_analysis/7_supply_shock_reg.R` | `nonbots_all_sd_filtered_pooled_buying.png`, `supply_shock_all_eventstudy_results_tidy.csv` |
| Greenspace event studies (searches weekly; transactions and prices monthly) | `8_a` (measure), `8_b` (regressions), `8_c` (figures) | `greenspace_*.png`, `regression_results/greenspace_*.csv` |
| Flood event studies (searches weekly; transactions and prices monthly) | `9_floods_reg.R` | `*_flood_ttwaxy*_oa_fe.png` and `.csv` |
| New-build event study (monthly) | `10_newly_built_reg.R` | `greenspace_new_builds_monthly_*.png` and `.csv` |
| Search data summary statistics table | `descriptives/1_search_descriptives.py` | `summary_table.tex` |
| Rank-rank correlations of search volumes across user samples | `descriptives/2_rank_rank_correlations_buying_searches.R` | printed |
| Asking prices against the demand gap | `descriptives/3_price_vs_gap.R` | `descriptives/*.png` |
| Robustness on saved-or-contacted users | `robustness/saved_or_contacted/5, 6, 7` | `saved_or_contacted/*.png`, `*.csv` |
| Local-authority gap maps, GB gap-rank map (the demo draws it for the demo area only, not Great Britain), Storm Ciara search maps | `maps/1`, `maps/2`, `maps/3` | `maps/*.png` |

---

## 3. Licence and data attribution

Code and demo dataset: Creative Commons Attribution-NonCommercial-ShareAlike 4.0
International (CC BY-NC-SA 4.0), see `LICENSE` in the repository root.

The demo dataset includes data derived from: Office for National Statistics licensed
under the Open Government Licence v3.0 (output-area boundaries and lookups, local
authority and travel-to-work-area boundaries; contains OS data © Crown copyright and
database right 2025) and Environment Agency Recorded Flood Outlines © Environment
Agency copyright and database right 2025, Open Government Licence v3.0. All other demo
data are synthetic and carry no third-party rights.
