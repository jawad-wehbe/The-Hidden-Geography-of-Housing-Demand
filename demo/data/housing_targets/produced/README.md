# produced/
Intermediate datasets and estimates written by the pipeline. Only `gap/` is shipped; the rest appear when `demo/run_demo.R` runs.

- `gap/` shipped input: OA demand-gap statistics and LA targets read by the maps, and random OA asking prices read by descriptives/3 (made by generator 7, not by the pipeline)
- `search_on_build_shock/setup/` NHBC construction shocks per OA, start-date (SD) and end-date (ED) versions (3_sd, 3_ed)
- `hidden_geography_of_housing_demand/nonbots/all/` weekly OA search panel, control sets and pooled regression datasets for all users (2, 4, 5, 6); supply-shock estimates (7)
- `hidden_geography_of_housing_demand/nonbots/saved/`, `contacted/`, `contacted_and_saved/` the same weekly panel for each user subset (descriptives)
- `hidden_geography_of_housing_demand/nonbots/saved_or_contacted/` panel, control sets and estimates for the robustness sample
- `hidden_geography_of_housing_demand/nonbots/regression_datasets/` greenspace, flood and new-build regression datasets (8_b, 9, 10)
- `hidden_geography_of_housing_demand/nonbots/regression_results/` tidy event-study estimates as CSV (8_b, 9, 10)
