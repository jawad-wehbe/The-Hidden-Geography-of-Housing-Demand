##############################################################################
# DEMO RUNNER, MAIN ANALYSIS ONLY: runs the main analysis and the maps from
# inside R (RStudio). Leaves out descriptives/ (summary table, rank-rank
# correlations and their three user subsets) and robustness/ (saved-or-contacted
# users), which run_demo.R includes. About a third of the full run time.
#
# Open hidden_geography_of_housing_demand.Rproj in RStudio, then in the console:
#   source("demo/run_demo_main.R")                        # main analysis and maps
#   from <- "9_floods"; source("demo/run_demo_main.R")    # resume at the first step containing this text
#   only <- "9_floods"; source("demo/run_demo_main.R")    # run just the first step containing this text
#
# The first thing it does is source demo/setup.R, which installs any missing
# R and Python packages. Each script then runs in its own R or Python process
# with HOUSING_DEMO=1, so every path resolves to demo/data. A script's output
# is discarded unless it fails, in which case its last lines are printed.
# Maps 1 and 2 download OpenStreetMap tiles and labels, so they need internet.
##############################################################################

if (!exists("from"))      from      <- ""
if (!exists("only"))      only      <- ""

if (!file.exists("config.R")) stop("Run this from the repository root (open hidden_geography_of_housing_demand.Rproj in RStudio first)")

# Windows limits file paths to 260 characters, and the demo writes files up to about
# 185 characters below the repository root, so the root itself must be short.
if (.Platform$OS.type == "windows" && nchar(normalizePath(".")) > 70) {
  stop("The repository folder path is ", nchar(normalizePath(".")), " characters long: ", normalizePath("."),
       "\nWindows limits paths to 260 characters and the demo writes files up to 185 characters below this folder.",
       "\nMove the folder to a short path such as C:\\hgohd (no nested folders) and reopen the project there.")
}

source(file.path("demo", "setup.R"))

Sys.setenv(HOUSING_DEMO = "1")
rscript <- file.path(R.home("bin"), "Rscript")
# python and py_pre come from demo/setup.R, sourced above

############
# Output folders the scripts expect to exist
############

for (d in c("housing_targets/produced/gap",
            "housing_targets/produced/search_on_build_shock/setup",
            "housing_targets/produced/hidden_geography_of_housing_demand/nonbots/all",
            "housing_targets/produced/hidden_geography_of_housing_demand/nonbots/regression_datasets",
            "housing_targets/produced/hidden_geography_of_housing_demand/nonbots/regression_results",
            "housing_targets/temp/hidden_geography_of_housing_demand/spill_dir",
            "housing_targets/temp/duckdb_spill",
            "housing_targets/output/tables/hidden_geography_of_housing_demand",
            "housing_targets/output/figures/hidden_geography_of_housing_demand/nonbots/maps",
            "housing_search/produced/nonbots",
            "Raw_Data/search", "Raw_Data/NHBC", "Raw_Data/HMLR")) {
  dir.create(file.path("demo", "data", d), recursive = TRUE, showWarnings = FALSE)
}

############
# Scripts in run order
############

main_steps <- c(
  "nonbots_main_analysis/1_search_by_location.py",
  "nonbots_main_analysis/2_location_to_oa.py",
  "nonbots_main_analysis/3_ed_shock_construction.R",
  "nonbots_main_analysis/3_sd_shock_construction.R",
  "nonbots_main_analysis/4_search_to_cw.R",
  "nonbots_main_analysis/5_ed_control_dataset_construction.R",
  "nonbots_main_analysis/5_sd_control_dataset_construction.R",
  "nonbots_main_analysis/6_ed_pooled_reg_dataset_construction.R",
  "nonbots_main_analysis/6_sd_pooled_red_dataset_construction.R",
  "nonbots_main_analysis/7_supply_shock_reg.R",
  "nonbots_main_analysis/8_a_private_greenspace_calculation.R",
  "nonbots_main_analysis/8_b_greenspace_reg.R",
  "nonbots_main_analysis/8_c_greenspace_figure_plotting.R",
  "nonbots_main_analysis/9_floods_reg.R",
  "nonbots_main_analysis/10_newly_built_reg.R"
)

map_steps <- c(
  "maps/1_main_report_la_maps.R",
  "maps/2_gb_map_gap_rank.R",
  "maps/3_transactions_searches_maps.R"
)

steps <- c(main_steps, map_steps)
if (from != "") steps <- steps[seq(min(grep(from, steps, fixed = TRUE)), length(steps))]
if (only != "") steps <- steps[min(grep(only, steps, fixed = TRUE))]
rm(from, only)                                  # so the next source() starts from the top again

############
# Run
############

repo  <- normalizePath(".")
t_all <- Sys.time()
cat("Demo run (main analysis and maps) started", format(t_all), "\n")

for (step in steps) {
  script <- file.path(repo, step)
  log    <- tempfile(fileext = ".log")
  t0     <- Sys.time()
  cat(sprintf("%-75s ", step))

  status <- if (grepl("\\.R$", step)) {
    system2(rscript, shQuote(script), stdout = log, stderr = log)
  } else {
    system2(python, c(py_pre, shQuote(script)), stdout = log, stderr = log)
  }

  secs <- round(as.numeric(difftime(Sys.time(), t0, units = "secs")))
  if (status != 0) {
    cat("FAILED after", secs, "s\n")
    cat(tail(readLines(log, warn = FALSE), 20), sep = "\n")
    unlink(log)
    stop("stopped at ", step)
  }
  unlink(log)
  cat("ok ", secs, "s\n")
}

cat("Demo run finished", format(Sys.time()), " total",
    round(as.numeric(difftime(Sys.time(), t_all, units = "mins"))), "min\n")
