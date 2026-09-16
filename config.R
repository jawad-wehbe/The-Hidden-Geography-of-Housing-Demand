##############################################################################
# config.R  -  single place where every data path is rooted
#
# Sourced at the top of every script:   source(file.path(here(), "config.R"))
#
# Two modes, chosen automatically:
#   real run : the project folder ~/Desktop/Projects/housing_targets exists
#              -> paths point at the real raw data and produced outputs
#   demo run : that folder does not exist (another machine), or the
#              environment variable HOUSING_DEMO is "1" (set by demo/run_demo.R)
#              -> paths point inside demo/data/ of this repository
#
# Scripts never hard-code "~/Desktop/..." any more; they build paths from the
# roots below with file.path(). Nothing else in the scripts changes.
##############################################################################

library(here)

repo_root <- here()                                   # the folder that holds .here

real_project_root <- "~/Desktop/Projects/housing_targets"

use_demo <- Sys.getenv("HOUSING_DEMO") == "1" | !dir.exists(path.expand(real_project_root))

if (use_demo) {
  raw_root      <- file.path(repo_root, "demo", "data", "Raw_Data")
  project_root  <- file.path(repo_root, "demo", "data", "housing_targets")
  search_root   <- file.path(repo_root, "demo", "data", "housing_search")
  n_threads     <- 2
  duckdb_memory <- "4GB"
  # the search data: folder of raw search inputs and the two DuckDB files
  search_raw_dir      <- file.path(raw_root, "search")
  search_filtered_db  <- file.path(search_root, "produced", "nonbots", "search_filtered.duckdb")
  search_processed_db <- file.path(search_raw_dir, "search_processed.duckdb")
} else {
  raw_root      <- "~/Desktop/Raw_Data"
  project_root  <- real_project_root
  search_root   <- "~/Desktop/Projects/housing_search"
  n_threads     <- 20
  duckdb_memory <- "150GB"
  # the real search data are named in config_local.R, which is not distributed:
  # it must define search_raw_dir, search_filtered_db and search_processed_db
  config_local <- file.path(repo_root, "config_local.R")
  if (!file.exists(config_local)) stop("Real mode needs ", config_local, " defining search_raw_dir, search_filtered_db and search_processed_db")
  source(config_local)
}

shapefiles_root <- file.path(raw_root, "Shapefiles")
duckdb_spill    <- file.path(project_root, "temp", "duckdb_spill")

cat("config.R: ", if (use_demo) "DEMO" else "REAL", " mode\n",
    "  raw_root     = ", raw_root, "\n",
    "  project_root = ", project_root, "\n",
    "  search_root  = ", search_root, "\n", sep = "")
